import AuthenticationServices
import Combine
import Foundation
import RevenueCat

// Sign in with Apple exists for exactly one reason: a stable identity to
// hand RevenueCat, so a subscription and its energy ledger (keyed
// server-side by RevenueCat's appUserID -- see conversation-engine/server's
// auth.js) survive a reinstall or a new device instead of resetting to a
// fresh anonymous user every time. Nothing else about the app requires an
// account, and using the app without ever signing in is unaffected.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    private static let keychainKey = "appleUserID"
    private static let hasShownPromptKey = "poise.hasShownSignInPrompt"

    // Presence of this, not a separate "isSignedIn" bool, IS the signed-in
    // state -- there is no world where one is true and the other isn't.
    @Published private(set) var appleUserID: String?

    var isSignedIn: Bool { appleUserID != nil }

    // Whether PoiseRootView should show the one-time "keep your progress"
    // prompt at launch. Deliberately plain UserDefaults, not CloudStore: this
    // must reset on every fresh install rather than sync, or a reinstall --
    // the exact moment signing in would actually matter -- would silently
    // never offer the prompt again.
    var shouldShowSignInPrompt: Bool {
        !isSignedIn && !UserDefaults.standard.bool(forKey: Self.hasShownPromptKey)
    }

    func markSignInPromptShown() {
        UserDefaults.standard.set(true, forKey: Self.hasShownPromptKey)
    }

    private init() {
        appleUserID = KeychainStore.read(Self.keychainKey)
        if let appleUserID {
            refreshCredentialState(for: appleUserID)
        }
    }

    // Called from the SignInWithAppleButton's onCompletion. Takes the
    // Apple-issued credential, keeps its stable `user` identifier (a Keychain
    // item survives reinstall, which is the whole point -- UserDefaults and
    // even NSUbiquitousKeyValueStore do not), and aliases RevenueCat's
    // identity onto it. logIn (not a fresh identify) is deliberate: it folds
    // whatever this install already did anonymously -- including a purchase
    // made before signing in -- onto the stable id rather than orphaning it.
    func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        let userID = credential.user
        KeychainStore.write(userID, forKey: Self.keychainKey)
        appleUserID = userID
        OneSignalNotificationService.shared.synchronizeIdentity(userID)
        OneSignalNotificationService.shared.synchronizeUserData(
            isPro: SubscriptionStore.shared.isPro,
            progress: LearnProgressStore.shared
        )

        // Apple hands back the name only on this first authorization, ever
        // -- a later sign-in on a new device won't have it. Only used to
        // fill in Profile's editable name field, and only if it's still
        // blank: this must never overwrite a name the user already set.
        if !UserProfileStore.shared.hasName, let givenName = credential.fullName?.givenName {
            UserProfileStore.shared.name = givenName
        }

        Task {
            do {
                _ = try await Purchases.shared.logIn(userID)
                await SubscriptionStore.shared.refreshEntitlement()
            } catch {
                print("AccountStore: RevenueCat logIn failed: \(error.localizedDescription)")
            }
        }
    }

    func signOut() {
        KeychainStore.delete(Self.keychainKey)
        appleUserID = nil
        OneSignalNotificationService.shared.synchronizeIdentity(nil)
        OneSignalNotificationService.shared.synchronizeUserData(
            isPro: SubscriptionStore.shared.isPro,
            progress: LearnProgressStore.shared
        )
        Task {
            do {
                _ = try await Purchases.shared.logOut()
                await SubscriptionStore.shared.refreshEntitlement()
            } catch {
                print("AccountStore: RevenueCat logOut failed: \(error.localizedDescription)")
            }
        }
    }

    // Apple ID sign-out or a revoked grant elsewhere doesn't notify this app
    // -- it has to ask. Checked once at launch; if it comes back anything
    // other than authorized, the stored id is stale and this device should
    // fall back to signed-out rather than keep claiming an identity Apple no
    // longer backs.
    private func refreshCredentialState(for userID: String) {
        // Not `[weak self]` -- self is a singleton, and capturing it across
        // this non-isolated completion handler's concurrency boundary is
        // exactly what trips Swift 6's strict checking. Going through the
        // singleton inside the Task sidesteps that instead of fighting it.
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
            guard state != .authorized else { return }
            Task { @MainActor in AccountStore.shared.signOut() }
        }
    }
}
