import SwiftUI

enum LyricStyle {
    static let lead = 0.25
    static let dim = 0.36
    static let dimWhileScrolling = 0.55
    static let spacing: CGFloat = 11
}

struct LyricFillRenderer: TextRenderer {
    var progress: Double
    var highlight: Double
    var base: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(highlight, base) }
        set {
            highlight = newValue.first
            base = newValue.second
        }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var total = 0
        for line in layout {
            for run in line {
                total += run.count
            }
        }
        let edge = 5.0
        let front = progress * (Double(total) + edge)
        let lit = min(max(highlight, 0), 1)
        let floor = min(max(base, 0), 1)
        var index = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let reach = min(max((front - Double(index)) / edge, 0), 1) * lit
                    var copy = context
                    copy.opacity = floor + (1 - floor) * reach
                    copy.draw(slice)
                    index += 1
                }
            }
        }
    }
}

struct LyricRowView: View {
    @Environment(PlayerManager.self) private var player
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 32

    let row: LyricRow
    let distance: Int
    let isPast: Bool
    let sharp: Bool
    let lag: CGFloat
    let lagAnimation: Animation?

    private struct Appearance: Equatable {
        var blur: CGFloat
        var highlight: Double
        var base: Double
    }

    private var isActive: Bool { distance == 0 }

    private var appearance: Appearance {
        Appearance(
            blur: sharp || isActive ? 0 : CGFloat(min(distance, 5)) * 0.85,
            highlight: isActive ? 1 : 0,
            base: sharp ? LyricStyle.dimWhileScrolling : LyricStyle.dim
        )
    }

    var body: some View {
        Group {
            switch row.kind {
            case .line: line
            case .interlude: InterludeDots(row: row, active: isActive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: lag)
        .animation(lagAnimation, value: lag)
    }

    private var line: some View {
        let look = appearance
        return TimelineView(.animation(paused: !(isActive && player.isPlaying))) { context in
            Text(row.text)
                .font(.system(size: size, weight: .bold))
                .lineSpacing(-1)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .textRenderer(
                    LyricFillRenderer(
                        progress: progress(at: context.date),
                        highlight: look.highlight,
                        base: look.base
                    )
                )
        }
        .padding(.vertical, LyricStyle.spacing)
        .padding(.trailing, 20)
        .blur(radius: look.blur)
        .animation(.smooth(duration: 0.45), value: look)
        .scaleEffect(isActive || sharp ? 1 : 0.94, anchor: .leading)
        .animation(.spring(duration: 0.55, bounce: 0.28), value: isActive || sharp)
    }

    private func progress(at date: Date) -> Double {
        if !isActive { return isPast ? 1 : 0 }
        let seconds = player.positionMs(at: date) / 1000 + LyricStyle.lead
        return min(max((seconds - row.start) / row.fillDuration, 0), 1)
    }
}

struct InterludeDots: View {
    @Environment(PlayerManager.self) private var player
    let row: LyricRow
    let active: Bool

    private static let diameter: CGFloat = 11

    var body: some View {
        TimelineView(.animation(paused: !(active && player.isPlaying))) { context in
            let seconds = player.positionMs(at: context.date) / 1000 + LyricStyle.lead
            let progress = active ? min(max((seconds - row.start) / row.duration, 0), 1) : 0
            let breath = 1 + 0.08 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.8)
            HStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(0.35 + 0.65 * min(max(progress * 3 - Double(index), 0), 1)))
                        .frame(width: Self.diameter, height: Self.diameter)
                }
            }
            .scaleEffect(breath, anchor: .leading)
        }
        .scaleEffect(active ? 1 : 0.4, anchor: .leading)
        .opacity(active ? 1 : 0)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: active)
        .frame(height: 22)
        .padding(.vertical, LyricStyle.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
