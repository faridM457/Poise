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

        // No App Tracking Transparency prompt is requested anywhere in the
        // app yet, so this always serves non-personalized ads (no IDFA) --
        // deliberately, rather than half-wiring ATT with no consent UX behind
        // it. Personalized ads are a later, separate decision.
        MobileAds.shared.start(completionHandler: nil)

        // TEMP, DEVELOPER-TESTING ONLY -- REMOVE BEFORE ARCHIVING FOR APP
        // STORE SUBMISSION. A Release build (unlike Debug, which always uses
        // Google's own universal test ad unit) requests real ads. Tapping/
        // viewing a real ad from your own device counts as invalid traffic
        // under AdMob policy and risks the account, unless that device is
        // registered as a test device first -- Google then serves it clearly
        // labeled test ads even on the real ad unit ID. Simulators are
        // already exempt automatically; this only matters for a real phone.
        // Get the identifier from the console the first time this build
        // requests an ad on the device -- it prints the exact line to add
        // here. Placeholder below is not a real ID.
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["<paste-device-id-from-console-here>"]
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
