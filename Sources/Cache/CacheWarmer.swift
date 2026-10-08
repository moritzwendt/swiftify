import Foundation
import Observation

@MainActor
@Observable
final class CacheWarmer {
    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var total = 0
    private(set) var failed = 0
    private(set) var currentName = ""
    private(set) var lastResult: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(library: LibraryStore, settings: AppSettings, force: Bool) {
        guard !isRunning, !library.isSample else { return }
        let playlists = library.editablePlaylists
        let api = library.api
        let cacheLists = settings.cacheLists
        let cacheImages = settings.cacheImages
        isRunning = true
        done = 0
        failed = 0
        total = playlists.count + 1
        lastResult = nil
        task = Task { [weak self] in
            await self?.run(api: api, playlists: playlists, force: force, cacheLists: cacheLists, cacheImages: cacheImages)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(api: SpotifyAPI, playlists: [Playlist], force: Bool, cacheLists: Bool, cacheImages: Bool) async {
        currentName = "Liked Songs"
        let likedOK = await warmLiked(api: api, force: force, cacheLists: cacheLists, cacheImages: cacheImages)
        if !Task.isCancelled {
            if !likedOK { failed += 1 }
            done += 1
        }
        for playlist in playlists {
            if Task.isCancelled { break }
            currentName = playlist.name
            let ok = await warm(playlist, api: api, force: force, cacheLists: cacheLists, cacheImages: cacheImages)
            if Task.isCancelled { break }
            if !ok { failed += 1 }
            done += 1
        }
        isRunning = false
        if Task.isCancelled {
            lastResult = "Stopped at \(done) of \(total)"
        } else if failed == 0 {
            lastResult = "Cached \(total) lists"
        } else {
            lastResult = "Cached \(total - failed) of \(total), \(failed) failed"
        }
    }

    private func warmLiked(api: SpotifyAPI, force: Bool, cacheLists: Bool, cacheImages: Bool) async -> Bool {
        let known = force || !cacheLists ? nil : await TrackListCache.load(key: LikedSongsView.contextKey)
        guard let result = await TrackListLoader.liked(api: api, known: known, progress: { _ in }) else { return false }
        if cacheLists, !result.fromCache {
            await TrackListCache.save(key: LikedSongsView.contextKey, stamp: result.stamp, tracks: result.tracks)
        }
        if cacheImages { await ImageCache.shared.prefetchArtwork(of: result.tracks, limit: 3000) }
        return true
    }

    private func warm(_ playlist: Playlist, api: SpotifyAPI, force: Bool, cacheLists: Bool, cacheImages: Bool) async -> Bool {
        var tracks: [Track]?
        if !force, cacheLists, let snapshot = playlist.snapshotId,
           let cached = await TrackListCache.load(key: playlist.id), cached.stamp == snapshot {
            tracks = cached.tracks
        }
        if tracks == nil {
            guard let fetched = await TrackListLoader.playlist(api: api, id: playlist.id, progress: { _ in }) else { return false }
            if cacheLists, let snapshot = playlist.snapshotId {
                await TrackListCache.save(key: playlist.id, stamp: snapshot, tracks: fetched)
            }
            tracks = fetched
        }
        if cacheImages {
            let covers = [playlist.images.url(atLeast: 100), playlist.images.url(atLeast: 640)].compactMap { $0 }
            await ImageCache.shared.prefetch(covers)
            await ImageCache.shared.prefetchArtwork(of: tracks ?? [], limit: 3000)
        }
        return true
    }
}
