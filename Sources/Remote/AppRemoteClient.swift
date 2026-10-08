import Foundation

@MainActor
protocol AppRemoteClient: AnyObject {
    var onEvent: ((AppRemoteClientEvent) -> Void)? { get set }
    var isConnected: Bool { get }
    var isSpotifyInstalled: Bool { get }

    func setAccessToken(_ token: String?)
    func connect()
    func disconnect()
    func authorizeAndPlay(uri: String) async throws -> AppRemoteAuthorizeOutcome
    func authorization(from url: URL) -> AppRemoteAuthorization?
    func subscribeToPlayerState() async throws -> RemotePlayerState?
    func subscribeToConnectivity() async throws
    func play(uri: String) async throws
    func pause() async throws
    func resume() async throws
    func skipToNext() async throws
    func skipToPrevious() async throws
}
