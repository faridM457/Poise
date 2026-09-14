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
                PoiseStatusChip(icon: "flame.fill", value: "\(streak)", color: .poiseOrange)
                PoiseStatusChip(icon: "bolt.fill", value: energyText, color: .poiseAmber)
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

    var body: some View {
        Text(text.uppercased())
            .font(PoiseType.eyebrow())
            .tracking(PoiseType.eyebrowTracking)
            .foregroundStyle(color)
    }
}

// Every section is introduced the same way: one eyebrow, 10pt of air, content.
// No section gets a louder header than any other.
struct PoiseSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseEyebrow(text: title)
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
// highlight -- TactileButtonStyle's raised edge is reserved for real buttons
// in the lesson flow.
struct PoisePressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// The flat primary action used by the redesigned tabs: a solid capsule, no
// raised lower edge. TactileButtonStyle stays in the lesson flow, where the
// chunkier feel belongs.
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
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color.poiseMuted)
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel("Exit lesson")

            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < step ? Color.poiseBlue.opacity(0.85) : Color.poiseSoftGray)
                        .frame(height: 10)
                }
            }

            Text(label.uppercased())
                .font(PoiseType.caption(.heavy))
                .foregroundStyle(Color.poiseMuted)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.white)
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
