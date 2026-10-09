import Foundation

@MainActor
enum SampleData {
    private static func decode<T: Decodable>(_ json: String) -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(T.self, from: Data(json.utf8))
    }

    static func install(library: LibraryStore, player: PlayerManager, queue: QueueStore, lyrics: LyricsStore) {
        let me: Me = decode(#"{"id":"me","display_name":"Moritz"}"#)
        let names = ["Daily Mix 1", "Late Night Drive", "Gym Energy", "Focus Flow", "Road Trip", "Sunday Jazz", "Indie Gems"]
        let playlists: [Playlist] = names.enumerated().map { index, name in
            decode(#"{"id":"p\#(index)","uri":"spotify:playlist:p\#(index)","name":"\#(name)","owner":{"id":"\#(index % 3 == 0 ? "spotify" : "me")","display_name":"\#(index % 3 == 0 ? "Spotify" : "Moritz")"},"items":{"total":\#(20 + index)}}"#)
        }
        let albumNames = ["Currents", "Random Access Memories", "Blonde", "Discovery"]
        let albums: [SavedAlbum] = albumNames.enumerated().map { index, name in
            decode(#"{"album":{"id":"a\#(index)","uri":"spotify:album:a\#(index)","name":"\#(name)","artists":[{"name":"Various Artist"}],"release_date":"2020-01-01"}}"#)
        }
        let artists: [Artist] = ["Tame Impala", "Daft Punk", "Frank Ocean"].enumerated().map { index, name in
            decode(#"{"id":"r\#(index)","uri":"spotify:artist:r\#(index)","name":"\#(name)"}"#)
        }
        library.loadSample(me: me, playlists: playlists, albums: albums, artists: artists, likedTotal: 482)
        library.membership.loadSample(["p1": ["spotify:track:t1"]])
        let devices: [SpotifyDevice] = decode(#"[{"id":"d1","is_active":true,"is_restricted":false,"name":"iPhone","type":"Smartphone","supports_volume":false},{"id":"d2","is_active":false,"is_restricted":false,"name":"MacBook Pro von Moritz","type":"Computer","supports_volume":true,"volume_percent":55},{"id":"d3","is_active":false,"is_restricted":false,"name":"Living Room","type":"Speaker","supports_volume":true,"volume_percent":30},{"id":"d4","is_active":false,"is_restricted":false,"name":"Samsung TV","type":"TV"},{"id":null,"is_active":false,"is_restricted":true,"name":"Kitchen Display","type":"CastVideo"}]"#)
        player.loadSample(queue: Array(tracks.prefix(3)), positionMs: 64000, context: "spotify:playlist:p0", devices: devices)
        queue.loadSample(upcoming: Array(tracks.dropFirst(3).prefix(8)))
        lyrics.isSample = true
    }

    static let tracks: [Track] = [
        track("t1", "The Less I Know The Better", "Tame Impala", 216000),
        track("t2", "Instant Crush", "Daft Punk", 337000),
        track("t3", "Nights", "Frank Ocean", 307000),
        track("t4", "Let It Happen", "Tame Impala", 467000),
        track("t5", "Get Lucky", "Daft Punk", 369000),
        track("t6", "Pink + White", "Frank Ocean", 184000),
        track("t7", "Borderline", "Tame Impala", 237000),
        track("t8", "One More Time", "Daft Punk", 320000),
        track("t9", "Self Control", "Frank Ocean", 249000),
        track("t10", "Eventually", "Tame Impala", 319000),
        track("t11", "Digital Love", "Daft Punk", 301000),
        track("t12", "Ivy", "Frank Ocean", 249000)
    ]

    private static func track(_ id: String, _ name: String, _ artist: String, _ duration: Int) -> Track {
        decode(#"{"uri":"spotify:track:\#(id)","name":"\#(name)","artists":[{"name":"\#(artist)"}],"duration_ms":\#(duration)}"#)
    }
}
