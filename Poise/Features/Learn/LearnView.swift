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
                    .padding(.top, 32)
                    // PoiseRootView's .safeAreaInset(edge: .bottom) already
                    // reserves space for the floating tab bar -- this only
                    // needs a small amount of its own breathing room below
                    // the last node, not a second large reservation on top
                    // of that (190pt here previously left a huge blank gap
                    // of empty background above the tab bar).
                    .padding(.bottom, 32)
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
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.20, blue: 0.43), Color.poiseBlueDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(unit.label.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.70))
                    .lineLimit(1)
                Text(unit.title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(alignment: .center) {
                    Text(unit.subtitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    UnitProgressBadge()
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: Color.poiseBlueDark.opacity(0.26), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unit.label), \(unit.title), \(unit.subtitle), 2 of 5 complete")
    }
}

private struct UnitProgressBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                Capsule().fill(Color.poiseBlue).frame(width: 9, height: 4)
                Capsule().fill(Color.poiseBlue.opacity(0.90)).frame(width: 9, height: 4)
                Capsule().fill(Color.white.opacity(0.22)).frame(width: 20, height: 4)
            }
            Text("2 / 5")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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

    private let sides: [LessonSide] = [.left, .right, .left, .right, .left]
    // Shrunk substantially (from an earlier [280, 156, 292, 154, 190]) so
    // all 5 nodes for a unit fit on one screen without scrolling, matching
    // the mockup's density. Whichever row is current still gets slightly
    // more headroom for MarcusCompanion via companionMinHeight below.
    private let rowHeights: [CGFloat] = [175, 82, 132, 82, 98]
    private let companionTopInset: CGFloat = 6
    // The next row's own node circle isn't flush with its row's start --
    // its center sits 40pt down from the row boundary, but its rendered
    // radius (~57pt, from LessonNodeButton's nodeSize+18) is bigger than
    // that, so the node visually pokes back UP past its own row's start by
    // about (57-40)=17pt. Confirmed by screenshot: with the old 10pt
    // margin, Marcus's arm visibly overlapped the next node. This margin
    // has to absorb that encroachment plus a real visual gap, not just
    // reach the nominal row boundary.
    private let companionBottomMargin: CGFloat = 34
    // Marcus's speech bubble + character image need real room to render
    // at a legible size (not just "whatever's left after the node") --
    // below this, scaledToFit would squash the image into a sliver.
    private let companionMinHeight: CGFloat = 85

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centers = pathCenters(in: width)
            let totalHeight = rowHeights.reduce(0, +)

            ZStack(alignment: .topLeading) {
                DottedLessonConnector(
                    points: centers,
                    routeLeftAfterIndex: unit.lessons.firstIndex(where: { $0.state == .available })
                )
                    .stroke(
                        Color.poiseMuted.opacity(0.22),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [2, 12])
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
                            action: { onTap(lesson) }
                        )
                    }
                }

                // Drawn as its own top-level layer (not nested inside a row's
                // HStack) and positioned explicitly from the same `centers`
                // used for the connector line, so its height can never be
                // constrained by -- or overflow into and get drawn-over by --
                // a fixed row height. Always on top, next to whichever lesson
                // is currently .available.
                if let availableIndex = unit.lessons.firstIndex(where: { $0.state == .available }) {
                    let anchor = centers[availableIndex]
                    let nodeHalfWidth = min(96, width * 0.28) / 2
                    // Bounded by the ACTUAL remaining space to the right of
                    // the node, not an arbitrary floor -- a floor bigger
                    // than what's really available let the bubble spill
                    // past the true screen edge. 16pt safety margin from
                    // the container's right edge.
                    let companionLeadingX = anchor.x + nodeHalfWidth + 12
                    let companionWidth = max(150, width - companionLeadingX - 16)
                    // Derived from the actual available row's real start/end
                    // (not a fixed absolute position independent of which
                    // row is current, which previously only happened to look
                    // right for one specific index and let Marcus's bottom
                    // edge sit just 14pt from the next row's node). Starts
                    // near the row's own top (companionTopInset) like the
                    // node itself does, and is capped so it can never reach
                    // the next row -- but never shrunk below companionMinHeight,
                    // since a too-small budget would squash the character
                    // image into an illegibly tiny sliver instead of leaving
                    // it at a normal size.
                    let rowStart = rowHeights[0..<availableIndex].reduce(0, +)
                    let rowEnd = rowStart + rowHeights[availableIndex]
                    let companionTop = rowStart + companionTopInset
                    let companionHeight = max(companionMinHeight, rowEnd - companionTop - companionBottomMargin)

                    MarcusCompanion()
                        .frame(width: companionWidth)
                        .frame(height: companionHeight, alignment: .top)
                        .position(
                            x: companionLeadingX + companionWidth / 2,
                            y: companionTop + companionHeight / 2
                        )
                        .allowsHitTesting(false)
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
            let point = CGPoint(x: x, y: y + 40)
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
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            LessonNodeButton(lesson: lesson, action: action)
                .frame(width: nodeColumnWidth)
                .position(x: nodeX, y: 40)
        }
        .frame(width: width, height: height)
    }

    private var nodeX: CGFloat {
        nodeCenterX(for: side, width: width)
    }

    private var nodeColumnWidth: CGFloat {
        min(96, width * 0.28)
    }
}

