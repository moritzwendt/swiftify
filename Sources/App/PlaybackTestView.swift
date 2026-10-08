import SwiftUI

@MainActor
@Observable
final class PlaybackTester {
    private(set) var log: [String] = []
    private let api: SpotifyAPI

    init(auth: AuthManager) {
        api = SpotifyAPI(auth: auth)
    }

    func devices() async {
        await run("Devices") {
            let response = try await api.send("GET", "me/player/devices")
            guard response.isSuccess else { return "HTTP \(response.status) \(response.text)" }
            let devices = try response.decode(DevicesResponse.self).devices
            if devices.isEmpty { return "No devices found" }
            return devices.map { "\($0.isActive ? "* " : "")\($0.name) (\($0.type))" }.joined(separator: "\n")
        }
    }

    func nowPlaying() async {
        await run("Now playing") {
            let response = try await api.send("GET", "me/player")
            if response.status == 204 { return "Nothing active" }
            guard response.isSuccess else { return "HTTP \(response.status) \(response.text)" }
            let state = try response.decode(PlayerStateResponse.self)
            let track = state.item.map { "\($0.name) by \($0.artistLine)" } ?? "No track"
            return "\(state.isPlaying ? "Playing" : "Paused"): \(track) on \(state.device?.name ?? "unknown")"
        }
    }

    func playFirstPlaylist() async {
        await run("Play first playlist") {
            let playlists = try await api.send("GET", "me/playlists", query: ["limit": "1"])
            guard playlists.isSuccess, let first = try playlists.decode(PlaylistsResponse.self).items.first else {
                return "Could not load playlist HTTP \(playlists.status)"
            }
            let devices = try await api.send("GET", "me/player/devices")
            let list = (try? devices.decode(DevicesResponse.self).devices) ?? []
            guard let device = list.first(where: \.isActive) ?? list.first, let deviceID = device.id else {
                return "No device. Open Spotify on the phone and start any song once."
            }
            let play = try await api.send(
                "PUT", "me/player/play",
                query: ["device_id": deviceID],
                body: ["context_uri": first.uri]
            )
            return "\(first.name) on \(device.name): HTTP \(play.status) \(play.text)"
        }
    }

    func command(_ title: String, method: String, path: String) async {
        await run(title) {
            let response = try await api.send(method, path)
            return "HTTP \(response.status) \(response.text)"
        }
    }

    func clear() { log.removeAll() }

    private func run(_ title: String, _ work: () async throws -> String) async {
        do {
            let result = try await work()
            log.insert("\(title)\n\(result)", at: 0)
        } catch {
            log.insert("\(title)\n\(error.localizedDescription)", at: 0)
        }
    }
}

struct PlaybackTestView: View {
    @State private var tester: PlaybackTester

    init(auth: AuthManager) {
        _tester = State(initialValue: PlaybackTester(auth: auth))
    }

    var body: some View {
        VStack(spacing: 12) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    button("Devices") { await tester.devices() }
                    button("Now playing") { await tester.nowPlaying() }
                }
                GridRow {
                    button("Play playlist") { await tester.playFirstPlaylist() }
                    button("Pause") { await tester.command("Pause", method: "PUT", path: "me/player/pause") }
                }
                GridRow {
                    button("Previous") { await tester.command("Previous", method: "POST", path: "me/player/previous") }
                    button("Next") { await tester.command("Next", method: "POST", path: "me/player/next") }
                }
            }

            List {
                ForEach(Array(tester.log.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            .listStyle(.plain)
        }
        .padding()
        .navigationTitle("Playback")
        .toolbar {
            Button("Clear") { tester.clear() }
        }
    }

    private func button(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
    }
}
