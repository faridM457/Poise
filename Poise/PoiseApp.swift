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

        #if DEBUG
        // DEVELOPER-TESTING ONLY. `#if DEBUG` guarantees this can never
        // compile into a Release/submission build, so there's no "remove
        // before archiving" step to remember or forget. The tradeoff: Debug
        // already always uses Google's own universal test ad unit (see
        // AdsConfig), so this line never actually has anything to do in a
        // normal Debug run -- it only matters if the real ad unit ID is
        // swapped in temporarily to test the Release ad path on a personal
        // phone. Tapping/viewing a real ad from an unregistered device
        // counts as invalid traffic under AdMob policy; this avoids that by
        // making the device serve clearly-labeled test ads instead, even on
        // the real ad unit ID. Simulators are already exempt automatically.
        // Get the identifier from the console the first time a build
        // requests an ad on the device -- it prints the exact line to add
        // here. Placeholder below is not a real ID.
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["<paste-device-id-from-console-here>"]
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
