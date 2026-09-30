import Combine
import Foundation
import GoogleMobileAds
import os
import UIKit
import UserMessagingPlatform

// Google's consent message (User Messaging Platform) for the EEA, UK and
// Switzerland. Google requires a certified consent tool before AdMob can
// serve ads to users there, even non-personalized ones. The message itself is
// configured in the AdMob dashboard (Privacy & messaging -> European
// regulations); Google decides per user whether it needs to show, so users
// elsewhere never see anything.
//
// The Mobile Ads SDK is started here, not at launch, because Google asks for
// no ad requests until consent allows them (`canRequestAds`).
@MainActor
final class AdConsentManager: ObservableObject {
    static let shared = AdConsentManager()

    // Whether Google says this user must be offered a way to change their
    // choice later -- Profile shows its "Privacy choices" row only then.
    @Published private(set) var privacyOptionsRequired = false

    private let logger = Logger(subsystem: "com.sapersolutions.poise", category: "AdConsent")
    private var isGathering = false
    private var didStartAds = false

    private init() {}

    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }

    /// Refreshes the consent status and shows Google's message if this user
    /// needs it. Safe to call more than once; overlapping calls are ignored.
    func gatherConsent() async {
        guard !isGathering else { return }
        isGathering = true
        defer { isGathering = false }

        // Consent saved from an earlier launch can already allow ads -- start
        // now rather than making the first ad wait on the network.
        startAdsIfAllowed()
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: Self.requestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: UIApplication.shared.poiseTopViewController)
        } catch {
            // Not fatal: without consent, canRequestAds stays false and no ads
            // are requested; Google retries on the next launch.
            logger.error("consent gathering failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshPrivacyOptionsRequirement()
        startAdsIfAllowed()
        logger.notice("consent status=\(ConsentInformation.shared.consentStatus.rawValue), canRequestAds=\(self.canRequestAds), privacyOptionsRequired=\(self.privacyOptionsRequired)")
    }

    /// Shows Google's privacy options form so the user can change their choice.
    func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: UIApplication.shared.poiseTopViewController)
        } catch {
            logger.error("privacy options form failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshPrivacyOptionsRequirement()
    }

    private func refreshPrivacyOptionsRequirement() {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func startAdsIfAllowed() {
        guard canRequestAds, !didStartAds else { return }
        didStartAds = true
        MobileAds.shared.start(completionHandler: nil)
    }

    private static func requestParameters() -> RequestParameters {
        let parameters = RequestParameters()
        #if DEBUG
        // Launch with -umpDebugEEA to see the message as a user in the EEA
        // would, and -umpReset to clear a saved choice. Simulators count as
        // test devices automatically; a real phone also needs its hashed ID
        // (printed to the console by the SDK) added to testDeviceIdentifiers.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-umpReset") {
            ConsentInformation.shared.reset()
        }
        if arguments.contains("-umpDebugEEA") {
            let debugSettings = DebugSettings()
            debugSettings.geography = .EEA
            parameters.debugSettings = debugSettings
        }
        #endif
        return parameters
    }
}

extension UIApplication {
    // The frontmost view controller, so a consent form can present over a
    // sheet or full-screen cover instead of failing behind it.
    var poiseTopViewController: UIViewController? {
        var top = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
