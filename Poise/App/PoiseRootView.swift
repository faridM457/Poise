import SwiftUI

struct PoiseRootView: View {
    @State private var selectedTab: AppTab = .learn
    @State private var showSignInPrompt = false
    @State private var showNotificationPaywall = false
    @State private var routedCustomScenario: CustomScenario?
    @State private var showRoutedCustomScenario = false
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // No NavigationStack per tab. None of the three screens pushes
        // anything (Learn uses a fullScreenCover, Profile a sheet, Progress
        // nothing), and wrapping them cost real behavior: a NavigationStack
        // swallows the bottom safeAreaInset added out here, so the tab bar
        // stopped reserving any space and every page's last element rendered
        // underneath it. Re-add a stack only alongside actual push navigation,
        // and put this inset inside it if you do.
        Group {
            switch selectedTab {
            case .learn:
                LearnView()
            case .progress:
                ProgressDashboardView()
            case .profile:
                ProfileView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PoiseBottomTabBar(selectedTab: $selectedTab)
        }
        .tint(.poiseBlueDark)
        // Energy regen is real-time-based (see LearnProgressStore), not tied
        // to app launches -- catch up on elapsed regen whenever the app
        // comes back to the foreground, not just at cold launch.
        .task {
            // Confirms (or corrects) the cached Pro flag the app launched
            // with, so the energy cap and regen interval settle to the truth.
            await SubscriptionStore.shared.refreshAtLaunch()
            if AccountStore.shared.shouldShowSignInPrompt {
                showSignInPrompt = true
            }
            handleNotificationDestination()
        }
        // Prefetched here, at launch, rather than left to PaywallSheet's own
        // .task -- offerings arriving *after* the paywall sheet has already
        // finished its presentation transition let its plan list grow in
        // right as the sheet's height was settling, and the sheet's height
        // then stays locked to whatever it measured at that moment, hiding
        // the plan list permanently even though it's still in the view tree
        // (confirmed: a debug block placed in the same spot flashed briefly
        // then vanished, and a colored ScrollView background showed its
        // measured content height never grew to include it). Loading here
        // means `sortedPackages` is already populated by the time anyone
        // taps through to the paywall, so its sheet has everything it needs
        // for its very first layout pass -- nothing changes shape after.
        .task {
            await SubscriptionStore.shared.loadOfferings()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                LearnProgressStore.shared.refreshRegen()
                // A subscription can lapse, be cancelled, or be restored on
                // another device while the app is backgrounded.
                Task { await SubscriptionStore.shared.refreshEntitlement() }
            }
        }
        // Once, ever, per install -- see AccountStore.shouldShowSignInPrompt
        // for why that's a local flag rather than a synced one. `onDismiss`
        // covers every way this can close (the button's own onDismiss call,
        // "Not now", or a swipe), so the flag only needs setting in one place.
        .sheet(isPresented: $showSignInPrompt, onDismiss: { AccountStore.shared.markSignInPromptShown() }) {
            SignInPromptSheet(onDismiss: { showSignInPrompt = false })
        }
        .sheet(isPresented: $showNotificationPaywall) {
            PaywallSheet(subscriptions: SubscriptionStore.shared)
                .presentationBackground(Color.poiseCanvas)
        }
        .fullScreenCover(isPresented: $showRoutedCustomScenario) {
            CustomScenarioFlowView(resuming: routedCustomScenario)
        }
        .onOpenURL { notificationRouter.route($0) }
        .onChange(of: notificationRouter.pendingDestination) { _, _ in
            handleNotificationDestination()
        }
    }

    private func handleNotificationDestination() {
        guard let destination = notificationRouter.consume() else { return }
        switch destination {
        case .learn:
            selectedTab = .learn
        case .progress:
            selectedTab = .progress
        case .paywall:
            showNotificationPaywall = true
        case .customScenario(let scenarioID):
            selectedTab = .learn
            routedCustomScenario = scenarioID.flatMap { CustomScenarioStore.shared.scenario(id: $0) }
            showRoutedCustomScenario = true
        }
    }
}

// Built to the same rules as the rest of the app's chrome: a flat full-bleed
// surface closed with a hairline, mirroring the Learn header's bottom edge,
// instead of a rounded floating slab with a heavy drop shadow. Type comes off
// the PoiseType ladder and icons carry the same .semibold weight used by every
// other icon in the app.
private struct PoiseBottomTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            BottomTabButton(title: "Learn", icon: "house.fill", tab: .learn, selectedTab: $selectedTab)
            BottomTabButton(title: "Progress", icon: "chart.bar.fill", tab: .progress, selectedTab: $selectedTab)
            BottomTabButton(title: "Profile", icon: "person.fill", tab: .profile, selectedTab: $selectedTab)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color.white.ignoresSafeArea(edges: .bottom)
                Rectangle()
                    .fill(Color.poiseBorder.opacity(0.8))
                    .frame(height: 1)
            }
        }
    }
}

private struct BottomTabButton: View {
    let title: String
    let icon: String
    let tab: AppTab
    @Binding var selectedTab: AppTab

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    // A wide pill spanning most of the tab column, not a badge
                    // hugging the glyph: this is the tab's *selection area*,
                    // so it should read as "this column is active" rather than
                    // as another icon chip. Width follows the column so the
                    // three tabs stay even on any device width.
                    Capsule()
                        .fill(Color.poiseSoftBlue)
                        .opacity(isSelected ? 1 : 0)

                    // Always the filled variant -- previously swapped between
                    // the outline icon and the filled one based on selection;
                    // only the COLOR should change, not the fill style.
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .padding(.horizontal, 14)

                Text(title)
                    .font(PoiseType.caption(.bold))
            }
            .foregroundStyle(isSelected ? Color.poiseBlueDark : Color.poiseMuted)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    PoiseRootView()
}
