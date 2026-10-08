import SwiftUI
import UIKit
import CryptoKit

actor ImageCache {
    static let shared = ImageCache()

    nonisolated(unsafe) private let memory = NSCache<NSURL, UIImage>()
    private let directory: URL
    private var limitBytes: Int {
        let megabytes = UserDefaults.standard.integer(forKey: "settings.imageCacheLimitMB")
        return (megabytes > 0 ? megabytes : 300) * 1024 * 1024
    }
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var writes = 0

    init() {
        directory = URL.cachesDirectory.appending(path: "Images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.totalCostLimit = 80 * 1024 * 1024
    }

    nonisolated func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }
        let task = Task<UIImage?, Never> { await load(url) }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        return result
    }

    func prefetch(_ urls: [URL]) async {
        var iterator = urls.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                guard let url = iterator.next() else { break }
                group.addTask(priority: .utility) { await self.warm(url) }
            }
            while await group.next() != nil {
                guard let url = iterator.next() else { continue }
                group.addTask(priority: .utility) { await self.warm(url) }
            }
        }
    }

    func stats() async -> (count: Int, bytes: Int) {
        let folder = directory
        return await Task.detached(priority: .utility) { directoryStats(folder) }.value
    }

    func trimNow() {
        trim()
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func load(_ url: URL) async -> UIImage? {
        let file = fileURL(for: url)
        if let image = await Self.decode(file: file) {
            store(image, for: url)
            return image
        }
        guard let data = await download(url), let image = await Self.decode(data: data) else { return nil }
        write(data, to: file)
        store(image, for: url)
        return image
    }

    private func warm(_ url: URL) async {
        let file = fileURL(for: url)
        if FileManager.default.fileExists(atPath: file.path()) { return }
        guard let data = await download(url) else { return }
        write(data, to: file)
    }

    private func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }

    private func write(_ data: Data, to file: URL) {
        try? data.write(to: file, options: .atomic)
        writes += 1
        if writes % 100 == 1 { trim() }
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return directory.appending(path: digest.map { String(format: "%02x", $0) }.joined())
    }

    private func trim() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { file -> (URL, Int, Date)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize, let date = values.contentModificationDate else { return nil }
            return (file, size, date)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > limitBytes else { return }
        entries.sort { $0.2 < $1.2 }
        for entry in entries where total > limitBytes * 8 / 10 {
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.1
        }
    }

    private static func decode(file: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: file) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }.value
    }

    private static func decode(data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }
}

extension ImageCache {
    func prefetchArtwork(of tracks: [Track], limit: Int = 600) async {
        var seen = Set<URL>()
        let urls = tracks.compactMap { $0.album?.images.url(atLeast: 100) }.filter { seen.insert($0).inserted }
        await prefetch(Array(urls.prefix(limit)))
    }
}

struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: Placeholder
    @State private var loaded: (url: URL, image: UIImage)?

    private var current: UIImage? {
        guard let url else { return nil }
        if let hit = ImageCache.shared.memoryImage(for: url) { return hit }
        return loaded?.url == url ? loaded?.image : nil
    }

    var body: some View {
        ZStack {
            if let current {
                Image(uiImage: current).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url, ImageCache.shared.memoryImage(for: url) == nil else { return }
            if let image = await ImageCache.shared.image(for: url) { loaded = (url, image) }
        }
    }
}
