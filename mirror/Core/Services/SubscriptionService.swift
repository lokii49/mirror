import RevenueCat
import SwiftUI
import WidgetKit

enum SubscriptionTier: String {
    case free
    case core
    case deep
}

@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    /// Every tier for every user, no purchase required, until paid plans start on 15 November
    /// 2026 (`FeatureCardRegistry.paidPlansStart`, the date the notice gives). By date, not a
    /// flag: the paid build is approved and installed before then, and must not gate anyone
    /// early (3.1.6, 2026-10-20).
    static var allFeaturesFree: Bool {
        #if DEBUG
        // Unit tests that generate insights assume a paid tier, and the gating tests set theirs
        // with `debugSetTier`; without this, they'd turn Free on 15 November, or follow
        // whichever sandbox account the simulator has.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        #endif
        return allFeaturesFree(now: Date())
    }

    static func allFeaturesFree(now: Date) -> Bool {
        now < FeatureCardRegistry.paidPlansStart
    }

    private(set) var tier: SubscriptionTier = allFeaturesFree ? .deep : .free
    /// The tier came from the free period, not from RevenueCat; checked again on app-active so an
    /// app left running into 15 November doesn't stay Deep until it's relaunched.
    private var tierFromFreePeriod = SubscriptionService.allFeaturesFree
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
    /// RevenueCat's current app user ID, for the support row in Settings. Re-read after the launch
    /// iCloud login and on every customer info update, so a Settings screen opened before the
    /// login finished doesn't keep showing the anonymous ID.
    private(set) var appUserID: String = Purchases.shared.appUserID
    private(set) var isAnonymousUser: Bool = Purchases.shared.isAnonymous

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
            refreshAppUserID()
            // RevenueCat: restorePurchases "may force your users to enter the App Store password
            // so should only be performed on request of the user" (5.89.0 docs), so launch uses
            // the silent syncPurchases instead (owner, 2026-10-11); the Restore buttons keep
            // restorePurchases. While every feature is free the result is thrown away anyway
            // (`updateTier`), so launch skips it.
            if !Self.allFeaturesFree { await syncPurchasesSilently() }
            await refresh()
            // Warm the paywall: RevenueCat caches offerings, so the first open shows plans, not
            // "Loading plans…". Also while everything is free: the What's New tier chips and the
            // widgets' locked states take their price from these products (`localizedMonthlyPrice`),
            // and the storefront's own figure is the only honest one to show.
            await loadProducts()
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

    /// The monthly plan's price as StoreKit formats it for this Apple ID's storefront ("$2.99",
    /// "2,99 €", "₹299"); nil until products have loaded. Every price the app shows comes from
    /// here or from a `Package` directly, never from a typed-in number: Apple sets a different
    /// price in each of the 175 storefronts, so a literal "$2.99" is wrong outside the US.
    func localizedMonthlyPrice(for tier: SubscriptionTier) -> String? {
        let packages: [Package]
        switch tier {
        case .free: return nil
        case .core: packages = corePackages
        case .deep: packages = deepPackages
        }
        return packages.first { !PaywallView.isYearly($0) }?.storeProduct.localizedPriceString
    }

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
            Self.publishPricesToWidgets(core: localizedMonthlyPrice(for: .core),
                                        deep: localizedMonthlyPrice(for: .deep))
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
        // only a definite "ineligible" or "no offer" hides the trial. A paid introductory price is
        // not a free trial, so it never counts.
        trialEligibleProductIDs = Set(packages.compactMap { package in
            guard package.storeProduct.introductoryDiscount?.paymentMode == .freeTrial else { return nil }
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

    /// App-active: once paid plans have started, a tier still left from the free period is
    /// replaced by the real one.
    func appDidBecomeActive() {
        guard tierFromFreePeriod, !Self.allFeaturesFree else { return }
        tierFromFreePeriod = false
        if let cached = Purchases.shared.cachedCustomerInfo {
            updateTier(from: cached)
        } else {
            tier = .free
            Self.publishTierToWidgets(.free)
        }
        Task {
            await syncPurchasesSilently()
            await refresh()
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

    private func refreshAppUserID() {
        appUserID = Purchases.shared.appUserID
        isAnonymousUser = Purchases.shared.isAnonymous
    }

    private func updateTier(from customerInfo: CustomerInfo) {
        refreshAppUserID()
        activeProductIDs = customerInfo.activeSubscriptions
        guard !Self.allFeaturesFree else {
            tier = .deep
            tierFromFreePeriod = true
            Self.publishTierToWidgets(tier)
            return
        }
        tierFromFreePeriod = false
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

    /// The widgets' locked states show the monthly price next to the tier name. The extension
    /// can't ask RevenueCat itself, so the app hands StoreKit's formatted strings over the app
    /// group whenever products load. A nil (a plan that didn't load) never erases a price already
    /// published. Timelines reload only when a value changed (the first load, a price change):
    /// WidgetKit budgets reloads and `loadProducts` runs on every paywall open.
    private static func publishPricesToWidgets(core: String?, deep: String?) {
        guard let defaults = UserDefaults(suiteName: WidgetShared.appGroupID) else { return }
        var changed = false
        for (key, value) in [(WidgetShared.corePriceKey, core), (WidgetShared.deepPriceKey, deep)] {
            guard let value, defaults.string(forKey: key) != value else { continue }
            defaults.set(value, forKey: key)
            changed = true
        }
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }
}
