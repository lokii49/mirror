import RevenueCat
import SwiftUI

@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    private(set) var isSubscribed = false
    private(set) var packages: [Package] = []
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?

    private init() {
        Task { await refresh() }
    }

    func loadProducts() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            packages = offerings.current?.availablePackages
                .sorted { $0.storeProduct.price < $1.storeProduct.price } ?? []
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
            isSubscribed = result.customerInfo.entitlements["core"]?.isActive == true
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            isSubscribed = customerInfo.entitlements["core"]?.isActive == true
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            isSubscribed = customerInfo.entitlements["core"]?.isActive == true
            #if DEBUG
            print("[RC] customerID: \(customerInfo.originalAppUserId)")
            print("[RC] activeEntitlements: \(customerInfo.entitlements.active.keys.joined(separator: ", "))")
            print("[RC] isSubscribed: \(isSubscribed)")
            #endif
        } catch {
            #if DEBUG
            print("[RC] refresh error: \(error.localizedDescription)")
            print("[RC] full error: \(error)")
            #endif
        }
    }
}
