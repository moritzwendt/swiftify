import Foundation

struct AppRemoteError: Error, Equatable {
    struct Layer: Equatable {
        let domain: String
        let code: Int
        let text: String
    }

    static let localDomain = "swiftify.remote"
    static let spotifyDomain = "com.spotify.app-remote"
    static let transportDomain = "com.spotify.app-remote.transport"

    let layers: [Layer]

    init(layers: [Layer]) {
        self.layers = layers.isEmpty ? [Layer(domain: Self.localDomain, code: 0, text: "Unknown error")] : layers
    }

    init(_ error: Error) {
        if let error = error as? AppRemoteError {
            self = error
            return
        }
        var collected: [Layer] = []
        var current: NSError? = error as NSError
        while let item = current, collected.count < 6 {
            collected.append(Layer(domain: item.domain, code: item.code, text: item.localizedDescription))
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self.init(layers: collected)
    }

    static func local(_ code: Int, _ text: String) -> AppRemoteError {
        AppRemoteError(layers: [Layer(domain: localDomain, code: code, text: text)])
    }

    static let notConnected = local(1, "Not connected")
    static let timedOut = local(2, "Timed out")
    static let cancelled = local(3, "Cancelled")

    var primary: Layer { layers[0] }

    var isLocal: Bool { primary.domain == Self.localDomain }

    var isTimedOut: Bool { isLocal && primary.code == 2 }

    var isCancelled: Bool { isLocal && primary.code == 3 }

    var isSpotifyUnreachable: Bool {
        layers.contains { $0.domain == NSPOSIXErrorDomain && $0.code == 61 }
    }

    var isConnectionTerminated: Bool {
        layers.contains {
            ($0.domain == Self.spotifyDomain && $0.code == -1002)
                || ($0.domain == Self.transportDomain && $0.code == -2001)
        }
    }

    var reason: String {
        if isSpotifyUnreachable { return "Spotify not running" }
        if isConnectionTerminated { return "Connection ended" }
        if isTimedOut { return "Timed out" }
        return primary.text
    }

    var summary: String { "\(primary.domain) \(primary.code) \(primary.text)" }

    var chainText: String {
        layers.enumerated().map { index, layer in
            String(repeating: "  ", count: index) + "\(layer.domain) \(layer.code) \(layer.text)"
        }
        .joined(separator: "\n")
    }
}
