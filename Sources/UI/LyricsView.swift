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
    @State private var pausedUntil = Date.distantPast
    let lines: [LyricLine]

    private static let lead = 0.25

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let seconds = player.positionMs(at: context.date) / 1000 + Self.lead
            let current = Lyrics.index(of: lines, at: seconds)
            scroller(current: current)
        }
    }

    private func scroller(current: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? "\u{266A}" : line.text)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white.opacity(line.id == current ? 1 : 0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await player.seek(to: line.time * 1000) }
                            }
                            .id(line.id)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: current)
                .padding(.vertical, 140)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                pausedUntil = phase == .idle ? Date().addingTimeInterval(3) : .distantFuture
            }
            .onChange(of: current) { _, line in
                guard let line, Date() >= pausedUntil else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(line, anchor: .center)
                }
            }
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .fadedEdges()
    }
}

private struct PlainLyrics: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 40)
        }
        .scrollIndicators(.hidden)
        .fadedEdges()
    }
}

private extension View {
    func fadedEdges() -> some View {
        mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
