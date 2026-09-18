import Foundation
import GoogleMobileAds
import os
import RevenueCatAdMob
import UIKit

// Post-lesson interstitial for free-tier users (Profile paywall lists this as
// "Coming Soon" -- this is that feature). Free-tier only: callers are
// responsible for checking SubscriptionStore.isPro before presenting.
//
// Loads eagerly as soon as a lesson reaches its scorecard, so the ad is
// already sitting in memory by the time the user taps Continue rather than
// making them wait on a network load at the exact moment they're leaving.
@MainActor
final class AdsManager: NSObject {
    static let shared = AdsManager()

    // os.Logger, not print() -- print() goes to the process's stdout, which
    // `xcrun simctl launch` (no console attached) doesn't capture anywhere
    // visible. Logger routes through the unified logging system, so
    // `xcrun simctl spawn booted log show --predicate 'process == "Poise"'`
    // actually sees it. This cost real time to notice once already.
    private let logger = Logger(subsystem: "com.sapersolutions.poise", category: "Ads")

    private var interstitial: InterstitialAd?
    private var isLoading = false
    private var dismissalCompletion: (() -> Void)?

    private override init() {}

    func preloadInterstitial() {
        guard let unitID = AdsConfig.interstitialAdUnitID else {
            logger.notice("preload skipped: no ad unit ID configured for this build")
            return
        }
        guard interstitial == nil, !isLoading else {
            logger.notice("preload skipped: already have one ready or in flight")
            return
        }
        logger.notice("preload starting, unit=\(unitID, privacy: .public)")
        isLoading = true
        // loadAndTrack (not plain .load) reports load/impression/revenue
        // events to RevenueCat's ad tracker alongside subscription revenue.
        // The delegate is passed in here, not assigned afterward -- the
        // adapter holds it weakly and wires its own forwarding, so setting
        // ad.fullScreenContentDelegate post-load would override that.
        InterstitialAd.loadAndTrack(
            withAdUnitID: unitID,
            request: Request(),
            placement: "lesson_scorecard",
            fullScreenContentDelegate: self
        ) { [weak self] ad, error in
            guard let self else { return }
            isLoading = false
            if let error {
                logger.error("preload FAILED: \(error.localizedDescription, privacy: .public)")
                return
            }
            logger.notice("preload succeeded, ad ready to present")
            interstitial = ad
        }
    }

    // Presents the preloaded interstitial if one is ready and calls
    // `completion` once it's dismissed. If no ad is ready (still loading,
    // failed to load, or unconfigured), calls `completion` immediately --
    // a missing ad must never block the user from finishing their lesson.
    func presentInterstitial(completion: @escaping () -> Void) {
        let hadAdReady = interstitial != nil
        guard let interstitial, let root = UIApplication.shared.poiseRootViewController else {
            logger.notice("present SKIPPED: adReady=\(hadAdReady), rootViewControllerFound=\(UIApplication.shared.poiseRootViewController != nil)")
            completion()
            return
        }
        logger.notice("presenting ad now")
        self.interstitial = nil
        dismissalCompletion = completion
        interstitial.present(from: root)
    }
}

extension AdsManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        let completion = dismissalCompletion
        dismissalCompletion = nil
        completion?()
        preloadInterstitial()
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let completion = dismissalCompletion
        dismissalCompletion = nil
        completion?()
        preloadInterstitial()
    }
}

private extension UIApplication {
    var poiseRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
