import Foundation
import Observation

@MainActor
@Observable
final class MembershipStore {
    private struct Entry: Codable {
        var snapshot: String
        var uris: [String]
    }

    private(set) var tracks: [String: Set<String>] = [:]
    private(set) var scanning: Set<String> = []
    private(set) var skipped: Set<String> = []
    @ObservationIgnored private var snapshots: [String: String] = [:]
    @ObservationIgnored private let api: SpotifyAPI
    @ObservationIgnored private var runningScan: Task<Void, Never>?
    @ObservationIgnored private var failureCount = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var isSample = false

    private static let maxTrackCount = 1000
    private static let pageDelay: Duration = .milliseconds(250)

    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "membership.json")
    }

    init(api: SpotifyAPI) {
        self.api = api
        if let data = try? Data(contentsOf: Self.fileURL),
           let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            for (id, entry) in stored {
                tracks[id] = Set(entry.uris)
                snapshots[id] = entry.snapshot
            }
        }
    }

    func contains(_ playlistID: String, uri: String) -> Bool? {
        tracks[playlistID]?.contains(uri)
    }

    func isInAny(_ uri: String) -> Bool {
        tracks.values.contains { $0.contains(uri) }
    }

    func reset() {
        generation += 1
        runningScan?.cancel()
        runningScan = nil
        tracks = [:]
        snapshots = [:]
        scanning = []
        skipped = []
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    func loadSample(_ values: [String: Set<String>]) {
        isSample = true
        tracks = values
    }

    func scan(_ playlists: [Playlist]) async {
        if isSample { return }
        if let running = runningScan { await running.value }
        let pending = playlists.filter(needsScan)
        guard !pending.isEmpty else { return }
        failureCount = 0
        let startedIn = generation
        let task = Task { await runScan(pending) }
        runningScan = task
        await task.value
        guard startedIn == generation else { return }
        runningScan = nil
        persist()
    }

    func recordRemoval(playlistID: String, uris: [String], snapshot: String?) {
        var set = tracks[playlistID] ?? []
        set.subtract(uris)
        tracks[playlistID] = set
        if let snapshot { snapshots[playlistID] = snapshot }
        persist()
    }

    func recordAll(playlistID: String, uris: [String], snapshot: String?) {
        var set = tracks[playlistID] ?? []
        set.formUnion(uris)
        tracks[playlistID] = set
        if let snapshot { snapshots[playlistID] = snapshot }
        persist()
    }

    func record(playlistID: String, uri: String, added: Bool, snapshot: String?) {
        var set = tracks[playlistID] ?? []
        if added { set.insert(uri) } else { set.remove(uri) }
        tracks[playlistID] = set
        if let snapshot { snapshots[playlistID] = snapshot }
        persist()
    }

    private func runScan(_ pending: [Playlist]) async {
        for playlist in pending {
            if Task.isCancelled || failureCount >= 3 { return }
            await scanOne(playlist)
        }
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
        let startedIn = generation
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
            guard let page else {
                failureCount += 1
                return
            }
            found.formUnion(page.items.compactMap(\.uri))
            offset += 50
            if page.next == nil { break }
            try? await Task.sleep(for: Self.pageDelay)
        }
        guard startedIn == generation, !Task.isCancelled else { return }
        tracks[playlist.id] = found
        snapshots[playlist.id] = playlist.snapshotId ?? ""
        try? await Task.sleep(for: Self.pageDelay)
    }

    private func persist() {
        var stored: [String: Entry] = [:]
        for (id, set) in tracks {
            stored[id] = Entry(snapshot: snapshots[id] ?? "", uris: Array(set))
        }
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
