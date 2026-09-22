import Combine
import SwiftUI

struct PoiseLogo: View {
    // Sized by its context: the Learn header sets this below the page's own
    // title size so the wordmark doesn't outrank the greeting under it.
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            Text("poise")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.poiseBlueDark)
            Text(".")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.poiseGold)
        }
        .accessibilityLabel("Poise")
    }
}

// MARK: - Shared page chrome
//
// Learn, Progress and Profile are all built from the pieces below so the three
// tabs read as one app: the same header, the same section headers, the same
// icon container, the same card press feel. Anything defined privately inside
// a single feature view is, by definition, not part of this system -- if a
// second screen needs it, it moves here.

// Flat, full-bleed, closed with a hairline -- the mirror image of the tab bar
// at the other end of the screen. Attach with `.safeAreaInset(edge: .top)` so
// page content scrolls underneath it.
struct PoiseTopBar: View {
    let streak: Int
    let energyText: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Deliberately smaller than PoiseType.title -- the wordmark is
            // orientation, the page's own heading under it is the real title.
            PoiseLogo(size: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.8)

            HStack(spacing: 8) {
                StreakChip(streak: streak)
                EnergyChip(energyText: energyText)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.poiseCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.poiseBorder.opacity(0.8))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

// A live countdown to the next unit of energy. Re-renders every second, and
// when the clock runs out it asks the store to apply the regen so the balance
// moves without waiting for the next foreground.
struct EnergyCountdown: View {
    @ObservedObject private var store = LearnProgressStore.shared
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Text("Next energy in")
                .font(PoiseType.caption())
                .foregroundStyle(Color.poiseMuted)
            Text(store.countdownText(asOf: now) ?? "")
                .font(PoiseType.caption(.bold))
                .foregroundStyle(Color.poiseNavy)
                // Digits keep a fixed width so the line doesn't jitter as it
                // counts down.
                .monospacedDigit()
        }
        .onReceive(tick) { instant in
            now = instant
            if let seconds = store.secondsUntilNextEnergy(asOf: instant), seconds <= 0 {
                store.refreshRegen()
            }
        }
    }
}

// Both chips behave the same way: tap for what the number means and what
// happens next. An interactive chip beside a static one is its own kind of
// inconsistency.
struct StreakChip: View {
    let streak: Int

    @State private var showingDetail = false

    var body: some View {
        Button { showingDetail = true } label: {
            PoiseStatusChip(icon: "flame.fill", value: "\(streak)", color: .poiseOrange)
        }
        .buttonStyle(PoisePressableStyle())
        .accessibilityLabel("Streak, \(streak) days. Tap for details.")
        .popover(isPresented: $showingDetail) {
            StreakDetailPopover(streak: streak)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Color.white)
        }
    }
}

private struct StreakDetailPopover: View {
    let streak: Int

    @ObservedObject private var store = LearnProgressStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.poiseOrange)
                Text("\(streak)-day streak")
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
            }

            Text("Days in a row with at least one conversation.")
                .font(PoiseType.caption())
                .foregroundStyle(Color.poiseMuted)
                .fixedSize(horizontal: false, vertical: true)

            PoiseDivider()

            // Says what to do next rather than threatening a loss -- the
            // streak is a record of practice, not a thing to be punished over.
            Text(store.practisedToday
                 ? "Done for today. Come back tomorrow to keep it going."
                 : "No conversation yet today. One keeps the streak alive.")
                .font(PoiseType.caption(.bold))
                .foregroundStyle(Color.poiseNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 240)
    }
}

// The energy chip is tappable. iOS has no hover, so the equivalent of a
// tooltip is a popover -- and the chip is where people already look when they
// want to know how much is left, which makes it the right place to explain
// what the number means and when the next one arrives.
struct EnergyChip: View {
    let energyText: String

    @ObservedObject private var store = LearnProgressStore.shared
    @State private var showingDetail = false

    var body: some View {
        Button { showingDetail = true } label: {
            PoiseStatusChip(icon: "bolt.fill", value: energyText, color: .poiseAmber)
        }
        .buttonStyle(PoisePressableStyle())
        .accessibilityLabel("Energy, \(energyText). Tap for details.")
        .popover(isPresented: $showingDetail) {
            EnergyDetailPopover(store: store)
                .presentationCompactAdaptation(.popover)
                // Without this the popover keeps the system's translucent
                // material, which blurs the page through it -- nothing else in
                // this app is transparent, so it read as a different design.
                .presentationBackground(Color.white)
        }
    }
}

