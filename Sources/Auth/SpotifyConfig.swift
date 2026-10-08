import Foundation

enum SpotifyConfig {
    static let clientID = "YOUR_CLIENT_ID"
    static let redirectScheme = "swiftify"
    static let redirectURI = "swiftify://callback"
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBase = URL(string: "https://api.spotify.com/v1")!

    static let scopes = [
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-private",
        "playlist-modify-public",
        "user-library-read",
        "user-library-modify",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "user-top-read",
        "app-remote-control"
    ]
}
