import SpotifyiOS
import UIKit

@MainActor
private final class OneShot<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value, Error>, timeout: Duration) {
        self.continuation = continuation
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.fail(AppRemoteError.timedOut)
        }
    }

    func succeed(_ value: Value) {
        guard let continuation else { return }
        finish()
        continuation.resume(returning: value)
    }

    func fail(_ error: Error) {
        guard let continuation else { return }
        finish()
        continuation.resume(throwing: error)
    }

    private func finish() {
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

private extension NSObject {
    func read(_ key: String) -> Any? {
        guard responds(to: NSSelectorFromString(key)) else { return nil }
        return value(forKey: key)
    }
}

@MainActor
final class SpotifyAppRemoteClient: NSObject, AppRemoteClient {
    var onEvent: ((AppRemoteClientEvent) -> Void)?

    private let appRemote: SPTAppRemote
    private let timeout: Duration

    init(clientID: String, redirectURL: URL, timeout: Duration = .seconds(8)) {
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .error)
        self.timeout = timeout
        super.init()
        appRemote.delegate = self
    }

    var isConnected: Bool { appRemote.isConnected }

    var isSpotifyInstalled: Bool {
        guard let url = URL(string: "spotify:") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func setAccessToken(_ token: String?) {
        appRemote.connectionParameters.accessToken = token
    }

    func connect() {
        appRemote.connect()
    }

    func disconnect() {
        appRemote.disconnect()
    }

    func authorizeAndPlay(uri: String) async throws -> AppRemoteAuthorizeOutcome {
        try await withCheckedThrowingContinuation { continuation in
            let shot = OneShot<AppRemoteAuthorizeOutcome>(continuation, timeout: timeout)
            appRemote.authorizeAndPlayURI(uri) { [weak self] installed in
                self?.deliver { _ in
                    shot.succeed(installed ? .started : .spotifyNotInstalled)
                }
            }
        }
    }

    func authorization(from url: URL) -> AppRemoteAuthorization? {
        guard let parameters = appRemote.authorizationParameters(from: url) else { return nil }
        return AppRemoteAuthorization(
            accessToken: parameters[SPTAppRemoteAccessTokenKey],
            errorCode: parameters[SPTAppRemoteErrorKey],
            errorDescription: parameters[SPTAppRemoteErrorDescriptionKey]
        )
    }

    func subscribeToPlayerState() async throws -> RemotePlayerState? {
        guard let api = appRemote.playerAPI else { throw AppRemoteError.notConnected }
        api.delegate = self
        let result = try await call { api.subscribe(toPlayerState: $0) }
        return Self.map(result, at: Date())
    }

    func subscribeToConnectivity() async throws {
        guard let api = appRemote.connectivityAPI else { throw AppRemoteError.notConnected }
        api.delegate = self
        _ = try await call { api.subscribe(toConnectivityState: $0) }
    }

    func play(uri: String) async throws {
        guard let api = appRemote.playerAPI else { throw AppRemoteError.notConnected }
        _ = try await call { api.play(uri, callback: $0) }
    }

    func pause() async throws {
        guard let api = appRemote.playerAPI else { throw AppRemoteError.notConnected }
        _ = try await call { api.pause($0) }
    }

    func resume() async throws {
        guard let api = appRemote.playerAPI else { throw AppRemoteError.notConnected }
        _ = try await call { api.resume($0) }
    }

    func skipToNext() async throws {
        guard let api = appRemote.playerAPI else { throw AppRemoteError.notConnected }
        _ = try await call { api.skip(toNext: $0) }
    }

    func skipToPrevious() async throws {
        guard let api = appRemote.playerAPI else { throw AppRemoteError.notConnected }
        _ = try await call { api.skip(toPrevious: $0) }
    }

    private func call(_ invoke: (@escaping SPTAppRemoteCallback) -> Void) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            let shot = OneShot<Any?>(continuation, timeout: timeout)
            invoke { [weak self] result, error in
                self?.deliver { _ in
                    if let error {
                        shot.fail(AppRemoteError(error))
                    } else {
                        shot.succeed(result)
                    }
                }
            }
        }
    }

    nonisolated func deliver(_ work: @escaping @MainActor (SpotifyAppRemoteClient) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work(self) }
        } else {
            Task { @MainActor in work(self) }
        }
    }

    nonisolated static func map(_ object: Any?, at date: Date) -> RemotePlayerState? {
        guard let state = object as? SPTAppRemotePlayerState,
              let stateObject = state as AnyObject as? NSObject,
              let trackObject = stateObject.read("track") as? NSObject else { return nil }
        let track = trackObject as? SPTAppRemoteTrack
        let artist = trackObject.read("artist") as? NSObject
        let album = trackObject.read("album") as? NSObject
        let options = stateObject.read("playbackOptions") as? SPTAppRemotePlaybackOptions
        let restrictions = stateObject.read("playbackRestrictions") as? SPTAppRemotePlaybackRestrictions
        let remoteTrack = RemoteTrack(
            uri: trackObject.read("URI") as? String ?? "",
            name: trackObject.read("name") as? String ?? "",
            artistName: artist?.read("name") as? String ?? "",
            artistURI: artist?.read("URI") as? String ?? "",
            albumName: album?.read("name") as? String ?? "",
            albumURI: album?.read("URI") as? String ?? "",
            durationMs: (trackObject.read("duration") as? NSNumber)?.intValue ?? 0,
            imageIdentifier: trackObject.read("imageIdentifier") as? String ?? "",
            isSaved: track?.isSaved ?? false,
            isEpisode: track?.isEpisode ?? false,
            isPodcast: track?.isPodcast ?? false,
            isAdvertisement: track?.isAdvertisement ?? false
        )
        return RemotePlayerState(
            track: remoteTrack,
            positionMs: state.playbackPosition,
            playbackSpeed: Double(state.playbackSpeed),
            isPaused: state.isPaused,
            isShuffling: options?.isShuffling ?? false,
            repeatMode: repeatMode(options?.repeatMode),
            contextURI: text(stateObject.read("contextURI")),
            contextTitle: text(stateObject.read("contextTitle")),
            canSkipNext: restrictions?.canSkipNext ?? true,
            canSkipPrevious: restrictions?.canSkipPrevious ?? true,
            canSeek: restrictions?.canSeek ?? true,
            receivedAt: date
        )
    }

    private nonisolated static func text(_ value: Any?) -> String? {
        let text = (value as? URL)?.absoluteString ?? value as? String
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private nonisolated static func repeatMode(_ mode: SPTAppRemotePlaybackOptionsRepeatMode?) -> RemoteRepeatMode {
        switch mode {
        case .track: .track
        case .context: .context
        default: .off
        }
    }
}

extension SpotifyAppRemoteClient: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        deliver { $0.onEvent?(.connected) }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let mapped = error.map { AppRemoteError($0) } ?? AppRemoteError.local(10, "Connection attempt failed")
        deliver { $0.onEvent?(.connectionFailed(mapped)) }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let mapped = error.map { AppRemoteError($0) }
        deliver { $0.onEvent?(.disconnected(mapped)) }
    }
}

extension SpotifyAppRemoteClient: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        deliver { client in
            if let state = Self.map(playerState, at: Date()) {
                client.onEvent?(.playerState(state))
            }
        }
    }
}

extension SpotifyAppRemoteClient: SPTAppRemoteConnectivityAPIDelegate {
    nonisolated func connectivityAPI(
        _ connectivityAPI: any SPTAppRemoteConnectivityAPI,
        didReceiveNewConnectivityState connectivityState: any SPTAppRemoteConnectivityState
    ) {
        let offline = connectivityState.isOffline
        deliver { $0.onEvent?(.connectivity(isOffline: offline)) }
    }
}