private struct EnergyDetailPopover: View {
    @ObservedObject var store: LearnProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.poiseAmber)
                Text("\(store.energyRemaining) of \(store.energyCap) energy")
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
            }

            // Was "nothing is locked, you can still practice", from when
            // starting at zero was merely discouraged. It is a hard block now
            // (see LiveLessonFlowView.startRoleplay), so saying otherwise
            // would set the user up for a refusal.
            Text(store.energyRemaining > 0
                 ? "Each conversation you start uses one. You get one back every \(store.regenHours) hours."
                 : "You are out. Reading a lesson is still free — starting a conversation needs one.")
                .font(PoiseType.caption())
                .foregroundStyle(Color.poiseMuted)
                .fixedSize(horizontal: false, vertical: true)

            if store.secondsUntilNextEnergy() != nil {
                PoiseDivider()
                EnergyCountdown()
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

// Icon + value in a white capsule with a hairline. The accent colors only the
// glyph -- the chip itself stays neutral so two chips side by side don't read
// as two different components.
struct PoiseStatusChip: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(PoiseType.subhead(.bold))
                .foregroundStyle(Color.poiseNavy)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.poiseBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// One eyebrow style app-wide: uppercase, tracked, muted. Used for section
// headers and for small labels inside cards ("UNIT 1", "UP NEXT").
struct PoiseEyebrow: View {
    let text: String
    var color: Color = .poiseMuted
    // Opt-in, default unchanged (11pt): every other eyebrow in the app stays
    // exactly as it was. Only a caller that explicitly wants it bigger --
    // e.g. sitting beside a 44pt icon badge, where 11pt reads as an
    // afterthought -- passes a larger size.
    var size: CGFloat = 11

    var body: some View {
        Text(text.uppercased())
            .font(PoiseType.eyebrow(size: size))
            .tracking(PoiseType.eyebrowTracking)
            .foregroundStyle(color)
    }
}

// Every section is introduced the same way: one eyebrow, 10pt of air, content.
// No section gets a louder header than any other.
struct PoiseSection<Content: View>: View {
    let title: String
    // Opt-in, default off: a rule filling the rest of the header's row.
    // Off everywhere by default so this stays every other section's plain
    // eyebrow; only a caller that explicitly wants the rule gets it.
    var showsRule: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsRule {
                HStack(spacing: 10) {
                    PoiseEyebrow(text: title)
                    Rectangle()
                        .fill(Color.poiseMuted.opacity(0.4))
                        .frame(height: 1)
                }
            } else {
                PoiseEyebrow(text: title)
            }
            content
        }
    }
}

// The page's own heading, one step below the largeTitle that used to be used
// here -- Learn's greeting sets the size for all three tabs.
struct PoisePageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseNavy)
            if let subtitle {
                Text(subtitle)
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
            }
        }
    }
}

// All icons in the app's chrome live in the same container: a rounded square
// whose radius is 0.3x its size, glyph at 0.44x, which leaves uniform padding
// on all four sides at any size.
struct PoiseIconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(color.opacity(0.13))
            Image(systemName: icon)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// The hairline used between rows inside a card -- the same weight and color as
// the header and tab bar edges, rather than the system separator.
struct PoiseDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.poiseBorder.opacity(0.8))
            .frame(height: 1)
    }
}

// Tappable cards acknowledge the press with a quiet scale rather than a
// highlight -- a raised edge is reserved for real buttons
// in the lesson flow.
struct PoisePressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// The app's only primary action: a solid capsule, no raised lower edge. It is
// used by every CTA in every flow -- the Learn hero, the lesson flow, the
// modal and the paywall -- so a button always reads as the same object.
struct PoiseFlatButtonStyle: ButtonStyle {
    var fill: Color = .poiseBlueDark
    var foreground: Color = .white
    // Inline (hugging) by default, matching the Learn hero's CTA. Pass true
    // only where the button really is the whole surface's single action.
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PoiseType.body(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 48)
            .background(fill)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// A white card with a hairline and one soft shadow -- the single surface
// treatment shared by every non-hero card in the app.
struct PoiseSurfaceCard<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.poiseBorder, lineWidth: 1)
            )
            .shadow(color: .poiseNavy.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(PoiseType.caption(.heavy))
            .foregroundStyle(Color.poiseBlueDark.opacity(0.72))
    }
}

struct PrimaryButtonLabel: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }
}

struct MarcusAvatar: View {
    var size: CGFloat = 124
    var compact: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 22 : 34, style: .continuous)
                .fill(Color(red: 0.78, green: 0.90, blue: 0.91))
            Circle()
                .fill(Color(red: 0.66, green: 0.35, blue: 0.20))
                .frame(width: size * 0.64, height: size * 0.64)
                .offset(y: size * 0.14)
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .frame(width: size * 0.55, height: size * 0.22)
                .offset(y: -size * 0.16)
            HStack(spacing: size * 0.16) {
                Circle().fill(.white).frame(width: size * 0.11)
                Circle().fill(.white).frame(width: size * 0.11)
            }
            .offset(y: size * 0.04)
            HStack(spacing: size * 0.20) {
                Circle().fill(Color.poiseNavy).frame(width: size * 0.045)
                Circle().fill(Color.poiseNavy).frame(width: size * 0.045)
            }
            .offset(y: size * 0.04)
            Capsule()
                .fill(Color(red: 0.38, green: 0.18, blue: 0.14))
                .frame(width: size * 0.20, height: 4)
                .offset(y: size * 0.25)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 22 : 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 22 : 34, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 4)
        )
        .shadow(color: Color.poiseBlue.opacity(0.16), radius: 10, x: 0, y: 6)
        .accessibilityLabel("Marcus character illustration")
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = .poiseBlue
    var height: CGFloat = 11

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.poiseSoftGray)
                Capsule().fill(tint).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Progress \(Int(value * 100)) percent")
    }
}

