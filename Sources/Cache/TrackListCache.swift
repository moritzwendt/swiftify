import Foundation

struct CachedTrackList: Codable {
    let version: Int
    let stamp: String
    let tracks: [Track]
}

func directoryStats(_ directory: URL) -> (count: Int, bytes: Int) {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    return (files.count, bytes)
}

enum TrackListCache {
    private static let version = 1

    private static var directory: URL {
        URL.cachesDirectory.appending(path: "TrackLists", directoryHint: .isDirectory)
    }

    static func load(key: String) async -> CachedTrackList? {
        let file = directory.appending(path: "\(key).json")
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: file),
                  let list = try? JSONDecoder().decode(CachedTrackList.self, from: data),
                  list.version == version else { return nil }
            return list
        }.value
    }

    static func save(key: String, stamp: String, tracks: [Track]) async {
        let folder = directory
        let file = folder.appending(path: "\(key).json")
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let list = CachedTrackList(version: version, stamp: stamp, tracks: tracks)
            guard let data = try? JSONEncoder().encode(list) else { return }
            try? data.write(to: file, options: .atomic)
        }.value
    }

    static func stats() async -> (count: Int, bytes: Int) {
        let folder = directory
        return await Task.detached(priority: .utility) { directoryStats(folder) }.value
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum TrackListLoader {
    struct LikedResult {
        let tracks: [Track]
        let stamp: String
        let fromCache: Bool
    }

    @MainActor
    static func playlist(api: SpotifyAPI, id: String, progress: ([Track]) -> Void) async -> [Track]? {
        let path = "playlists/\(id)/items"
        let first: Page<PlaylistItem>? = try? await api.get(path, query: ["limit": "50", "offset": "0"])
        guard let first else { return nil }
        var tracks = first.items.compactMap(\.resolved)
        progress(tracks)
        let finished = await PagedLoader.loadRemaining(api: api, path: path, first: first) {
            tracks += $0.compactMap(\.resolved)
            progress(tracks)
        }
        return finished ? tracks : nil
    }

    @MainActor
    static func liked(api: SpotifyAPI, known: CachedTrackList?, progress: ([Track]) -> Void) async -> LikedResult? {
        let path = "me/tracks"
        let first: Page<SavedTrack>? = try? await api.get(path, query: ["limit": "50", "offset": "0"])
        guard let first else { return nil }
        var tracks = first.items.map(\.track)
        let stamp = "\(first.total ?? 0)|\(tracks.first?.uri ?? "")"
        if let known, known.stamp == stamp {
            return LikedResult(tracks: known.tracks, stamp: stamp, fromCache: true)
        }
        progress(tracks)
        let finished = await PagedLoader.loadRemaining(api: api, path: path, first: first) {
            tracks += $0.map(\.track)
            progress(tracks)
        }
        return finished ? LikedResult(tracks: tracks, stamp: stamp, fromCache: false) : nil
    }
}

enum PagedLoader {
    @MainActor
    static func loadRemaining<Item: Decodable>(
        api: SpotifyAPI,
        path: String,
        first: Page<Item>,
        pageSize: Int = 50,
        concurrency: Int = 4,
        append: ([Item]) -> Void
    ) async -> Bool {
        guard let total = first.total, total > pageSize else { return true }
        let offsets = Array(stride(from: pageSize, to: total, by: pageSize))
        for start in stride(from: 0, to: offsets.count, by: concurrency) {
            let chunk = Array(offsets[start..<min(start + concurrency, offsets.count)])
            let pages = await withTaskGroup(of: (Int, Page<Item>?).self) { group in
                for offset in chunk {
                    group.addTask { (offset, await fetchPage(api: api, path: path, offset: offset, pageSize: pageSize)) }
                }
                var result: [Int: Page<Item>] = [:]
                for await (offset, page) in group {
                    if let page { result[offset] = page }
                }
                return result
            }
            if Task.isCancelled { return false }
            for offset in chunk {
                guard let page = pages[offset] else { return false }
                append(page.items)
            }
        }
        return true
    }

    private static func fetchPage<Item: Decodable>(api: SpotifyAPI, path: String, offset: Int, pageSize: Int) async -> Page<Item>? {
        for _ in 0..<2 {
            if Task.isCancelled { return nil }
            let page: Page<Item>? = try? await api.get(path, query: ["limit": "\(pageSize)", "offset": "\(offset)"])
            if let page { return page }
        }
        return nil
    }
}