private struct LessonNodeButton: View {
    let lesson: LessonNode
    let action: () -> Void

    private var nodeSize: CGFloat {
        lesson.isCheckpoint ? 72 : 74
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
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    Circle()
                        .fill(ringFill)
                        .frame(width: nodeSize + 8, height: nodeSize + 8)
                        .shadow(color: Color.poiseNavy.opacity(0.12), radius: 5, x: 0, y: 3)

                    Circle()
                        .fill(lowerFill)
                        .frame(width: nodeSize, height: nodeSize)
                        .offset(y: 2)

                    Circle()
                        .fill(topFill)
                        .frame(width: nodeSize, height: nodeSize)
                        .overlay {
                            Image(systemName: iconName)
                                .font(.system(size: iconSize, weight: .heavy))
                                .foregroundStyle(iconColor)
                        }

                    if lesson.state == .available {
                        Text("START")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.poiseBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.poisePaleBlue.opacity(0.96))
                            .clipShape(Capsule())
                            .offset(y: -18)
                            .shadow(color: Color.poiseBlue.opacity(0.10), radius: 5, x: 0, y: 2)
                    }
                }
                .frame(width: nodeSize + 18, height: nodeSize + 22)

                Text(lessonTitle)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.poiseNavy)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 110)
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
        // Marcus on the left, bubble on his right -- the bubble's tail
        // points left (toward his head) to match that arrangement.
        HStack(alignment: .top, spacing: 6) {
            Image("MarcusWaving")
                .resizable()
                .scaledToFit()
                .frame(width: 104)
                .accessibilityHidden(true)

            SpeechBubble(text: "Let’s work through it together.")
                .frame(width: bubbleWidth, alignment: .leading)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Marcus says, let’s work through it together")
    }

    private var bubbleWidth: CGFloat {
        88
    }
}

private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.poiseNavy)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.poiseSoftBlue.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .leading) {
                SpeechBubbleTail()
                    .fill(Color.poiseSoftBlue.opacity(0.92))
                    .frame(width: 9, height: 14)
                    .offset(x: -7)
            }
    }
}

// A small left-pointing carat so the bubble reads as dialogue rather than
// a floating label -- Marcus sits to the bubble's left, so the tail points
// left toward him.
private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.4))
        path.closeSubpath()
        return path
    }
}

