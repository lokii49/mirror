import StoreKit
import SwiftUI

@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    private(set) var isSubscribed = false
    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?

    private let productIDs = ["mirror_core_monthly", "mirror_core_yearly"]
    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refresh() async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                hasActive = true
                break
            }
        }
        isSubscribed = hasActive
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
                await refresh()
            }
        }
    }
}
