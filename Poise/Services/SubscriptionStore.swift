import Combine
import Foundation
import RevenueCat

// Poise Pro entitlement and the packages that grant it.
//
// This replaces the local `isPremium` bool the paywall used to flip. That
// bool is still the flag the rest of the app reads -- energy cap, regen
// interval, the plan label -- but it is now downstream of RevenueCat rather
// than the source of truth, so the app cannot believe someone is subscribed
// when the store disagrees.
//
// Prices are never hardcoded. A paywall has to show the real localized price
// for the user's storefront, which only StoreKit knows; the previous screen's
// "$7.99" would have been wrong in every currency but one and wrong in that
// one as soon as pricing changed.
@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    // Must match the entitlement identifier configured in RevenueCat.
    private static let proEntitlementID = "poise_pro"

    enum LoadState: Equatable {
        case idle
        case loading
        // No offering configured, or the network failed. The paywall shows
        // this rather than an empty plan list with a dead button.
        case unavailable(String)
        case loaded
    }

    @Published private(set) var isPro = false
    @Published private(set) var packages: [Package] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private var didRunStartupRefresh = false

    private init() {}

    var planLabel: String { isPro ? "Poise Pro" : "Free plan" }

    // Annual first when both exist: it is the better value and the one worth
    // defaulting the selection to.
    var sortedPackages: [Package] {
        packages.sorted { lhs, rhs in
            rank(lhs) < rank(rhs)
        }
    }

    private func rank(_ package: Package) -> Int {
        switch package.packageType {
        case .annual: return 0
        case .monthly: return 1
        default: return 2
        }
    }

    // MARK: - Loading

    func refreshAtLaunch() async {
        guard !didRunStartupRefresh else { return }
        didRunStartupRefresh = true
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
        } catch {
            // Deliberately silent. A failed entitlement check at launch should
            // leave the user on Free, not interrupt them with an alert about
            // something they did not ask for.
            isPro = false
            syncEntitlement()
        }
    }

    func loadOfferings() async {
        loadState = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current, !current.availablePackages.isEmpty else {
                packages = []
                loadState = .unavailable("Plans aren't available right now. Check back shortly.")
                return
            }
            packages = current.availablePackages
            loadState = .loaded
        } catch {
            packages = []
            loadState = .unavailable("We couldn't load plans. Check your connection and try again.")
        }
    }

    // MARK: - Purchasing

    // Returns whether the user ends up entitled, so the paywall can dismiss
    // itself on success and stay open on cancellation.
    @discardableResult
    func purchase(_ package: Package) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            // A deliberate cancellation is not an error and gets no alert.
            guard !result.userCancelled else { return false }
            apply(result.customerInfo)
            return isPro
        } catch {
            errorMessage = "That purchase couldn't be completed. You have not been charged."
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            if !isPro {
                errorMessage = "We didn't find a previous Poise Pro purchase on this account."
            }
            return isPro
        } catch {
            errorMessage = "We couldn't restore your purchases. Please try again."
            return false
        }
    }

    // MARK: - Entitlement

    private func apply(_ info: CustomerInfo) {
        isPro = info.entitlements[Self.proEntitlementID]?.isActive == true
        errorMessage = nil
        syncEntitlement()
    }

    // The rest of the app asks LearnProgressStore whether this is a Pro
    // account, because that is where the energy cap and regen interval live.
    // Pushing the entitlement down to it keeps one answer in the app.
    private func syncEntitlement() {
        LearnProgressStore.shared.applyEntitlement(isPro: isPro)
    }
}