private struct DottedLessonConnector: Shape {
    let points: [CGPoint]
    // The companion character stands just to the right of whichever node is
    // .available, so the segment leaving THAT node needs to route away from
    // it (left, under its label, then across) instead of the normal
    // crossed-control sweep toward the destination's side -- which for a
    // left-side node would sweep the track rightward, straight through
    // where the companion stands. nil when no lesson is available (shouldn't
    // normally happen, but degrades to the default routing rather than
    // crashing on an out-of-range index).
    var routeLeftAfterIndex: Int?

    // Two earlier attempts at pure vertical clearance (76pt, then 98pt)
    // still let the track cut through label text -- confirmed by an actual
    // zoomed screenshot crop, not just eyeballing the full page. Root
    // problem with that whole approach: as long as the curve stays at the
    // departure node's x position while descending past its label (which
    // sits directly below the node, in the same column), no vertical
    // clearance number fixes it -- the fix has to move the curve OUT of
    // that column before it reaches label height, not just further down
    // within it.
    //
    // This uses "crossed" control points: control1 is placed near the
    // DESTINATION's x (not the source's), just a little below the source;
    // control2 is placed near the SOURCE's x, just above the destination.
    // That makes the curve's initial direction already diagonal, sweeping
    // toward the other column almost immediately after leaving each node,
    // so it's clear of both nodes' label columns well before it reaches
    // label height -- a structural fix, not a tuned distance.
    private let earlyOffset: CGFloat = 34
    // When two consecutive nodes are on the SAME side, previous.x ==
    // current.x, so the crossed-control-point trick has no x-difference to
    // work with and degenerates back into a straight vertical line through
    // the label. Force a minimum sideways bow (toward the empty opposite
    // side) in that case -- labels are at most 110pt wide, so half that
    // plus margin clears them.
    private let minLateralBow: CGFloat = 115
    // The route-left-around-the-companion case sweeps left much further
    // (minLateralBow) than it descends (earlyOffset=34), so with the
    // ordinary earlyOffset its early trajectory stays close to the label's
    // TOP edge while still moving left -- confirmed by an actual pixel
    // crop showing a dot grazing the "N" in "Naming". Give this case its
    // own, larger vertical offset so it's already past the label's top
    // before sweeping wide.
    private let leftRouteEarlyOffset: CGFloat = 70

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            if index - 1 == routeLeftAfterIndex {
                // No straight segments and no sharp corners -- two cubic
                // beziers, joined at a waypoint with MATCHING tangents (both
                // arrive at and leave the waypoint heading straight down),
                // so the join reads as one continuous curve, not a corner.
                // The first curve's own control points make it leave the
                // node heading almost straight left (not downward) and
                // arrive at the waypoint heading straight down.
                //
                // Solved the x(t)/y(t) equations by hand for this exact
                // control-point setup (not just previewed): x drops below
                // the label's left edge by t=0.27, while y is still only
                // ~11 at that point (the label doesn't start until ~47) --
                // so the curve is already outside the label's column well
                // before it reaches label height, and after the waypoint
                // the curve stays past the label's bottom edge for its
                // entire second half. No t-value puts it inside the box.
                let waypoint = CGPoint(x: previous.x - 75, y: previous.y + 100)
                path.addCurve(
                    to: waypoint,
                    control1: CGPoint(x: previous.x - 66, y: previous.y),
                    control2: CGPoint(x: waypoint.x, y: waypoint.y - 40)
                )
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: waypoint.x, y: waypoint.y + 40),
                    control2: CGPoint(x: current.x, y: current.y - earlyOffset)
                )
                continue
            }

            let dx = current.x - previous.x
            let bowedTargetX: CGFloat = abs(dx) >= minLateralBow
                ? current.x
                : current.x + (dx >= 0 ? minLateralBow : -minLateralBow)

            path.addCurve(
                to: current,
                control1: CGPoint(x: bowedTargetX, y: previous.y + earlyOffset),
                control2: CGPoint(x: previous.x, y: current.y - earlyOffset)
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
