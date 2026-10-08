import Foundation
import Observation
import UIKit

private struct PendingPlayback {
    let body: [String: Any]?
    let pinsFirstTrack: Bool
    let date: Date
    var leftApp = false
}

@MainActor
@Observable
final class PlayerManager {
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var shuffle = false
    private(set) var repeatMode = "off"
    private(set) var deviceName: String?
    private(set) var isLiked = false
    private(set) var errorMessage: String?
    private(set) var contextURI: String?
    @ObservationIgnored private var localContextKey: String?
    @ObservationIgnored private var localContextURIs: Set<String> = []

    @ObservationIgnored private var basePositionMs: Double = 0
    @ObservationIgnored private var baseDate = Date()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let api: SpotifyAPI
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored var isSample = false
    @ObservationIgnored private var sampleQueue: [Track] = []
    @ObservationIgnored private var sampleIndex = 0
    @ObservationIgnored private var pending: PendingPlayback?
    @ObservationIgnored private var holdsShuffle = false
    @ObservationIgnored private var expected: (uri: String, until: Date)?
    @ObservationIgnored private var expectedPlaying: (value: Bool, until: Date)?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var expectedShuffle: (value: Bool, until: Date)?
    @ObservationIgnored private var expectedRepeat: (value: String, until: Date)?

    init(api: SpotifyAPI, settings: AppSettings) {
        self.api = api
        self.settings = settings
    }

    var durationMs: Double { Double(track?.durationMs ?? 0) }

    func artworkURL(atLeast width: Int) -> URL? {
        track?.album?.images.url(atLeast: width)
    }

    func positionMs(at date: Date) -> Double {
        guard isPlaying else { return min(basePositionMs, durationMs) }
        return min(basePositionMs + date.timeIntervalSince(baseDate) * 1000, durationMs)
    }

    func clearError() { errorMessage = nil }

    func isActive(context key: String) -> Bool {
        if contextURI == key { return true }
        guard localContextKey == key, let uri = track?.uri else { return false }
        return localContextURIs.contains(uri)
    }

    func isPlaying(context key: String) -> Bool {
        isPlaying && isActive(context: key)
    }

    func playOrPause(context uri: String) async {
        if isActive(context: uri) {
            await togglePlay()
        } else {
            await play(context: uri)
        }
    }

    func playOrPause(uris: [String], key: String) async {
        if isActive(context: key) {
            await togglePlay()
        } else {
            await play(uris: uris, key: key)
        }
    }

    func startPolling() {
        guard !isSample, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshState()
                let wait = self.nextWait()
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reset() {
        stopPolling()
        track = nil
        isPlaying = false
    }

    private func stepSample(_ delta: Int) {
        guard !sampleQueue.isEmpty else { return }
        sampleIndex = (sampleIndex + delta + sampleQueue.count) % sampleQueue.count
        track = sampleQueue[sampleIndex]
        basePositionMs = 0
        baseDate = Date()
    }

    func loadSample(queue: [Track], positionMs: Double, context: String?) {
        sampleQueue = queue
        let track = queue[0]
        isSample = true
        contextURI = context
        self.track = track
        isPlaying = true
        basePositionMs = positionMs
        baseDate = Date()
        deviceName = "iPhone"
    }

    func refreshState(after delay: Double = 0) async {
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        do {
            let response = try await api.send("GET", "me/player")
            if response.status == 204 {
                if !holdsExpectedTrack(nil), !holdsExpectedPlaying(false) { isPlaying = false }
                return
            }
            try response.validate()
            apply(try response.decode(PlayerStateResponse.self))
        } catch {
            return
        }
    }

    func play(context: String, offset: String? = nil, showing track: Track? = nil) async {
        var body: [String: Any] = ["context_uri": context]
        if let offset { body["offset"] = ["uri": offset] }
        localContextKey = nil
        contextURI = context
        await startPlayback(body, pinsFirstTrack: offset != nil, showing: track)
    }

    func play(uris: [String], startAt index: Int? = nil, key: String? = nil, showing track: Track? = nil) async {
        let start = index ?? 0
        guard start < uris.count else { return }
        let queue = Array(uris[start...].prefix(100))
        localContextKey = key
        localContextURIs = Set(queue)
        contextURI = nil
        await startPlayback(["uris": queue], pinsFirstTrack: index != nil && queue.count > 1, showing: track)
    }

    func togglePlay() async {
        if isSample {
            isPlaying.toggle()
            return
        }
        let target = !isPlaying
        setPlayingLocally(target)
        let previous = commandTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.sendPlayState(target)
        }
        commandTask = task
        await task.value
    }

