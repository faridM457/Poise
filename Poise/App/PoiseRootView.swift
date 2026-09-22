import SwiftUI

struct PoiseRootView: View {
    @State private var selectedTab: AppTab = .learn
    @State private var showSignInPrompt = false
    @Environment(\.scenePhase) private var scenePhase
    // Watched here, not inside any one tab, because a badge earned by
    // finishing a lesson is announced only after LiveLessonFlowView has
    // already dismissed back out to whichever tab was underneath it -- root
    // is the one place guaranteed to still be around to show it.
    @ObservedObject private var progressStore = LearnProgressStore.shared

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
                // They're back -- the come-back nudge no longer applies.
                // The streak reminder is left alone: merely opening the app
                // isn't the same as having practised (only
                // LearnProgressStore.recordCompletion cancels that one).
                NotificationService.shared.cancelComeBackReminder()
            } else if newPhase == .background {
                scheduleBackgroundReminders()
            }
        }
        // Once, ever, per install -- see AccountStore.shouldShowSignInPrompt
        // for why that's a local flag rather than a synced one. `onDismiss`
        // covers every way this can close (the button's own onDismiss call,
        // "Not now", or a swipe), so the flag only needs setting in one place.
        .sheet(isPresented: $showSignInPrompt, onDismiss: { AccountStore.shared.markSignInPromptShown() }) {
            SignInPromptSheet(onDismiss: { showSignInPrompt = false })
        }
        // Only ever the front of the queue -- one banner on screen at a
        // time, even if a single completion earned several badges at once.
        // Keyed on the badge's own id so a new banner sliding in after the
        // old one is dismissed is a fresh view (a fresh auto-dismiss timer,
        // not the outgoing one's timer racing to close a card that isn't
        // its own anymore).
        .overlay(alignment: .top) {
            if let badge = progressStore.pendingBadgeAnnouncements.first {
                BadgeEarnedBanner(badge: badge) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        progressStore.dismissCurrentBadgeAnnouncement()
                    }
                }
                .id(badge.id)
                .padding(.horizontal, 16)
                // Clears PoiseTopBar (each tab's own safeAreaInset, roughly
                // logo/chip row height plus its own top/bottom padding) --
                // without this the banner lands right on top of the streak
                // and energy chips instead of below them.
                .padding(.top, 72)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: progressStore.pendingBadgeAnnouncements.first?.id)
    }

    // Backgrounding is the one moment both local reminders get (re)computed
    // -- there's no server ticking these on a schedule, so this app has to
    // set its own alarm clock on the way out every time. Never requests
    // permission itself (see NotificationService.isAuthorized's doc): that
    // only ever happens from the explicit toggle in Profile's PrivacyCard.
    private func scheduleBackgroundReminders() {
        Task {
            guard await NotificationService.isAuthorized else { return }
            let store = LearnProgressStore.shared
            // Only worth nagging about if there's a streak alive to lose
            // and today hasn't already covered it.
            if store.currentStreak > 0 && !store.practisedToday {
                NotificationService.shared.scheduleStreakReminder(
                    streakLength: store.currentStreak,
                    at: streakReminderDate()
                )
            }
            // Unconditional, unlike the streak reminder -- even a
            // brand-new account with no streak yet has an "up next".
            NotificationService.shared.scheduleComeBackReminder(
                afterDays: 2,
                upNextTitle: store.upNext?.lesson.title
            )
        }
    }

    // 7pm local, today -- late enough that most people have had a chance to
    // fit practice in, early enough it doesn't land at midnight. If it's
    // already past 7pm when the app backgrounds, firing "later today" a
    // couple of hours out still beats silently deferring the whole reminder
    // to tomorrow, which would miss the streak's actual deadline (midnight).
    private func streakReminderDate() -> Date {
        let now = Date()
        if let sevenPM = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: now), sevenPM > now {
            return sevenPM
        }
        return now.addingTimeInterval(2 * 60 * 60)
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
