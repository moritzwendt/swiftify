import Foundation

struct CachedTrackList: Codable {
    let version: Int
    let stamp: String
    let tracks: [Track]
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

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
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
