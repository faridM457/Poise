import SwiftUI
import RevenueCat

@main
struct PoiseApp: App {
    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
