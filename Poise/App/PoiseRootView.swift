import SwiftUI

struct PoiseRootView: View {
    @State private var selectedTab: AppTab = .learn

    var body: some View {
        ZStack {
            Group {
                switch selectedTab {
                case .learn:
                    NavigationStack {
                        LearnView(unit: PoiseMockData.unit)
                    }
                case .progress:
                    NavigationStack {
                        ProgressDashboardView(snapshot: PoiseMockData.progress)
                    }
                case .profile:
                    NavigationStack {
                        ProfileView(profile: PoiseMockData.profile)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PoiseBottomTabBar(selectedTab: $selectedTab)
        }
        .tint(.poiseBlueDark)
    }
}

private struct PoiseBottomTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 8) {
            BottomTabButton(
                title: "Learn",
                selectedIcon: "house.fill",
                icon: "house",
                tab: .learn,
                selectedTab: $selectedTab
            )
            BottomTabButton(
                title: "Progress",
                selectedIcon: "chart.bar.fill",
                icon: "chart.bar",
                tab: .progress,
                selectedTab: $selectedTab
            )
            BottomTabButton(
                title: "Profile",
                selectedIcon: "person.fill",
                icon: "person",
                tab: .profile,
                selectedTab: $selectedTab
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(.white)
                .shadow(color: Color.poiseNavy.opacity(0.10), radius: 18, x: 0, y: -8)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct BottomTabButton: View {
    let title: String
    let selectedIcon: String
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
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 25, weight: .heavy))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.poiseBlue : Color.poiseNavy.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.poiseSoftBlue.opacity(0.95))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
