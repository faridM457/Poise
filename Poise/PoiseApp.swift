import SwiftUI
import RevenueCat
import GoogleMobileAds

@main
struct PoiseApp: App {
    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        OneSignalNotificationService.shared.initialize()

        // No App Tracking Transparency prompt is requested anywhere in the
        // app yet, so this always serves non-personalized ads (no IDFA) --
        // deliberately, rather than half-wiring ATT with no consent UX behind
        // it. Personalized ads are a later, separate decision.
        MobileAds.shared.start(completionHandler: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
