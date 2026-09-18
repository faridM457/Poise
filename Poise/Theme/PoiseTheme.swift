import SwiftUI

extension Color {
    static let poiseBlue = Color(red: 0.22, green: 0.50, blue: 0.82)
    static let poiseBlueDark = Color(red: 0.12, green: 0.34, blue: 0.62)
    static let poiseNavy = Color(red: 0.18, green: 0.23, blue: 0.31)
    // Secondary text, app-wide. Darkened from (0.46, 0.51, 0.58), which
    // measured 3.91:1 on white, 3.65:1 on the canvas and 3.12:1 on the hero
    // gradient -- all below the 4.5:1 WCAG AA needs for text at the 11-14pt
    // sizes this is used at (eyebrows, captions, subheads). This value scores
    // 6.08 / 5.67 / 4.86 respectively. Anything lighter fails somewhere: the
    // hero's pale-blue gradient is the binding constraint, not white.
    static let poiseMuted = Color(red: 0.345, green: 0.388, blue: 0.459)
    static let poiseMint = Color(red: 0.39, green: 0.76, blue: 0.64)
    static let poiseMintDark = Color(red: 0.17, green: 0.58, blue: 0.46)
    static let poiseGold = Color(red: 0.75, green: 0.56, blue: 0.12)
    static let poiseOrange = Color(red: 0.86, green: 0.43, blue: 0.18)
    static let poisePurple = Color(red: 0.51, green: 0.42, blue: 0.82)
    static let poisePaleBlue = Color(red: 0.91, green: 0.95, blue: 1.0)
    static let poiseSoftBlue = Color(red: 0.84, green: 0.91, blue: 0.98)
    static let poiseBackground = Color(red: 0.98, green: 0.985, blue: 0.99)
    static let poiseBorder = Color(red: 0.87, green: 0.90, blue: 0.93)
    static let poiseSoftGray = Color(red: 0.94, green: 0.96, blue: 0.97)
    // Flat warm paper the Learn page sits on -- deep enough that plain white
    // cards separate from it without needing heavy shadows or tinted fills.
    static let poiseCanvas = Color(red: 0.972, green: 0.969, blue: 0.960)
    // The single amber used for energy. Replaces the near-fluorescent
    // (1.0, 0.80, 0.02) that was inlined at the one call site.
    static let poiseAmber = Color(red: 0.93, green: 0.69, blue: 0.13)
    // Neutral "empty" rail for progress segments and activity marks -- one
    // step darker than poiseBorder so unfilled state is legible, not absent.
    static let poiseTrack = Color(red: 0.878, green: 0.894, blue: 0.914)
}

// One type scale for the whole app -- six steps, one family (rounded
// system). Anything that needs a size not on this ladder is a sign the
// hierarchy is wrong, not that the ladder needs another rung.
struct PoiseType {
    static func largeTitle(_ weight: Font.Weight = .heavy) -> Font {
        .system(size: 32, weight: weight, design: .rounded)
    }

    static func title(_ weight: Font.Weight = .heavy) -> Font {
        .system(size: 25, weight: weight, design: .rounded)
    }

    static func headline(_ weight: Font.Weight = .bold, size: CGFloat = 18) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // Default .medium, not .regular. SF Rounded only reads as rounded from
    // medium upward -- at regular its terminals flatten out and prose looks
    // like plain system text sitting next to the app's bold rounded labels.
    // Set here rather than at a call site so every prose block in the app
    // carries the same weight.
    static func body(_ weight: Font.Weight = .medium) -> Font {
        .system(size: 16, weight: weight, design: .rounded)
    }

    // Secondary supporting copy -- one clear step below body so a card can
    // carry a title and a detail line without both competing at 16pt.
    static func subhead(_ weight: Font.Weight = .medium) -> Font {
        .system(size: 14, weight: weight, design: .rounded)
    }

    static func caption(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 12, weight: weight, design: .rounded)
    }

    // Small all-caps labels (section headers, "UNIT 1", "UP NEXT"). Always
    // pair with `.tracking(PoiseType.eyebrowTracking)` and uppercased text
    // so every eyebrow in the app reads as the same element.
    static func eyebrow(_ weight: Font.Weight = .heavy, size: CGFloat = 11) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let eyebrowTracking: CGFloat = 1.1
}

struct PoiseCardBackground: ViewModifier {
    var fill: Color = .white
    var stroke: Color = .poiseBorder
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 1.5)
            )
            .shadow(color: .poiseNavy.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func poiseCard(fill: Color = .white, stroke: Color = .poiseBorder, radius: CGFloat = 24) -> some View {
        modifier(PoiseCardBackground(fill: fill, stroke: stroke, radius: radius))
    }
}