    private func setPlayingLocally(_ value: Bool) {
        basePositionMs = positionMs(at: Date())
        baseDate = Date()
        isPlaying = value
        expectedPlaying = (value, Date().addingTimeInterval(4))
    }

    private func sendPlayState(_ target: Bool) async {
        if target {
            await startPlayback(nil)
        } else {
            errorMessage = nil
            do {
                try await api.perform("PUT", "me/player/pause")
            } catch {
                errorMessage = error.localizedDescription
            }
            await refreshState(after: 0.8)
        }
        if errorMessage != nil {
            basePositionMs = positionMs(at: Date())
            baseDate = Date()
            isPlaying = !target
            expectedPlaying = nil
        }
    }

    private func holdsExpectedPlaying(_ value: Bool) -> Bool {
        guard let expectedPlaying else { return false }
        if value == expectedPlaying.value || Date() > expectedPlaying.until {
            self.expectedPlaying = nil
            return false
        }
        return true
    }

    func next() async {
        if isSample {
            stepSample(1)
            return
        }
        await command("POST", "me/player/next")
    }

    func previous() async {
        if isSample {
            stepSample(-1)
            return
        }
        await command("POST", "me/player/previous")
    }

    func skipBack() async {
        let threshold = Double(settings.previousRestartSeconds) * 1000
        if threshold > 0, positionMs(at: Date()) > threshold {
            await seek(to: 0)
        } else {
            await previous()
        }
    }

    func seek(to ms: Double) async {
        basePositionMs = ms
        baseDate = Date()
        await command("PUT", "me/player/seek", query: ["position_ms": "\(Int(ms))"])
    }

    func toggleShuffle() async {
        let target = !shuffle
        let previous = shuffle
        shuffle = target
        expectedShuffle = (target, Date().addingTimeInterval(4))
        await enqueue { [self] in
            errorMessage = nil
            await command("PUT", "me/player/shuffle", query: ["state": target ? "true" : "false"])
            if errorMessage != nil {
                shuffle = previous
                expectedShuffle = nil
            }
        }
    }

    func cycleRepeat() async {
        let previous = repeatMode
        let target: String
        switch repeatMode {
        case "off": target = "context"
        case "context": target = "track"
        default: target = "off"
        }
        repeatMode = target
        expectedRepeat = (target, Date().addingTimeInterval(4))
        await enqueue { [self] in
            errorMessage = nil
            await command("PUT", "me/player/repeat", query: ["state": target])
            if errorMessage != nil {
                repeatMode = previous
                expectedRepeat = nil
            }
        }
    }

    private func enqueue(_ work: @escaping () async -> Void) async {
        let previous = commandTask
        let task = Task {
            await previous?.value
            await work()
        }
        commandTask = task
        await task.value
    }

    private func holdsExpectedShuffle(_ value: Bool) -> Bool {
        guard let expectedShuffle else { return false }
        if value == expectedShuffle.value || Date() > expectedShuffle.until {
            self.expectedShuffle = nil
            return false
        }
        return true
    }

    private func holdsExpectedRepeat(_ value: String) -> Bool {
        guard let expectedRepeat else { return false }
        if value == expectedRepeat.value || Date() > expectedRepeat.until {
            self.expectedRepeat = nil
            return false
        }
        return true
    }

    func syncLiked(uri: String, liked: Bool) {
        if track?.uri == uri { isLiked = liked }
    }

