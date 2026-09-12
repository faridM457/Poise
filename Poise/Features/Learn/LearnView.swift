import SwiftUI

struct LearnView: View {
    let unit: LessonUnit
    @State private var activeLesson: LessonNode?

    var body: some View {
        ZStack {
            LearnBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    LearnTopStatusBar(streak: 7, xp: 420, level: PoiseMockData.progress.level)
                        .padding(.top, 10)

                    LearnUnitBanner(unit: unit)

                    LessonPathView(unit: unit) { lesson in
                        guard lesson.state == .available else { return }
                        activeLesson = lesson
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 190)
                }
                .padding(.horizontal, 20)
            }
        }
        .poiseLessonCover(item: $activeLesson) { lesson in
            LessonFlowView(lesson: lesson) {
                activeLesson = nil
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func poiseLessonCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}

private struct LearnBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.white, Color(red: 0.99, green: 0.98, blue: 0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct LearnTopStatusBar: View {
    let streak: Int
    let xp: Int
    let level: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PoiseLogo()
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.8)

            HStack(spacing: 10) {
                LearnStatusMetric(icon: "flame.fill", value: "\(streak)", color: .poiseOrange)
                LearnStatusMetric(icon: "bolt.fill", value: "\(xp) XP", color: Color(red: 1.0, green: 0.80, blue: 0.02))
                LearnStatusMetric(icon: "shield.fill", value: "\(level)", color: .poiseBlue)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .contain)
    }
}

private struct LearnStatusMetric: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .heavy))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.poiseNavy)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

private struct LearnUnitBanner: View {
    let unit: LessonUnit

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.20, blue: 0.43), Color.poiseBlueDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 148, height: 148)
                            .offset(x: 48, y: 18)
                        Circle()
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 116, height: 116)
                            .offset(x: -24, y: 30)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(unit.label.uppercased())
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(unit.title)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(unit.subtitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Spacer(minLength: 0)
                    UnitProgressBadge()
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, minHeight: 188)
        .shadow(color: Color.poiseBlueDark.opacity(0.26), radius: 16, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unit.label), \(unit.title), \(unit.subtitle), 2 of 5 complete")
    }
}

private struct UnitProgressBadge: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Capsule().fill(Color.poiseBlue).frame(width: 20, height: 10)
                Capsule().fill(Color.poiseBlue.opacity(0.90)).frame(width: 20, height: 10)
                Capsule().fill(Color.white.opacity(0.22)).frame(width: 46, height: 10)
            }
            Text("2 / 5")
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 13)
        .background(Color.poiseNavy.opacity(0.42))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

private enum LessonSide {
    case left
    case right
}

private struct LessonPathView: View {
    let unit: LessonUnit
    let onTap: (LessonNode) -> Void

    private let sides: [LessonSide] = [.left, .right, .left, .left, .right]
    private let rowHeights: [CGFloat] = [150, 156, 292, 154, 190]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centers = pathCenters(in: width)
            let totalHeight = rowHeights.reduce(0, +)

            ZStack(alignment: .topLeading) {
                DottedLessonConnector(points: centers)
                    .stroke(
                        Color.poiseMuted.opacity(0.22),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 12])
                    )
                    .frame(width: width, height: totalHeight)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                        LessonPathRow(
                            lesson: lesson,
                            side: side(for: index),
                            width: width,
                            height: rowHeights[safe: index] ?? 174,
                            showMarcus: lesson.state == .available,
                            action: { onTap(lesson) }
                        )
                    }
                }
            }
        }
        .frame(height: rowHeights.reduce(0, +))
    }

    private func side(for index: Int) -> LessonSide {
        sides[safe: index] ?? (index.isMultiple(of: 2) ? .left : .right)
    }

    private func pathCenters(in width: CGFloat) -> [CGPoint] {
        var y: CGFloat = 0
        return unit.lessons.indices.map { index in
            let rowHeight = rowHeights[safe: index] ?? 174
            let side = side(for: index)
            let x = nodeCenterX(for: side, width: width)
            let point = CGPoint(x: x, y: y + 54)
            y += rowHeight
            return point
        }
    }
}

private struct LessonPathRow: View {
    let lesson: LessonNode
    let side: LessonSide
    let width: CGFloat
    let height: CGFloat
    let showMarcus: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if showMarcus {
                HStack(alignment: .top, spacing: 12) {
                    LessonNodeButton(lesson: lesson, action: action)
                        .frame(width: nodeColumnWidth)
                        .padding(.top, 22)
                    Spacer(minLength: 0)
                    MarcusCompanion()
                        .frame(width: companionWidth)
                        .padding(.top, 34)
                }
                .frame(width: width, height: height, alignment: .top)
            } else {
                ZStack(alignment: .topLeading) {
                    LessonNodeButton(lesson: lesson, action: action)
                        .frame(width: nodeColumnWidth)
                        .position(x: nodeX, y: 66)
                }
                .frame(width: width, height: height)
            }
        }
    }

    private var nodeX: CGFloat {
        nodeCenterX(for: side, width: width)
    }

    private var nodeColumnWidth: CGFloat {
        min(152, width * 0.42)
    }

    private var companionWidth: CGFloat {
        min(188, max(172, width - nodeColumnWidth - 18))
    }
}

