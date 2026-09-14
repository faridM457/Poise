import SwiftUI

struct PoiseRootView: View {
    @State private var selectedTab: AppTab = .learn
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
                ProgressDashboardView(snapshot: PoiseMockData.progress)
            case .profile:
                ProfileView(profile: PoiseMockData.profile)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PoiseBottomTabBar(selectedTab: $selectedTab)
        }
        .tint(.poiseBlueDark)
        // Energy regen is real-time-based (see LearnProgressStore), not tied
        // to app launches -- catch up on elapsed regen whenever the app
        // comes back to the foreground, not just at cold launch.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                LearnProgressStore.shared.refreshRegen()
            }
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
