import Foundation
import Observation

@MainActor
@Observable
final class LyricsStore {
    enum Phase: Equatable {
        case loading
        case loaded(Lyrics)
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var trackURI: String?

    @ObservationIgnored private let client: LyricsClient
    @ObservationIgnored private var cache: [String: Lyrics] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored var isSample = false

    private static let cacheLimit = 60

    init(client: LyricsClient = LyricsClient()) {
        self.client = client
    }

    func load(for track: Track) async {
        trackURI = track.uri
        if let cached = cache[track.uri] {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        if isSample {
            store(Self.sample, for: track.uri)
            return
        }
        do {
            let lyrics = try await client.lyrics(for: track)
            if Task.isCancelled || trackURI != track.uri { return }
            store(lyrics, for: track.uri)
        } catch {
            if Task.isCancelled || trackURI != track.uri { return }
            phase = .failed
        }
    }

    func reset() {
        cache = [:]
        cacheOrder = []
        trackURI = nil
        phase = .loading
    }

    private func store(_ lyrics: Lyrics, for uri: String) {
        cache[uri] = lyrics
        cacheOrder.removeAll { $0 == uri }
        cacheOrder.append(uri)
        if cacheOrder.count > Self.cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
        phase = .loaded(lyrics)
    }

    private static let sample: Lyrics = .synced(
        [
            "Sample line one",
            "Sample line two with a bit more text",
            "Sample line three",
            "",
            "Sample line four goes on for quite a while so it wraps onto a second line",
            "Sample line five",
            "Sample line six",
            "",
            "Sample line seven",
            "Sample line eight with some words",
            "Sample line nine",
            "Sample line ten",
            "Sample line eleven",
            "Sample line twelve"
        ]
        .enumerated()
        .map { LyricLine(id: $0.offset, time: 62 + Double($0.offset) * 4, text: $0.element) }
    )
}