private struct LessonNodeButton: View {
    let lesson: LessonNode
    let action: () -> Void

    private var nodeSize: CGFloat {
        lesson.isCheckpoint ? 94 : 96
    }

    private var topFill: Color {
        switch lesson.state {
        case .completed: return Color(red: 0.22, green: 0.84, blue: 0.56)
        case .available: return Color(red: 0.10, green: 0.55, blue: 0.98)
        case .locked: return Color(red: 0.92, green: 0.94, blue: 0.96)
        case .checkpoint: return Color(red: 1.0, green: 0.78, blue: 0.20)
        }
    }

    private var lowerFill: Color {
        switch lesson.state {
        case .completed: return Color(red: 0.22, green: 0.65, blue: 0.46)
        case .available: return Color.poiseBlueDark
        case .locked: return Color(red: 0.76, green: 0.79, blue: 0.83)
        case .checkpoint: return Color(red: 0.91, green: 0.60, blue: 0.08)
        }
    }

    private var ringFill: Color {
        switch lesson.state {
        case .completed: return Color(red: 0.63, green: 0.95, blue: 0.78)
        case .available: return Color.poiseSoftBlue
        case .locked: return Color(red: 0.96, green: 0.97, blue: 0.98)
        case .checkpoint: return Color(red: 1.0, green: 0.87, blue: 0.42)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 11) {
                ZStack(alignment: .top) {
                    Circle()
                        .fill(ringFill)
                        .frame(width: nodeSize + 20, height: nodeSize + 20)
                        .shadow(color: Color.poiseNavy.opacity(0.14), radius: 12, x: 0, y: 8)

                    Circle()
                        .fill(lowerFill)
                        .frame(width: nodeSize, height: nodeSize)
                        .offset(y: 11)

                    Circle()
                        .fill(topFill)
                        .frame(width: nodeSize, height: nodeSize)
                        .overlay(alignment: .topLeading) {
                            Circle()
                                .fill(.white.opacity(0.22))
                                .frame(width: nodeSize * 0.74, height: nodeSize * 0.74)
                                .offset(x: -nodeSize * 0.06, y: -nodeSize * 0.10)
                        }
                        .overlay {
                            Image(systemName: iconName)
                                .font(.system(size: iconSize, weight: .heavy))
                                .foregroundStyle(iconColor)
                        }

                    if lesson.state == .available {
                        Text("START")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.poiseBlue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(Color.poisePaleBlue.opacity(0.96))
                            .clipShape(Capsule())
                            .offset(y: -31)
                            .shadow(color: Color.poiseBlue.opacity(0.10), radius: 8, x: 0, y: 4)
                    }
                }
                .frame(width: nodeSize + 30, height: nodeSize + 38)

                Text(lessonTitle)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.poiseNavy)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 166)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(lesson.state == .locked || lesson.state == .checkpoint)
        .accessibilityLabel("\(lesson.title), \(lesson.subtitle)")
    }

    private var lessonTitle: String {
        lesson.title == "Mediating a conflict" ? "Mediating conflict" : lesson.title
    }

    private var iconName: String {
        if lesson.isCheckpoint { return "flag.fill" }
        return lesson.icon
    }

    private var iconSize: CGFloat {
        switch lesson.state {
        case .available: return 34
        case .checkpoint: return 36
        default: return 38
        }
    }

    private var iconColor: Color {
        lesson.state == .locked ? Color.poiseMuted : .white
    }
}

private struct MarcusCompanion: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpeechBubble(text: "Let’s work through it together.")
                .frame(width: bubbleWidth, alignment: .leading)

            Image("MarcusWaving")
                .resizable()
                .scaledToFit()
                .frame(width: 134)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Marcus says, let’s work through it together")
    }

    private var bubbleWidth: CGFloat {
        146
    }
}

private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.poiseNavy)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 14)
            .background(Color.poiseSoftBlue.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DottedLessonConnector: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midY = (previous.y + current.y) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x, y: midY),
                control2: CGPoint(x: current.x, y: midY)
            )
        }

        return path
    }
}

private func nodeCenterX(for side: LessonSide, width: CGFloat) -> CGFloat {
    let inset = min(112, max(80, width * 0.29))
    switch side {
    case .left:
        return inset
    case .right:
        return width - inset
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
