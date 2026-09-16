import SwiftUI
import RevenueCat

@main
struct PoiseApp: App {
    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(
            withAPIKey: "test_wwZMvuBadTGHkKuouqJFsMBCsxa"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
