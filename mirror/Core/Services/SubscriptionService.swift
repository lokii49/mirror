import RevenueCat
import SwiftUI

enum SubscriptionTier: String {
    case free
    case core
    case deep
}

@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    // TEMPORARY: unlock every tier for every user, no purchase required.
    // Flip to false to restore normal RevenueCat-driven gating.
    static let allFeaturesFree = true

    private(set) var tier: SubscriptionTier = allFeaturesFree ? .deep : .free
    private(set) var corePackages: [Package] = []
    private(set) var deepPackages: [Package] = []
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?
    /// Set when offerings couldn't be fetched, so the paywall offers a retry instead of a spinner.
    private(set) var productsLoadFailed = false
    /// Product IDs whose introductory offer (the 7-day trial) this Apple ID can still use. Apple
    /// gives one trial per subscription group, and all four products share one group, so after a
    /// Core trial Deep has none: the paywall must not promise it.
    private(set) var trialEligibleProductIDs: Set<String> = []
    /// Subscriptions active on this Apple ID right now, from the latest customer info.
    private(set) var activeProductIDs: Set<String> = []
    /// One-line result of a Restore tap that found nothing to restore (not an error).
    private(set) var restoreMessage: String?

    #if DEBUG
    /// Snapshot mode only: lets the Mac UI be checked in each plan without a purchase.
    func debugSetTier(_ newTier: SubscriptionTier) { tier = newTier }
    #endif

    var isSubscribed: Bool { tier != .free }
    var isDeep: Bool { tier == .deep }

    /// Ask questions a month: none on Free, 15 on Core, unlimited on Deep (CLAUDE.md tiers).
    static func askMonthlyLimit(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: 0
        case .core: 15
        case .deep: .max
        }
    }

    /// Talk It Out is offered on Core and Deep only. Free users don't see it at all, so it never
    /// shows a paywall before the first nudge (CLAUDE.md, staged onboarding; owner, 2026-10-11).
    static func offersTalkItOut(for tier: SubscriptionTier) -> Bool {
        tier != .free
    }

    private init() {
        // Widgets read the tier from the app group and treat a missing key as "free". With
        // everything free the answer is known now, so write it before RevenueCat replies (or
        // fails, offline): otherwise the widgets show a locked view with a price.
        if Self.allFeaturesFree { Self.publishTierToWidgets(.deep) }
        // Paid tiers: start from RevenueCat's cached customer info so a cold launch (a background
        // refresh, the nightly task) doesn't treat a subscriber as Free until the network answers
        // and skip their digest, report or mood alert. Purchases is configured before this runs.
        else if let cached = Purchases.shared.cachedCustomerInfo { updateTier(from: cached) }
        Task {
            // First, so the sync and refresh below already run as the iCloud account's customer
            // (where any granted entitlement lives) rather than this install's anonymous one.
            await RevenueCatIdentity.logInWithICloudAccount()
            // RevenueCat: restorePurchases "may force your users to enter the App Store password
            // so should only be performed on request of the user" (5.89.0 docs), so launch uses
            // the silent syncPurchases instead (owner, 2026-10-11); the Restore buttons keep
            // restorePurchases. While every feature is free the result is thrown away anyway
            // (`updateTier`), so launch skips it.
            if !Self.allFeaturesFree { await syncPurchasesSilently() }
            await refresh()
            // Warm the paywall: RevenueCat caches offerings, so the first open shows plans, not
            // "Loading plans…". Skipped while everything is free (the paywall never shows).
            if !Self.allFeaturesFree { await loadProducts() }
        }
        // Follow every customer info change while the app runs: RevenueCat refreshes it on
        // foreground, so a purchase made on another device with the same App Store account,
        // an expiry or a refund reaches the tier without a relaunch or a Settings visit.
        Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                self?.updateTier(from: customerInfo)
            }
        }
    }

    var hasProducts: Bool { !corePackages.isEmpty || !deepPackages.isEmpty }

    func isTrialEligible(_ package: Package) -> Bool {
        trialEligibleProductIDs.contains(package.storeProduct.productIdentifier)
    }

    /// Clears the previous attempt's messages when the paywall opens again (this is a singleton).
    func clearMessages() {
        purchaseError = nil
        restoreMessage = nil
    }

    func loadProducts() async {
        productsLoadFailed = false
        do {
            let offerings = try await Purchases.shared.offerings()
            corePackages = (offerings.offering(identifier: "core")?.availablePackages
                ?? offerings.current?.availablePackages.filter {
                    $0.storeProduct.productIdentifier.contains("core")
                } ?? [])
                .sorted { $0.storeProduct.price < $1.storeProduct.price }
            deepPackages = (offerings.offering(identifier: "deep")?.availablePackages
                ?? offerings.current?.availablePackages.filter {
                    $0.storeProduct.productIdentifier.contains("deep")
                } ?? [])
                .sorted { $0.storeProduct.price < $1.storeProduct.price }
            await loadTrialEligibility()
        } catch {
            // A cached list from an earlier load is still good; only an empty paywall needs a retry.
            productsLoadFailed = !hasProducts
        }
    }

    private func loadTrialEligibility() async {
        let packages = corePackages + deepPackages
        guard !packages.isEmpty else { return }
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: packages)
        // `.unknown` is what a first-time user with no receipt yet gets, so it counts as eligible;
        // only a definite "ineligible" or "no offer" hides the trial.
        trialEligibleProductIDs = Set(packages.compactMap { package in
            guard package.storeProduct.introductoryDiscount != nil else { return nil }
            switch eligibility[package]?.status {
            case .ineligible, .noIntroOfferExists: return nil
            default: return package.storeProduct.productIdentifier
            }
        })
    }

    func purchase(_ package: Package) async {
        isPurchasing = true
        clearMessages()
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return }
            updateTier(from: result.customerInfo)
        } catch ErrorCode.purchaseCancelledError {
            // Closing the App Store sheet is a choice, not a failure: no red text.
        } catch ErrorCode.paymentPendingError {
            purchaseError = String(localized: "Waiting for approval. Your plan starts as soon as the purchase is approved.")
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        clearMessages()
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateTier(from: customerInfo)
            if customerInfo.entitlements.active.isEmpty {
                restoreMessage = String(localized: "No active subscription found for this Apple ID.")
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// Launch-time sync: no password prompt, and a failure stays quiet (no `purchaseError`),
    /// since the user didn't ask for anything. `refresh()` runs right after either way.
    private func syncPurchasesSilently() async {
        if let customerInfo = try? await Purchases.shared.syncPurchases() {
            updateTier(from: customerInfo)
        }
    }

    func refresh() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            updateTier(from: customerInfo)
            #if DEBUG
            print("[RC] customerID: \(customerInfo.originalAppUserId)")
            print("[RC] activeEntitlements: \(customerInfo.entitlements.active.keys.joined(separator: ", "))")
            print("[RC] tier: \(tier)")
            #endif
        } catch {
            #if DEBUG
            print("[RC] refresh error: \(error.localizedDescription)")
            print("[RC] full error: \(error)")
            #endif
        }
    }

    private func updateTier(from customerInfo: CustomerInfo) {
        activeProductIDs = customerInfo.activeSubscriptions
        guard !Self.allFeaturesFree else {
            tier = .deep
            Self.publishTierToWidgets(tier)
            return
        }
        if customerInfo.entitlements["deep"]?.isActive == true {
            tier = .deep
        } else if customerInfo.entitlements["core"]?.isActive == true {
            tier = .core
        } else {
            tier = .free
        }
        Self.publishTierToWidgets(tier)
    }

    private static func publishTierToWidgets(_ tier: SubscriptionTier) {
        UserDefaults(suiteName: WidgetShared.appGroupID)?.set(tier.rawValue, forKey: "widget.tier")
    }
}
