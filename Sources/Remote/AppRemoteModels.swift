import Foundation

enum RemoteRepeatMode: Equatable {
    case off
    case track
    case context
}

struct RemoteTrack: Equatable {
    var uri: String
    var name: String
    var artistName: String
    var artistURI: String
    var albumName: String
    var albumURI: String
    var durationMs: Int
    var imageIdentifier: String
    var isSaved: Bool
    var isEpisode: Bool
    var isPodcast: Bool
    var isAdvertisement: Bool
}

struct RemotePlayerState: Equatable {
    var track: RemoteTrack
    var positionMs: Int
    var playbackSpeed: Double
    var isPaused: Bool
    var isShuffling: Bool
    var repeatMode: RemoteRepeatMode
    var contextURI: String?
    var contextTitle: String?
    var canSkipNext: Bool
    var canSkipPrevious: Bool
    var canSeek: Bool
    var receivedAt: Date

    func positionMs(at date: Date) -> Double {
        let limit = track.durationMs > 0 ? Double(track.durationMs) : Double.greatestFiniteMagnitude
        let base = Double(positionMs)
        guard !isPaused else { return min(base, limit) }
        let elapsed = max(0, date.timeIntervalSince(receivedAt)) * 1000 * playbackSpeed
        return min(base + elapsed, limit)
    }
}

struct AppRemoteAuthorization: Equatable {
    var accessToken: String?
    var errorCode: String?
    var errorDescription: String?
}

enum AppRemoteAuthorizeOutcome: Equatable {
    case started
    case spotifyNotInstalled
}

enum AppRemoteClientEvent: Equatable {
    case connected
    case connectionFailed(AppRemoteError)
    case disconnected(AppRemoteError?)
    case playerState(RemotePlayerState)
    case connectivity(isOffline: Bool)
}