struct LessonProgressHeader: View {
    let step: Int
    let total: Int
    let label: String
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.poiseMuted)
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Exit lesson")

            // Same segmented rail as the unit cards' progress -- 6pt, poiseBlue
            // filled, poiseTrack empty -- rather than 10pt bars on poiseSoftGray.
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < step ? Color.poiseBlue : Color.poiseTrack)
                        .frame(height: 6)
                }
            }

            PoiseEyebrow(text: label)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        // Flat canvas closed with a hairline, mirroring PoiseTopBar and the
        // tab bar, instead of a plain white block with no edge.
        .background(Color.poiseCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.poiseBorder.opacity(0.8))
                .frame(height: 1)
        }
    }
}

struct InfoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .poiseCard()
    }
}

// MARK: - Modal

// The app's own alert. UIKit's `.alert` arrives with system typography, system
// corner radius and a tinted default button -- none of which are on this app's
// ladder, so a blocking message was the one surface that looked like a
// different product. This is the same construction as every other card here:
// a white surface, an icon badge, the type ladder, and the app's flat button.
//
// Presentation is an overlay rather than a sheet so it can sit inside a
// fullScreenCover without a second presentation fighting the first.
struct PoiseModal<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    var primaryTitle: String = "Got it"
    let onPrimary: () -> Void
    @ViewBuilder var extra: Content

    var body: some View {
        ZStack {
            // Scrim. Navy rather than black so it reads as this app dimming
            // itself rather than a system overlay.
            Color.poiseNavy.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onPrimary)

            VStack(spacing: 0) {
                PoiseIconBadge(icon: icon, color: iconColor, size: 52)

                Spacer().frame(height: 16)

                Text(title)
                    .font(PoiseType.headline())
                    .foregroundStyle(Color.poiseNavy)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 8)

                Text(message)
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                extra

                Spacer().frame(height: 20)

                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.poiseBorder, lineWidth: 1.5)
            )
            .shadow(color: .poiseNavy.opacity(0.18), radius: 28, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

extension PoiseModal where Content == EmptyView {
    init(
        icon: String,
        iconColor: Color,
        title: String,
        message: String,
        primaryTitle: String = "Got it",
        onPrimary: @escaping () -> Void
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            message: message,
            primaryTitle: primaryTitle,
            onPrimary: onPrimary,
            extra: { EmptyView() }
        )
    }
}

// MARK: - Badge earned banner

// Earning a badge (see LearnProgressStore.pendingBadgeAnnouncements) is a
// bonus, not a checkpoint -- it should announce itself and get out of the
// way on its own, never make someone dismiss it before they can go back to
// what they were doing. That rules out reusing PoiseModal above: its scrim
// and centered card are built for something that blocks until acknowledged
// (the out-of-energy alert), which is the wrong shape for a "nice, you got
// one" moment. This is a compact, non-blocking card instead -- no scrim,
// pinned near the top rather than centered, and it dismisses itself.
//
// Hosted at root level (see PoiseRootView), not inside the lesson flow: by
// the time a badge is announced, `recordAndFinish` has often already called
// `onFinish(true)` and returned the user to whichever tab they were on
// before the lesson.
struct BadgeEarnedBanner: View {
    let badge: PoiseBadge
    let onDismiss: () -> Void

    // Long enough to actually read a short title, short enough that nobody
    // is left waiting on it -- this is meant to feel like a toast, not a
    // screen that needs clearing.
    private static let displayDuration: UInt64 = 3_000_000_000

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 12) {
                PoiseIconBadge(icon: badge.icon, color: .poiseGold, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    PoiseEyebrow(text: "Badge earned", color: .poiseGold)
                    Text(badge.title)
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.poiseBorder, lineWidth: 1)
            )
            // A real shadow, not a hairline -- this card floats above the
            // page rather than sitting flush with it like the top bar it's
            // layered over.
            .shadow(color: .poiseNavy.opacity(0.16), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(PoisePressableStyle())
        // A tap dismisses early. Nothing else about this view is
        // interactive, so the whole card is fair game as the tap target
        // rather than needing its own small close button.
        .accessibilityLabel("Badge earned: \(badge.title). Double tap to dismiss.")
        .task {
            // Cancelled for free the moment this view leaves the tree --
            // which is exactly what happens when the caller pops the queue,
            // whether that pop came from this timer or from the tap above.
            try? await Task.sleep(nanoseconds: Self.displayDuration)
            onDismiss()
        }
    }
}
