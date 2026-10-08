import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppRemoteConnection {
    enum Status: Equatable {
        case off
        case connecting
        case connected
        case failed(String)
        case spotifyNotInstalled
    }

    enum TokenSource: String, CaseIterable, Identifiable {
        case login
        case spotify

        var id: String { rawValue }
    }

    enum Command: Equatable {
        case play(String)
        case pause
        case resume
        case next
        case previous

        var name: String {
            switch self {
            case .play: "play"
            case .pause: "pause"
            case .resume: "resume"
            case .next: "next"
            case .previous: "previous"
            }
        }
    }

    struct Counters: Codable, Equatable {
        var wakes = 0
        var redirects = 0
        var connectAttempts = 0
        var connectFailures = 0
        var connects = 0
        var dropsWhilePlaying = 0
        var pausedDrops: [Double] = []
    }

    private(set) var status: Status = .off
    private(set) var isWaking = false
    private(set) var lastError: AppRemoteError?
    private(set) var playerState: RemotePlayerState?
    private(set) var spotifyIsOffline: Bool?
    private(set) var hasSpotifyToken = false
    private(set) var counters: Counters {
        didSet { saveCounters() }
    }
    var tokenSource: TokenSource = .login
    var autoConnect: Bool {
        didSet { defaults.set(autoConnect, forKey: Self.autoConnectKey) }
    }
    let diagnostics: DiagnosticsLog

    @ObservationIgnored private let client: AppRemoteClient
    @ObservationIgnored private let tokenProvider: () async throws -> String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let wakeRetryDelays: [Duration]
    @ObservationIgnored private let postReturnDelay: Duration
    @ObservationIgnored private let connectTimeout: Duration
    @ObservationIgnored private let returnTimeout: Duration
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var spotifyToken: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var attempt: Task<Bool, Never>?
    @ObservationIgnored private var connectWaiter: CheckedContinuation<Result<Void, AppRemoteError>, Never>?
    @ObservationIgnored private var connectTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var returnWaiter: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var returnTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var returnSeen = false
    @ObservationIgnored private var leftForeground = false
    @ObservationIgnored private var pausedSince: Date?

    private static let autoConnectKey = "remote.autoConnect"
    private static let countersKey = "remote.counters"

    init(
        client: AppRemoteClient,
        tokenProvider: @escaping () async throws -> String,
        diagnostics: DiagnosticsLog,
        defaults: UserDefaults = .standard,
        wakeRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(3)],
        postReturnDelay: Duration = .milliseconds(600),
        connectTimeout: Duration = .seconds(10),
        returnTimeout: Duration = .seconds(25),
        sleep: @escaping @MainActor (Duration) async -> Void = AppRemoteConnection.defaultSleep,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.diagnostics = diagnostics
        self.defaults = defaults
        self.wakeRetryDelays = wakeRetryDelays
        self.postReturnDelay = postReturnDelay
        self.connectTimeout = connectTimeout
        self.returnTimeout = returnTimeout
        self.sleep = sleep
        self.now = now
        counters = Self.loadCounters(defaults)
        autoConnect = defaults.object(forKey: Self.autoConnectKey) as? Bool ?? false
        client.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    nonisolated static func defaultSleep(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    var isSpotifyInstalled: Bool { client.isSpotifyInstalled }

    var isConnected: Bool { status == .connected }

    var statusText: String {
        switch status {
        case .off: "Off"
        case .connecting: isWaking ? "Waking Spotify" : "Connecting"
        case .connected: "Connected"
        case .failed(let reason): "Failed: \(reason)"
        case .spotifyNotInstalled: "Spotify not installed"
        }
    }

    @discardableResult
    func connect(retrying delays: [Duration] = []) async -> Bool {
        if status == .connected, client.isConnected { return true }
        if let attempt { return await attempt.value }
        let task = Task { await runConnect(delays) }
        attempt = task
        let result = await task.value
        if attempt == task { attempt = nil }
        return result
    }

    func disconnect() {
        generation += 1
        attempt?.cancel()
        attempt = nil
        resolveConnectWaiter(.failure(.cancelled))
        signalReturn()
        isWaking = false
        if status != .off {
            diagnostics.add("disconnect")
        }
        client.disconnect()
        status = .off
        playerState = nil
        spotifyIsOffline = nil
        pausedSince = nil
    }

    func wake(playing uri: String = "") async {
        guard !isWaking else { return }
        let run = generation
        isWaking = true
        returnSeen = false
        leftForeground = false
        counters.wakes += 1
        status = .connecting
        let started = now()
        diagnostics.add("wake: authorize and play \(uri.isEmpty ? "last played" : uri)")
        defer {
            if run == generation { isWaking = false }
        }
        let outcome: AppRemoteAuthorizeOutcome
        do {
            outcome = try await client.authorizeAndPlay(uri: uri)
        } catch {
            guard run == generation else { return }
            fail(AppRemoteError(error))
            return
        }
        guard run == generation else { return }
        guard outcome == .started else {
            status = .spotifyNotInstalled
            diagnostics.add("wake: Spotify not installed")
            return
        }
        diagnostics.add("wake: app switch requested")
        await waitForReturn()
        guard run == generation else { return }
        diagnostics.add("wake: back after \(Self.seconds(now().timeIntervalSince(started))) s")
        await sleep(postReturnDelay)
        guard run == generation else { return }
        await connect(retrying: wakeRetryDelays)
    }

    @discardableResult
    func send(_ command: Command) async -> Bool {
        guard client.isConnected else {
            diagnostics.add("\(command.name) skipped: not connected")
            return false
        }
        let started = now()
        do {
            switch command {
            case .play(let uri): try await client.play(uri: uri)
            case .pause: try await client.pause()
            case .resume: try await client.resume()
            case .next: try await client.skipToNext()
            case .previous: try await client.skipToPrevious()
            }
            let milliseconds = Int(now().timeIntervalSince(started) * 1000)
            diagnostics.add("\(command.name) ok after \(milliseconds) ms")
            return true
        } catch {
            let mapped = AppRemoteError(error)
            lastError = mapped
            diagnostics.add("\(command.name) failed \(mapped.summary)")
            return false
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        diagnostics.add("scene \(Self.name(of: phase))")
        switch phase {
        case .active:
            if isWaking {
                if leftForeground { signalReturn() }
            } else if autoConnect {
                Task { await connect() }
            }
        case .inactive, .background:
            if isWaking {
                leftForeground = true
            } else if status == .connected || status == .connecting {
                disconnect()
            }
        @unknown default:
            break
        }
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard let authorization = client.authorization(from: url) else { return false }
        counters.redirects += 1
        let parameters = Self.parameterSummary(in: url)
        if let token = authorization.accessToken, !token.isEmpty {
            spotifyToken = token
            hasSpotifyToken = true
            diagnostics.add("redirect with token: \(parameters)")
        } else if authorization.errorCode != nil || authorization.errorDescription != nil {
            diagnostics.add("redirect with error \(authorization.errorCode ?? "") \(authorization.errorDescription ?? ""): \(parameters)")
        } else {
            diagnostics.add("redirect without token: \(parameters)")
        }
        if isWaking { signalReturn() }
        return true
    }

    func reset() {
        disconnect()
        spotifyToken = nil
        hasSpotifyToken = false
        lastError = nil
        counters = Counters()
        diagnostics.clear()
    }

    func report() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let drops = counters.pausedDrops.map { String(format: "%.0f", $0) }.joined(separator: " ")
        let lines = [
            "Swiftify \(version) (\(build))",
            "iOS \(UIDevice.current.systemVersion), \(Self.machine)",
            "Spotify installed: \(isSpotifyInstalled ? "yes" : "no")",
            "Status: \(statusText)",
            "Wakes \(counters.wakes), redirects \(counters.redirects), connects \(counters.connects), "
                + "attempts \(counters.connectAttempts), failures \(counters.connectFailures)",
            "Drops while playing \(counters.dropsWhilePlaying), seconds paused before drop: \(drops.isEmpty ? "none" : drops)",
            "",
            diagnostics.export()
        ]
        return lines.joined(separator: "\n")
    }

    private func runConnect(_ delays: [Duration]) async -> Bool {
        let run = generation
        status = .connecting
        var pending = delays[...]
        var number = 1
        while true {
            let token: String
            do {
                token = try await currentToken()
            } catch {
                guard run == generation else { return false }
                fail(.local(5, error.localizedDescription))
                return false
            }
            guard run == generation else { return false }
            client.setAccessToken(token)
            counters.connectAttempts += 1
            diagnostics.add("connect attempt \(number)")
            let outcome = await performConnect()
            guard run == generation else { return false }
            switch outcome {
            case .success:
                return true
            case .failure(let error):
                counters.connectFailures += 1
                lastError = error
                diagnostics.add("connect failed\n\(error.chainText)")
                guard let delay = pending.popFirst() else {
                    fail(error)
                    return false
                }
                diagnostics.add("retry in \(Self.seconds(delay)) s")
                await sleep(delay)
                guard run == generation else { return false }
                number += 1
            }
        }
    }

    private func performConnect() async -> Result<Void, AppRemoteError> {
        await withCheckedContinuation { continuation in
            connectWaiter = continuation
            let timeout = connectTimeout
            let sleeper = sleep
            connectTimeoutTask = Task {
                await sleeper(timeout)
                guard !Task.isCancelled else { return }
                self.resolveConnectWaiter(.failure(.timedOut))
            }
            client.connect()
        }
    }

    private func resolveConnectWaiter(_ result: Result<Void, AppRemoteError>) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        guard let waiter = connectWaiter else { return }
        connectWaiter = nil
        waiter.resume(returning: result)
    }

    private func waitForReturn() async {
        if returnSeen { return }
        await withCheckedContinuation { continuation in
            returnWaiter = continuation
            let timeout = returnTimeout
            let sleeper = sleep
            returnTimeoutTask = Task {
                await sleeper(timeout)
                guard !Task.isCancelled else { return }
                self.diagnostics.add("wake: no return from Spotify after \(Self.seconds(timeout)) s")
                self.signalReturn()
            }
        }
    }

    private func signalReturn() {
        returnSeen = true
        returnTimeoutTask?.cancel()
        returnTimeoutTask = nil
        guard let waiter = returnWaiter else { return }
        returnWaiter = nil
        waiter.resume()
    }

    private func currentToken() async throws -> String {
        if tokenSource == .spotify {
            if let spotifyToken {
                diagnostics.add("token: Spotify issued, length \(spotifyToken.count)")
                return spotifyToken
            }
            diagnostics.add("token: no Spotify issued token yet")
        }
        let token = try await tokenProvider()
        diagnostics.add("token: Swiftify login, length \(token.count)")
        return token
    }

    private func fail(_ error: AppRemoteError) {
        lastError = error
        status = .failed(error.reason)
        diagnostics.add("failed: \(error.reason)")
    }

    private func handle(_ event: AppRemoteClientEvent) {
        switch event {
        case .connected:
            status = .connected
            lastError = nil
            counters.connects += 1
            diagnostics.add("connected")
            resolveConnectWaiter(.success(()))
            Task { await subscribe() }
        case .connectionFailed(let error):
            diagnostics.add("connection failed: \(error.summary)")
            if connectWaiter == nil {
                lastError = error
                status = .failed(error.reason)
            }
            resolveConnectWaiter(.failure(error))
        case .disconnected(let error):
            guard let error else {
                diagnostics.add("disconnected (requested)")
                return
            }
            handleDrop(error)
        case .playerState(let state):
            apply(state)
        case .connectivity(let isOffline):
            spotifyIsOffline = isOffline
            diagnostics.add("Spotify is \(isOffline ? "offline" : "online")")
        }
    }

    private func handleDrop(_ error: AppRemoteError) {
        var line = "disconnected: \(error.summary)"
        if status == .connected {
            if let pausedSince {
                let seconds = now().timeIntervalSince(pausedSince)
                counters.pausedDrops.append(seconds)
                line += ", paused for \(Self.seconds(seconds)) s"
            } else if playerState?.isPaused == false {
                counters.dropsWhilePlaying += 1
                line += ", while playing"
            }
        }
        diagnostics.add(line)
        lastError = error
        playerState = nil
        spotifyIsOffline = nil
        pausedSince = nil
        if connectWaiter == nil {
            status = .failed(error.reason)
        }
        resolveConnectWaiter(.failure(error))
    }

    private func subscribe() async {
        do {
            if let state = try await client.subscribeToPlayerState() {
                apply(state)
            }
        } catch {
            diagnostics.add("player subscription failed: \(AppRemoteError(error).summary)")
        }
        do {
            try await client.subscribeToConnectivity()
        } catch {
            diagnostics.add("connectivity subscription failed: \(AppRemoteError(error).summary)")
        }
    }

    private func apply(_ state: RemotePlayerState) {
        guard status == .connected else { return }
        playerState = state
        if state.isPaused {
            if pausedSince == nil { pausedSince = now() }
        } else {
            pausedSince = nil
        }
        let track = state.track
        let position = Self.seconds(state.positionMs(at: state.receivedAt) / 1000)
        diagnostics.add(
            "state \(state.isPaused ? "paused" : "playing") \(track.name) by \(track.artistName) at \(position) s, "
                + "context \(state.contextURI ?? "none"), shuffle \(state.isShuffling ? "on" : "off"), "
                + "repeat \(Self.name(of: state.repeatMode)), image \(track.imageIdentifier)"
        )
    }

    private func saveCounters() {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        defaults.set(data, forKey: Self.countersKey)
    }

    private static func loadCounters(_ defaults: UserDefaults) -> Counters {
        guard let data = defaults.data(forKey: countersKey),
              let counters = try? JSONDecoder().decode(Counters.self, from: data) else { return Counters() }
        return counters
    }

    private static func name(of phase: ScenePhase) -> String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    private static func name(of mode: RemoteRepeatMode) -> String {
        switch mode {
        case .off: "off"
        case .track: "track"
        case .context: "context"
        }
    }

    private static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        return seconds(Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000)
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func parameterSummary(in url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "unreadable" }
        var items = components.queryItems ?? []
        if let fragment = components.fragment {
            var fragmentComponents = URLComponents()
            fragmentComponents.query = fragment
            items += fragmentComponents.queryItems ?? []
        }
        if items.isEmpty { return "none" }
        let hidden: Set<String> = ["access_token", "refresh_token", "code"]
        return items.map { item in
            let value = item.value ?? ""
            return hidden.contains(item.name) ? "\(item.name)(length \(value.count))" : "\(item.name)=\(value)"
        }
        .joined(separator: " ")
    }

    private static var machine: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }
}
