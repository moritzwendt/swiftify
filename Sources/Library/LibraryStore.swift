import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var me: Me?
    private(set) var playlists: [Playlist] = []
    private(set) var albums: [SavedAlbum] = []
    private(set) var artists: [Artist] = []
    private(set) var likedTotal = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var downloaded: Set<String>
    private(set) var recentOrder: [String] = []

    @ObservationIgnored let api: SpotifyAPI
    @ObservationIgnored var isSample = false

    private static let downloadedKey = "downloadedMarks"

    init(api: SpotifyAPI) {
        self.api = api
        downloaded = Set(UserDefaults.standard.stringArray(forKey: Self.downloadedKey) ?? [])
    }

    func load(force: Bool = false) async {
        if isSample || isLoading || (hasLoaded && !force) { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        async let meResult: Me? = try? api.get("me")
        async let playlistResult: [Playlist] = pages("me/playlists")
        async let albumResult: [SavedAlbum] = pages("me/albums")
        async let artistResult: [Artist] = followedArtists()
        async let likedResult: Page<SavedTrack>? = try? api.get("me/tracks", query: ["limit": "1"])
        async let historyResult: Page<PlayHistory>? = try? api.get("me/player/recently-played", query: ["limit": "50"])
        let loadedMe = await meResult
        let loadedPlaylists = await playlistResult
        let loadedAlbums = await albumResult
        let loadedArtists = await artistResult
        let loadedLiked = await likedResult
        let loadedHistory = await historyResult
        if let loadedMe { me = loadedMe }
        playlists = loadedPlaylists
        albums = loadedAlbums
        artists = loadedArtists
        likedTotal = loadedLiked?.total ?? likedTotal
        var seen = Set<String>()
        recentOrder = (loadedHistory?.items ?? [])
            .compactMap { $0.context?.uri }
            .filter { seen.insert($0).inserted }
    }

    func noteRecent(_ uri: String) {
        recentOrder.removeAll { $0 == uri }
        recentOrder.insert(uri, at: 0)
    }

    func reset() {
        me = nil
        playlists = []
        albums = []
        artists = []
        likedTotal = 0
        recentOrder = []
        hasLoaded = false
    }

    func canListTracks(of playlist: Playlist) -> Bool {
        if isSample { return true }
        guard let me else { return false }
        return playlist.owner?.id == me.id || playlist.collaborative == true
    }

    func isDownloaded(_ uri: String) -> Bool { downloaded.contains(uri) }

    func toggleDownloaded(_ uri: String) {
        if downloaded.contains(uri) {
            downloaded.remove(uri)
        } else {
            downloaded.insert(uri)
        }
        UserDefaults.standard.set(Array(downloaded), forKey: Self.downloadedKey)
    }

    func clearDownloaded() {
        downloaded = []
        UserDefaults.standard.removeObject(forKey: Self.downloadedKey)
    }

    func createPlaylist(named name: String) async throws {
        let created: Playlist = try await api.post("me/playlists", body: ["name": name, "public": false])
        playlists.insert(created, at: 0)
    }

    func loadSample(me: Me, playlists: [Playlist], albums: [SavedAlbum], artists: [Artist], likedTotal: Int) {
        isSample = true
        self.me = me
        self.playlists = playlists
        self.albums = albums
        self.artists = artists
        self.likedTotal = likedTotal
        hasLoaded = true
    }

    private func pages<T: Decodable>(_ path: String, limit: Int = 50) async -> [T] {
        var result: [T] = []
        var offset = 0
        while offset < 1000 {
            let page: Page<T>? = try? await api.get(path, query: ["limit": "\(limit)", "offset": "\(offset)"])
            guard let page else { break }
            result += page.items
            offset += limit
            if let total = page.total, offset >= total { break }
            if page.next == nil { break }
        }
        return result
    }

    private func followedArtists() async -> [Artist] {
        var result: [Artist] = []
        var after: String?
        for _ in 0..<10 {
            var query = ["type": "artist", "limit": "50"]
            if let after { query["after"] = after }
            let response: FollowedResponse? = try? await api.get("me/following", query: query)
            guard let page = response?.artists else { break }
            result += page.items
            after = page.cursors?.after
            if after == nil || page.items.isEmpty { break }
        }
        return result
    }
}
