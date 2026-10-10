import Foundation

struct SpotifyImage: Codable, Hashable {
    let url: String
    let width: Int?
}

extension Optional where Wrapped == [SpotifyImage] {
    func url(atLeast width: Int) -> URL? {
        guard let images = self, !images.isEmpty else { return nil }
        if images.allSatisfy({ $0.width == nil }) { return URL(string: images[0].url) }
        let sorted = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let pick = sorted.first(where: { ($0.width ?? 0) >= width }) ?? sorted.last
        return pick.flatMap { URL(string: $0.url) }
    }
}

struct Skip: Decodable {
    init(from decoder: Decoder) throws {}
}

struct Page<T: Decodable>: Decodable {
    struct Cursors: Decodable { let after: String? }

    let items: [T]
    let next: String?
    let total: Int?
    let cursors: Cursors?

    private enum CodingKeys: String, CodingKey { case items, next, total, cursors }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        next = try container.decodeIfPresent(String.self, forKey: .next)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        cursors = try container.decodeIfPresent(Cursors.self, forKey: .cursors)
        var list = try container.nestedUnkeyedContainer(forKey: .items)
        var result: [T] = []
        while !list.isAtEnd {
            if let value = try? list.decode(T.self) {
                result.append(value)
            } else {
                _ = try? list.decode(Skip.self)
            }
        }
        items = result
    }
}

struct ArtistRef: Codable, Hashable {
    let id: String?
    let name: String
    let uri: String?
}

struct Artist: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?

    static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Album: Decodable, Hashable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id, uri, name, images, artists, releaseDate, totalTracks, albumType, tracks
    }

    let id: String
    let uri: String
    let name: String
    let images: [SpotifyImage]?
    let artists: [ArtistRef]?
    let releaseDate: String?
    let totalTracks: Int?
    let albumType: String?
    let tracks: Page<Track>?

    var artistLine: String { (artists ?? []).map(\.name).joined(separator: ", ") }
    var year: String? { releaseDate.map { String($0.prefix(4)) } }

    static func == (lhs: Album, rhs: Album) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Album: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(uri, forKey: .uri)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(artists, forKey: .artists)
        try container.encodeIfPresent(releaseDate, forKey: .releaseDate)
        try container.encodeIfPresent(totalTracks, forKey: .totalTracks)
        try container.encodeIfPresent(albumType, forKey: .albumType)
    }
}

struct Track: Codable, Hashable, Identifiable {
    let id: String?
    let uri: String
    let name: String
    let artists: [ArtistRef]?
    let album: Album?
    let durationMs: Int?
    let trackNumber: Int?
    let explicit: Bool?

    var artistLine: String { (artists ?? []).map(\.name).joined(separator: ", ") }

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.uri == rhs.uri }
    func hash(into hasher: inout Hasher) { hasher.combine(uri) }
}

struct Owner: Decodable, Hashable {
    let id: String
    let displayName: String?
}

struct Playlist: Decodable, Hashable, Identifiable {
    struct Counts: Decodable { let total: Int? }

    let id: String
    let uri: String
    var name: String
    var images: [SpotifyImage]?
    let owner: Owner?
    var collaborative: Bool?
    var description: String?
    var `public`: Bool?
    let items: Counts?
    let tracks: Counts?
    var snapshotId: String?

    var trackCount: Int? { items?.total ?? tracks?.total }

    static func savesLabel(_ count: Int) -> String {
        count == 1 ? "1 save" : "\(count.formatted()) saves"
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Track {
    func matches(_ needle: String) -> Bool {
        name.localizedCaseInsensitiveContains(needle)
            || artistLine.localizedCaseInsensitiveContains(needle)
            || (album?.name.localizedCaseInsensitiveContains(needle) ?? false)
    }
}

struct URIRef: Decodable {
    let uri: String?
}

struct URIItem: Decodable {
    let item: URIRef?
    let track: URIRef?

    var uri: String? { item?.uri ?? track?.uri }
}

struct SnapshotResponse: Decodable {
    let snapshotId: String?
}

struct Me: Decodable {
    let id: String
    let displayName: String?
    let images: [SpotifyImage]?
}

struct SavedAlbum: Decodable {
    let addedAt: String?
    let album: Album
}

struct SavedTrack: Decodable {
    let addedAt: String?
    let track: Track
}

struct PlaylistItem: Decodable {
    let item: Track?
    let track: Track?

    var resolved: Track? { item ?? track }
}

struct PlayHistory: Decodable {
    let track: Track?
    let playedAt: String?
    let context: PlayerContext?
}

struct FollowedResponse: Decodable {
    let artists: Page<Artist>
}

struct SearchResults: Decodable {
    let tracks: Page<Track>?
    let artists: Page<Artist>?
    let albums: Page<Album>?
    let playlists: Page<Playlist>?
}

struct SpotifyDevice: Decodable, Identifiable, Equatable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool
    let isRestricted: Bool?
    let supportsVolume: Bool?
    let volumePercent: Int?

    var isUsable: Bool { id != nil && isRestricted != true }

    var symbol: String { Self.symbol(for: type) }

    static func symbol(for type: String?) -> String {
        switch type {
        case "Computer": "macbook"
        case "Tablet": "ipad"
        case "Smartphone": "iphone"
        case "Speaker": "hifispeaker"
        case "AVR": "hifispeaker.2"
        case "TV", "STB", "CastVideo": "tv"
        case "GameConsole": "gamecontroller"
        case "Automobile": "car"
        case "AudioDongle", "CastAudio": "airplayaudio"
        default: "speaker.wave.2"
        }
    }
}

struct DevicesResponse: Decodable {
    let devices: [SpotifyDevice]
}

struct PlaylistsResponse: Decodable {
    let items: [Playlist]
}

struct PlayerContext: Decodable {
    let uri: String?
    let type: String?
}

struct QueueResponse: Decodable {
    let currentlyPlaying: Track?
    let queue: [Track]

    private enum CodingKeys: String, CodingKey { case currentlyPlaying, queue }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentlyPlaying = try? container.decodeIfPresent(Track.self, forKey: .currentlyPlaying)
        var result: [Track] = []
        if var list = try? container.nestedUnkeyedContainer(forKey: .queue) {
            while !list.isAtEnd {
                if let value = try? list.decode(Track.self) {
                    result.append(value)
                } else {
                    _ = try? list.decode(Skip.self)
                }
            }
        }
        queue = result
    }
}

struct PlayerStateResponse: Decodable {
    let isPlaying: Bool
    let context: PlayerContext?
    let progressMs: Int?
    let shuffleState: Bool?
    let repeatState: String?
    let item: Track?
    let device: SpotifyDevice?
}
