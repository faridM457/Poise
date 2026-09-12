import SwiftUI

extension Color {
    static let poiseBlue = Color(red: 0.22, green: 0.50, blue: 0.82)
    static let poiseBlueDark = Color(red: 0.12, green: 0.34, blue: 0.62)
    static let poiseNavy = Color(red: 0.18, green: 0.23, blue: 0.31)
    static let poiseMuted = Color(red: 0.46, green: 0.51, blue: 0.58)
    static let poiseMint = Color(red: 0.39, green: 0.76, blue: 0.64)
    static let poiseMintDark = Color(red: 0.17, green: 0.58, blue: 0.46)
    static let poiseGold = Color(red: 0.75, green: 0.56, blue: 0.12)
    static let poiseOrange = Color(red: 0.86, green: 0.43, blue: 0.18)
    static let poisePaleBlue = Color(red: 0.91, green: 0.95, blue: 1.0)
    static let poiseSoftBlue = Color(red: 0.84, green: 0.91, blue: 0.98)
    static let poiseBackground = Color(red: 0.98, green: 0.985, blue: 0.99)
    static let poiseBorder = Color(red: 0.87, green: 0.90, blue: 0.93)
    static let poiseSoftGray = Color(red: 0.94, green: 0.96, blue: 0.97)
}

struct PoiseType {
    static func largeTitle(_ weight: Font.Weight = .heavy) -> Font {
        .system(size: 32, weight: weight, design: .rounded)
    }

    static func title(_ weight: Font.Weight = .heavy) -> Font {
        .system(size: 25, weight: weight, design: .rounded)
    }

    static func headline(_ weight: Font.Weight = .bold) -> Font {
        .system(size: 18, weight: weight, design: .rounded)
    }

    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 16, weight: weight, design: .rounded)
    }

    static func caption(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 12, weight: weight, design: .rounded)
    }
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

struct TactileButtonStyle: ButtonStyle {
    var fill: Color = .poiseBlue
    var lowerEdge: Color = .poiseBlueDark
    var foreground: Color = .white
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PoiseType.body(.heavy))
            .foregroundStyle(disabled ? Color.poiseMuted : foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(disabled ? Color.poiseSoftGray : lowerEdge)
                        .offset(y: configuration.isPressed ? 0 : 4)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(disabled ? Color.poiseSoftGray : fill)
                        .offset(y: configuration.isPressed ? 4 : 0)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct SecondaryPoiseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PoiseType.body(.heavy))
            .foregroundStyle(Color.poiseBlueDark)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.poiseBorder, lineWidth: 1.5)
            )
            .shadow(color: Color.poiseNavy.opacity(configuration.isPressed ? 0.02 : 0.08), radius: 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
