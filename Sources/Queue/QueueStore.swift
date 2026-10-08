import Foundation
import Observation

@MainActor
@Observable
final class QueueStore {
    private(set) var current: Track?
    private(set) var upcoming: [Track] = []
    private(set) var queuedCount = 0
    private(set) var hasLoaded = false
    private(set) var loadFailed = false
    private(set) var message: String?
    private(set) var addedCount = 0

    @ObservationIgnored private let api: SpotifyAPI
    @ObservationIgnored private var added: [String] = []
    @ObservationIgnored private var latestRefresh = 0
    @ObservationIgnored var isSample = false

    init(api: SpotifyAPI) {
        self.api = api
    }

    func refresh() async {
        if isSample { return }
        latestRefresh += 1
        let id = latestRefresh
        do {
            let response = try await api.send("GET", "me/player/queue")
            guard id == latestRefresh else { return }
            if response.status == 204 || response.status == 404 {
                apply(current: nil, upcoming: [])
            } else {
                try response.validate()
                let decoded = try response.decode(QueueResponse.self)
                apply(current: decoded.currentlyPlaying, upcoming: decoded.queue)
            }
            loadFailed = false
        } catch {
            guard id == latestRefresh else { return }
            loadFailed = true
        }
        hasLoaded = true
    }

    func add(_ track: Track) async {
        if isSample {
            upcoming.insert(track, at: min(queuedCount, upcoming.count))
            queuedCount += 1
            confirm()
            return
        }
        await add(uri: track.uri)
    }

    func add(uri: String) async {
        if isSample {
            confirm()
            return
        }
        do {
            try await api.perform("POST", "me/player/queue", query: ["uri": uri])
            added.append(uri)
            confirm()
        } catch {
            message = error.localizedDescription
        }
    }

    func clearMessage() {
        message = nil
    }

    func reset() {
        current = nil
        upcoming = []
        queuedCount = 0
        hasLoaded = false
        loadFailed = false
        message = nil
        added = []
    }

    func loadSample(upcoming: [Track]) {
        isSample = true
        self.upcoming = upcoming
        hasLoaded = true
    }

    nonisolated static func reconcile(
        added: [String],
        currentURI: String?,
        upcomingURIs: [String]
    ) -> (added: [String], count: Int) {
        var pending = added
        if let currentURI, pending.first == currentURI {
            pending.removeFirst()
        }
        var matched = 0
        while matched < pending.count, matched < upcomingURIs.count, pending[matched] == upcomingURIs[matched] {
            matched += 1
        }
        if matched < pending.count, matched < upcomingURIs.count {
            pending = Array(pending.prefix(matched))
        }
        return (pending, matched)
    }

    private func apply(current: Track?, upcoming: [Track]) {
        let result = Self.reconcile(added: added, currentURI: current?.uri, upcomingURIs: upcoming.map(\.uri))
        added = result.added
        queuedCount = result.count
        self.current = current
        self.upcoming = upcoming
    }

    private func confirm() {
        addedCount += 1
        message = "Added to queue"
    }
}
