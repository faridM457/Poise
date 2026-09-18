import Foundation

// Build-level configuration that must differ between development and release.

enum RevenueCatConfig {
    // Public SDK keys are safe to embed -- they identify the app, they do not
    // authorise anything. What matters is the PREFIX, because it says which
    // store the key points at:
    //
    //   test_  RevenueCat's Test Store. Purchases are simulated, never touch
    //          StoreKit or Apple, and move no money. Works in the Simulator,
    //          which is why it is useful while building a paywall -- and the
    //          SDK logs a warning that App Review rejects builds shipping it.
    //   appl_  Production Apple. Real purchases against real App Store
    //          Connect products.
    //
    // These were one hardcoded literal before. Shipping the wrong store was
    // then a single character away with nothing to catch it, which is exactly
    // the mistake that survives review and then fails silently in the hands of
    // paying users.
    private static let testStoreKey = "test_wwZMvuBadTGHkKuouqJFsMBCsxa"

    // The Apple app's public SDK key, generated automatically when the App
    // Store app was connected in RevenueCat (Project Settings → Apps →
    // Poise (App Store) → API keys).
    private static let productionKey = "appl_rwipBkvIqQDfFzSRZcZqSDewItl"

    static var apiKey: String {
        #if DEBUG
        return testStoreKey
        #else
        // Deliberately fatal rather than silently falling back to the Test
        // Store. A release build with no production key cannot take money, and
        // a crash on first launch is found in the first TestFlight install --
        // whereas a silent fallback ships, passes a smoke test, and leaves
        // every purchase quietly doing nothing.
        precondition(
            !productionKey.isEmpty,
            "RevenueCatConfig.productionKey is empty. Set the appl_ key from the RevenueCat dashboard before shipping."
        )
        return productionKey
        #endif
    }

    // True when the app is pointed at simulated purchases, so the paywall can
    // say so instead of looking like it takes real money.
    static var isUsingTestStore: Bool {
        apiKey.hasPrefix("test_")
    }
}

enum AdsConfig {
    // Free-tier-only interstitial shown after a lesson's scorecard. RevenueCat
    // has no ad-serving product -- its 2026 ad-monetization feature only
    // tracks revenue from an existing ad SDK alongside subscriptions -- so
    // this is a separate integration (Google Mobile Ads / AdMob) gated on
    // SubscriptionStore.isPro rather than anything RevenueCat provides.
    //
    // Google's own test ad unit ID: safe to ship in Debug indefinitely, backed
    // by Google, never serves a real (paying) ad. https://developers.google.com/admob/ios/test-ads
    private static let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"

    private static let productionInterstitialUnitID = "ca-app-pub-4763995977400393/3426681015"

    // nil, rather than a precondition failure like the other configs here --
    // a missing ad unit ID means no ads show, which is a lost-revenue bug,
    // not a crash-worthy one the way a missing purchase or engine key is.
    static var interstitialAdUnitID: String? {
        #if DEBUG
        return testInterstitialUnitID
        #else
        return productionInterstitialUnitID.isEmpty ? nil : productionInterstitialUnitID
        #endif
    }
}

enum EngineConfig {
    // Shared key sent as X-Poise-App-Key on every engine request. It is
    // compiled into the binary, so it filters random traffic rather than
    // proving anything -- the server documents the same caveat. App Attest is
    // the eventual hardening. Must match POISE_APP_KEY in the engine's .env.
    private static let debugAppKey = "poise-dev-app-key"

    // Must match POISE_APP_KEY in conversation-engine/.env (local for now --
    // when the engine gets real hosting, set the same value there too).
    private static let productionAppKey = "6527ea119b99dae75e1355613adb39cd56b42bc7c60ca43bce14c6deba72ba65"

    static var appKey: String {
        #if DEBUG
        return debugAppKey
        #else
        precondition(
            !productionAppKey.isEmpty,
            "EngineConfig.productionAppKey is empty. Set it to match the server's POISE_APP_KEY before shipping."
        )
        return productionAppKey
        #endif
    }
}

enum PoiseLegal {
    // REQUIRED BEFORE SUBMISSION. App Review rejects subscription paywalls
    // whose Terms and Privacy links are missing -- and equally rejects ones
    // whose links do not resolve, so these placeholders must be replaced with
    // pages that actually exist, not just edited to look plausible.
    //
    // Apple also requires the Terms link to point at an EULA. Apple's standard
    // licence agreement is acceptable if you do not have your own:
    // https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
    static let termsURL = URL(string: "https://sapersolutions.com/poise/terms")!
    static let privacyURL = URL(string: "https://sapersolutions.com/poise/privacy")!
}
