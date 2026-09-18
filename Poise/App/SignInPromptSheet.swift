import AuthenticationServices
import SwiftUI

// Shown once, ever, at first launch -- never again after that, whether the
// user signs in or dismisses it (see PoiseRootView, which owns the one-time
// gate via AccountStore.shouldShowSignInPrompt). Purely a nudge: using the
// app without ever signing in remains fully supported (see AccountStore),
// this just makes sure a new user is AWARE the option exists before they
// might reinstall and lose everything, rather than leaving it to be found
// only by opening Profile on their own -- which is also still there, for
// anyone who dismisses this and changes their mind later.
struct SignInPromptSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(Color.poiseSoftBlue)
                    .frame(width: 72, height: 72)
                Image(systemName: "icloud.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.poiseBlueDark)
            }

            VStack(spacing: 8) {
                Text("Keep your progress")
                    .font(PoiseType.headline())
                    .foregroundStyle(Color.poiseNavy)
                Text("Sign in with Apple so your streak, energy, and Pro subscription survive a reinstall or a new device.")
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            SignInWithAppleButton(.signIn, onRequest: { request in
                request.requestedScopes = [.fullName]
            }, onCompletion: { result in
                switch result {
                case .success(let authorization):
                    AccountStore.shared.handleAuthorization(authorization)
                case .failure(let error):
                    print("SignInPromptSheet: Sign in with Apple failed: \(error.localizedDescription)")
                }
                // Covers a cancelled/failed system flow too, not just a
                // clean success -- this sheet never shows again either way
                // (see AccountStore.shouldShowSignInPrompt), so anyone who
                // doesn't come out of it with a real name (declined,
                // dismissed the system sheet, or this is a repeat
                // authorization that Apple didn't hand a name back for)
                // should still land on something better than a blank name.
                assignGuestNameIfNeeded()
                onDismiss()
            })
            .frame(height: 44)
            .padding(.horizontal, 24)

            Button("Not now") {
                assignGuestNameIfNeeded()
                onDismiss()
            }
            .font(PoiseType.subhead(.bold))
            .foregroundStyle(Color.poiseMuted)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 24)
        .presentationDetents([.medium])
        // Without this, a sheet's default backing on this iOS version is the
        // translucent Liquid Glass material -- fine for system UI, but it
        // doesn't match this app's one surface treatment (flat white,
        // hairline border, soft shadow; see LearnView's header comment).
        // Same fix already used for the other two popovers/sheets in
        // PoiseComponents.swift.
        .presentationBackground(Color.white)
    }

    private func assignGuestNameIfNeeded() {
        guard !UserProfileStore.shared.hasName else { return }
        UserProfileStore.shared.assignGuestPlaceholderName()
    }
}