    func toggleLike() async {
        guard let uri = track?.uri else { return }
        let target = !isLiked
        isLiked = target
        do {
            try await api.perform(target ? "PUT" : "DELETE", "me/library", query: ["uris": uri])
        } catch {
            isLiked = !target
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ state: PlayerStateResponse) {
        guard !holdsExpectedTrack(state.item?.uri), !holdsExpectedPlaying(state.isPlaying) else { return }
        if let item = state.item, item.uri != track?.uri {
            track = item
            Task { await refreshLiked() }
        }
        isPlaying = state.isPlaying
        if let uri = state.context?.uri {
            contextURI = uri
            localContextKey = nil
        } else {
            contextURI = nil
        }
        basePositionMs = Double(state.progressMs ?? 0)
        baseDate = Date()
        let incomingShuffle = state.shuffleState ?? false
        if !holdsShuffle, !holdsExpectedShuffle(incomingShuffle) { shuffle = incomingShuffle }
        let incomingRepeat = state.repeatState ?? "off"
        if !holdsExpectedRepeat(incomingRepeat) { repeatMode = incomingRepeat }
        deviceName = state.device?.name
    }

    private func refreshLiked() async {
        guard let uri = track?.uri else { return }
        let result: [Bool]? = try? await api.get("me/library/contains", query: ["uris": uri])
        if track?.uri == uri { isLiked = result?.first ?? false }
    }

    private func nextWait() -> Double {
        guard isPlaying, durationMs > 0 else { return 6 }
        let remaining = (durationMs - positionMs(at: Date())) / 1000
        return max(1, min(4, remaining + 0.4))
    }

    private func command(_ method: String, _ path: String, query: [String: String] = [:]) async {
        if isSample { return }
        do {
            try await api.perform(method, path, query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshState(after: 0.4)
    }

    private func holdsExpectedTrack(_ uri: String?) -> Bool {
        guard let expected else { return false }
        if uri == expected.uri || Date() > expected.until {
            self.expected = nil
            return false
        }
        return true
    }

    private func show(_ next: Track) {
        track = next
        isPlaying = true
        basePositionMs = 0
        baseDate = Date()
        expected = (next.uri, Date().addingTimeInterval(6))
        expectedPlaying = nil
        Task { await refreshLiked() }
    }

    private func startPlayback(_ body: [String: Any]?, pinsFirstTrack: Bool = false, showing next: Track? = nil) async {
        errorMessage = nil
        pending = nil
        let previous = (track: track, isPlaying: isPlaying, position: positionMs(at: Date()))
        if let next {
            show(next)
        } else if !isPlaying {
            setPlayingLocally(true)
        }
        do {
            try await sendPlay(body, deviceID: settings.preferredDeviceID, pinsFirstTrack: pinsFirstTrack)
        } catch let error as APIError where error.status == 404 {
            await playOnFirstDevice(body, pinsFirstTrack: pinsFirstTrack)
        } catch {
            errorMessage = error.localizedDescription
        }
        if errorMessage != nil {
            track = previous.track
            isPlaying = previous.isPlaying
            basePositionMs = previous.position
            baseDate = Date()
            expected = nil
            expectedPlaying = nil
        }
        await refreshState(after: 0.6)
    }

    private func sendPlay(_ body: [String: Any]?, deviceID: String?, pinsFirstTrack: Bool) async throws {
        var query: [String: String] = [:]
        if let deviceID { query["device_id"] = deviceID }
        let reshuffle = pinsFirstTrack && shuffle
        if reshuffle {
            holdsShuffle = true
            try? await api.perform("PUT", "me/player/shuffle", query: query.merging(["state": "false"]) { $1 })
        }
        var failure: Error?
        do {
            try await api.perform("PUT", "me/player/play", query: query, body: body)
        } catch {
            failure = error
        }
        if reshuffle {
            try? await Task.sleep(for: .milliseconds(500))
            try? await api.perform("PUT", "me/player/shuffle", query: query.merging(["state": "true"]) { $1 })
            holdsShuffle = false
        }
        if let failure { throw failure }
    }

    private func playOnFirstDevice(_ body: [String: Any]?, pinsFirstTrack: Bool) async {
        do {
            guard let id = try await firstDeviceID() else {
                pending = PendingPlayback(body: body, pinsFirstTrack: pinsFirstTrack, date: Date())
                isPlaying = false
                expected = nil
                expectedPlaying = nil
                if await !openSpotify() {
                    pending = nil
                    errorMessage = Self.noDeviceMessage
                }
                return
            }
            try await sendPlay(body, deviceID: id, pinsFirstTrack: pinsFirstTrack)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func firstDeviceID() async throws -> String? {
        let list: DevicesResponse = try await api.get("me/player/devices")
        return (list.devices.first(where: \.isActive) ?? list.devices.first)?.id
    }

    private func openSpotify() async -> Bool {
        guard let url = URL(string: "spotify://") else { return false }
        return await UIApplication.shared.open(url)
    }

    func appDidEnterBackground() {
        pending?.leftApp = true
    }

    func resumePendingPlayback() async {
        guard let request = pending, request.leftApp else { return }
        pending = nil
        guard Date().timeIntervalSince(request.date) < 600 else { return }
        for attempt in 0..<4 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            do {
                guard let id = try await firstDeviceID() else { continue }
                try await sendPlay(request.body, deviceID: id, pinsFirstTrack: request.pinsFirstTrack)
                await refreshState(after: 0.6)
                return
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        errorMessage = Self.noDeviceMessage
    }

    private static let noDeviceMessage = "Open Spotify and play a song once"
}
