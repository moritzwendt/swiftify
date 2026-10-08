import Foundation
import Observation

@MainActor
@Observable
final class MembershipStore {
    private(set) var tracks: [String: Set<String>] = [:]
    private(set) var scanning: Set<String> = []
    private(set) var skipped: Set<String> = []
    @ObservationIgnored private var snapshots: [String: String] = [:]
    @ObservationIgnored private let api: SpotifyAPI
    @ObservationIgnored var isSample = false

    private static let maxTrackCount = 1000

    init(api: SpotifyAPI) {
        self.api = api
    }

    func contains(_ playlistID: String, uri: String) -> Bool? {
        tracks[playlistID]?.contains(uri)
    }

    func reset() {
        tracks = [:]
        snapshots = [:]
        scanning = []
        skipped = []
    }

    func loadSample(_ values: [String: Set<String>]) {
        isSample = true
        tracks = values
    }

    func scan(_ playlists: [Playlist]) async {
        if isSample { return }
        let pending = playlists.filter(needsScan)
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<2 {
                if let playlist = iterator.next() {
                    group.addTask { await self.scanOne(playlist) }
                }
            }
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll(); break }
                if let playlist = iterator.next() {
                    group.addTask { await self.scanOne(playlist) }
                }
            }
        }
    }

    func record(playlistID: String, uri: String, added: Bool, snapshot: String?) {
        var set = tracks[playlistID] ?? []
        if added { set.insert(uri) } else { set.remove(uri) }
        tracks[playlistID] = set
        if let snapshot { snapshots[playlistID] = snapshot }
    }

    private func needsScan(_ playlist: Playlist) -> Bool {
        if skipped.contains(playlist.id) { return false }
        guard tracks[playlist.id] != nil else { return true }
        guard let current = playlist.snapshotId else { return false }
        return snapshots[playlist.id] != current
    }

    private func scanOne(_ playlist: Playlist) async {
        if (playlist.trackCount ?? 0) > Self.maxTrackCount {
            skipped.insert(playlist.id)
            return
        }
        scanning.insert(playlist.id)
        defer { scanning.remove(playlist.id) }
        var found = Set<String>()
        var offset = 0
        while true {
            if Task.isCancelled { return }
            let page: Page<URIItem>? = try? await api.get(
                "playlists/\(playlist.id)/items",
                query: [
                    "limit": "50",
                    "offset": "\(offset)",
                    "fields": "items(item(uri),track(uri)),next,total"
                ]
            )
            guard let page else { return }
            found.formUnion(page.items.compactMap(\.uri))
            offset += 50
            if page.next == nil { break }
        }
        tracks[playlist.id] = found
        snapshots[playlist.id] = playlist.snapshotId ?? ""
    }
}
