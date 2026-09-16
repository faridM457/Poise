import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class SubscriptionState {
    private static let proEntitlementIdentifier = "poise_pro"

    private(set) var isPro = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoadedAtStartup = false

    var planLabel: String {
        isPro ? "Poise Pro" : "Free plan"
    }

    func refreshAtStartup() async {
        guard !hasLoadedAtStartup else { return }
        hasLoadedAtStartup = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            apply(customerInfo)
        } catch {
            errorMessage = "We couldn't refresh your subscription status. Please try again."
        }
    }

    func refreshAfterPurchaseOrRestore(with customerInfo: CustomerInfo) async {
        apply(customerInfo)
        await refresh()
    }

    func handlePurchaseFailure(_ error: NSError) {
        errorMessage = "The purchase could not be completed. Please try again."
    }

    func handleRestoreFailure(_ error: NSError) {
        errorMessage = "Purchases could not be restored. Please try again."
    }

    func clearError() {
        errorMessage = nil
    }

    private func apply(_ customerInfo: CustomerInfo) {
        // RevenueCat is currently wired to Test Store products; connect Apple App Store products before production.
        isPro = customerInfo.entitlements[Self.proEntitlementIdentifier]?.isActive == true
        errorMessage = nil
    }
}
