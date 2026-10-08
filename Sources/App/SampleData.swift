import Foundation

@MainActor
enum SampleData {
    private static func decode<T: Decodable>(_ json: String) -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(T.self, from: Data(json.utf8))
    }

    static func install(library: LibraryStore, player: PlayerManager) {
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
        let track: Track = decode(#"{"uri":"spotify:track:t1","name":"The Less I Know The Better","artists":[{"name":"Tame Impala"}],"duration_ms":216000}"#)
        player.loadSample(track: track, positionMs: 64000, context: "spotify:playlist:p0")
    }
}
