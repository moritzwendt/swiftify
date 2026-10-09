import SwiftUI

struct LyricsView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(LyricsStore.self) private var lyrics

    private var isCurrent: Bool { lyrics.trackURI == player.track?.uri }

    var body: some View {
        content
            .task(id: player.track?.uri) {
                guard let track = player.track else { return }
                await lyrics.load(for: track)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !isCurrent {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch lyrics.phase {
            case .loading:
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                message("Lyrics are not available right now", symbol: "wifi.exclamationmark")
            case .loaded(.synced(let lines)):
                SyncedLyrics(lines: lines)
                    .id(lyrics.trackURI)
            case .loaded(.plain(let text)):
                PlainLyrics(text: text)
            case .loaded(.instrumental):
                message("Instrumental", symbol: "music.note")
            case .loaded(.notFound):
                message("No lyrics found", symbol: "quote.bubble")
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
            Text(text)
                .font(.headline)
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SyncedLyrics: View {
    @Environment(PlayerManager.self) private var player
    let lines: [LyricLine]

    var body: some View {
        let rows = LyricRow.rows(from: lines, trackDuration: player.durationMs > 0 ? player.durationMs / 1000 : nil)
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let seconds = player.positionMs(at: context.date) / 1000 + LyricStyle.lead
            LyricScroller(rows: rows, current: LyricRow.index(of: rows, at: seconds))
                .equatable()
        }
    }
}

private final class ScrollMetrics {
    var frames: [Int: CGRect] = [:]
    var offset: CGFloat = 0
    var lastStagger = Date.distantPast
}

private struct LyricScroller: View, Equatable {
    @Environment(PlayerManager.self) private var player
    let rows: [LyricRow]
    let current: Int?

    @State private var position = ScrollPosition(y: 0)
    @State private var metrics = ScrollMetrics()
    @State private var viewport: CGFloat = 0
    @State private var placed = false
    @State private var following = true
    @State private var lag: CGFloat = 0
    @State private var lagAnimates = false
    @State private var resume: Task<Void, Never>?

    nonisolated static func == (lhs: LyricScroller, rhs: LyricScroller) -> Bool {
        lhs.current == rhs.current && lhs.rows == rhs.rows
    }

    private static let space = "lyricContent"
    private static let anchorFraction: CGFloat = 0.15

    private var anchor: CGFloat { viewport * Self.anchorFraction }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    LyricRowView(
                        row: row,
                        distance: abs(row.id - (current ?? -1)),
                        isPast: row.id < (current ?? -1),
                        sharp: !following,
                        lag: lag,
                        lagAnimation: lagAnimation(for: row.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { select(row) }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.space))
                    } action: { frame in
                        metrics.frames[row.id] = frame
                        placeIfReady()
                    }
                }
            }
            .coordinateSpace(.named(Self.space))
            .padding(.top, anchor)
            .padding(.bottom, max(viewport - anchor, 0))
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
            viewport = height
            if placed {
                replace()
            } else {
                placeIfReady()
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
            metrics.offset = offset
        }
        .onScrollPhaseChange { _, phase in
            switch phase {
            case .interacting, .decelerating:
                resume?.cancel()
                following = false
            case .idle:
                if !following { scheduleResume() }
            default:
                break
            }
        }
        .onChange(of: current) { _, new in
            guard placed, following else { return }
            follow(new ?? 0, staggered: true)
        }
        .opacity(placed ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: placed)
        .animation(.easeInOut(duration: 0.3), value: following)
        .fadedEdges()
    }

    private func lagAnimation(for index: Int) -> Animation? {
        guard lagAnimates else { return nil }
        let steps = max(index - (current ?? 0), 0)
        return .spring(duration: 0.6, bounce: 0.1).delay(Double(min(steps, 8)) * 0.045)
    }

    private func target(for index: Int) -> CGFloat? {
        metrics.frames[index]?.minY
    }

    private func placeIfReady() {
        guard !placed, viewport > 0, metrics.frames.count >= rows.count,
              let target = target(for: current ?? 0) else { return }
        placed = true
        metrics.offset = target
        position.scrollTo(y: target)
    }

    private func replace() {
        guard following, let target = target(for: current ?? 0) else { return }
        metrics.offset = target
        position.scrollTo(y: target)
    }

    private func follow(_ index: Int, staggered: Bool) {
        guard let target = target(for: index) else { return }
        let delta = target - metrics.offset
        guard abs(delta) > 0.5 else { return }
        let settled = Date().timeIntervalSince(metrics.lastStagger) > 1
        metrics.offset = target
        guard staggered, settled, abs(delta) < viewport * 0.9 else {
            withAnimation(.smooth(duration: 0.6)) {
                position.scrollTo(y: target)
            }
            return
        }
        metrics.lastStagger = Date()
        lagAnimates = false
        lag = delta
        position.scrollTo(y: target)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(24))
            lagAnimates = true
            lag = 0
        }
    }

    private func scheduleResume() {
        resume?.cancel()
        resume = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            following = true
            follow(current ?? 0, staggered: false)
        }
    }

    private func select(_ row: LyricRow) {
        guard row.kind == .line else { return }
        resume?.cancel()
        following = true
        Task {
            await player.seek(to: row.start * 1000)
        }
        follow(row.id, staggered: false)
    }
}

private struct PlainLyrics: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 24, weight: .bold))
                .lineSpacing(6)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .fadedEdges()
    }
}

private extension View {
    func fadedEdges() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
            }
        }
    }
}
