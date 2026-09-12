import SwiftUI

struct PoiseLogo: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("poise")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.poiseBlueDark)
            Text(".")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.poiseGold)
        }
        .accessibilityLabel("Poise")
    }
}

struct StatusRow: View {
    let streak: Int
    let xp: Int
    let level: Int

    var body: some View {
        HStack {
            StatusPill(icon: "flame.fill", value: "\(streak) days", color: .poiseOrange)
            Spacer()
            StatusPill(icon: "sparkles", value: "\(xp) XP", color: .poiseGold)
            Spacer()
            StatusPill(icon: "flag.fill", value: "Level \(level)", color: .poiseBlueDark)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.white.opacity(0.94))
    }
}

struct StatusPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(PoiseType.caption(.heavy))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
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
