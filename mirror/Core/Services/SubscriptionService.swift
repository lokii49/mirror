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

    var isSubscribed: Bool { tier != .free }
    var isDeep: Bool { tier == .deep }

    private init() {
        Task {
            await restorePurchases()
            await refresh()
        }
    }

    func loadProducts() async {
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
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func purchase(_ package: Package) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            updateTier(from: result.customerInfo)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateTier(from: customerInfo)
        } catch {
            purchaseError = error.localizedDescription
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
        guard !Self.allFeaturesFree else {
            tier = .deep
            UserDefaults(suiteName: "group.com.lokesh.mirror")?.set(tier.rawValue, forKey: "widget.tier")
            return
        }
        if customerInfo.entitlements["deep"]?.isActive == true {
            tier = .deep
        } else if customerInfo.entitlements["core"]?.isActive == true {
            tier = .core
        } else {
            tier = .free
        }
        UserDefaults(suiteName: "group.com.lokesh.mirror")?.set(tier.rawValue, forKey: "widget.tier")
    }
}
