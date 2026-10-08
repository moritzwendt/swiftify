import SwiftUI
import UIKit

struct SDKDiagnosticsView: View {
    @Environment(AppRemoteConnection.self) private var connection
    @Environment(LibraryStore.self) private var library
    @State private var uriText = ""
    @State private var copied = false

    private var resolvedURI: String? {
        let trimmed = uriText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("spotify:") { return trimmed }
        return SpotifyLink.parse(trimmed)?.uri
    }

    private var statusColor: Color {
        switch connection.status {
        case .connected: .green
        case .failed: .red
        case .spotifyNotInstalled: .orange
        default: .secondary
        }
    }

    var body: some View {
        List {
            connectionSection
            actionsSection
            linkSection
            commandsSection
            playerSection
            countersSection
            logSection
        }
        .navigationTitle("SDK diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Copy report") {
                        UIPasteboard.general.string = connection.report()
                        copied = true
                    }
                    Button("Clear log", role: .destructive) {
                        connection.diagnostics.clear()
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "ellipsis.circle")
                }
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent("Status") {
                Text(connection.statusText)
                    .foregroundStyle(statusColor)
            }
            LabeledContent("Spotify installed", value: connection.isSpotifyInstalled ? "Yes" : "No")
            if let offline = connection.spotifyIsOffline {
                LabeledContent("Spotify offline", value: offline ? "Yes" : "No")
            }
            Picker("Token", selection: Bindable(connection).tokenSource) {
                Text("Swiftify login").tag(AppRemoteConnection.TokenSource.login)
                Text(connection.hasSpotifyToken ? "Spotify issued" : "Spotify issued (none yet)")
                    .tag(AppRemoteConnection.TokenSource.spotify)
            }
            Toggle("Auto connect", isOn: Bindable(connection).autoConnect)
            if let error = connection.lastError {
                Text(error.chainText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button("Connect") {
                Task { await connection.connect() }
            }
            Button("Disconnect") {
                connection.disconnect()
            }
            Button("Wake and resume") {
                Task { await connection.wake() }
            }
        }
    }

    private var linkSection: some View {
        Section("Link") {
            TextField("URI or link", text: $uriText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
            Button("Paste") {
                uriText = UIPasteboard.general.string ?? uriText
            }
            Menu("Fill") {
                if let uri = library.playlists.first?.uri {
                    Button("First playlist") { uriText = uri }
                }
                if let id = library.me?.id {
                    Button("Liked Songs collection") { uriText = "spotify:user:\(id):collection" }
                }
            }
            Button("Play link") {
                guard let uri = resolvedURI else { return }
                Task { await connection.send(.play(uri)) }
            }
            .disabled(resolvedURI == nil || !connection.isConnected)
            Button("Wake and play link") {
                guard let uri = resolvedURI else { return }
                Task { await connection.wake(playing: uri) }
            }
            .disabled(resolvedURI == nil)
        }
    }

    private var commandsSection: some View {
        Section("Commands") {
            Button("Pause") { Task { await connection.send(.pause) } }
            Button("Resume") { Task { await connection.send(.resume) } }
            Button("Previous") { Task { await connection.send(.previous) } }
            Button("Next") { Task { await connection.send(.next) } }
        }
        .disabled(!connection.isConnected)
    }

    @ViewBuilder
    private var playerSection: some View {
        if let state = connection.playerState {
            Section("Player") {
                row("Track", state.track.name)
                row("Artist", state.track.artistName)
                row("Album", state.track.albumName)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    row(
                        "Position",
                        "\(Self.clock(state.positionMs(at: context.date))) of \(Self.clock(Double(state.track.durationMs)))"
                    )
                }
                row("State", state.isPaused ? "Paused" : "Playing")
                row("Shuffle", state.isShuffling ? "On" : "Off")
                row("Repeat", Self.repeatName(state.repeatMode))
                row("Context", state.contextURI ?? "None")
                row("Context title", state.contextTitle ?? "None")
                row("Track URI", state.track.uri)
                row("Image", state.track.imageIdentifier)
                row("Saved", state.track.isSaved ? "Yes" : "No")
                row("Speed", String(format: "%.2f", state.playbackSpeed))
                row("Can skip", "\(state.canSkipPrevious ? "previous" : "none") \(state.canSkipNext ? "next" : "none")")
                row("Can seek", state.canSeek ? "Yes" : "No")
            }
        }
    }

    private var countersSection: some View {
        let counters = connection.counters
        let drops = counters.pausedDrops.map { String(format: "%.0f s", $0) }.joined(separator: ", ")
        return Section("Counters") {
            row("Wakes", "\(counters.wakes)")
            row("Redirects", "\(counters.redirects)")
            row("Connects", "\(counters.connects)")
            row("Connect attempts", "\(counters.connectAttempts)")
            row("Connect failures", "\(counters.connectFailures)")
            row("Drops while playing", "\(counters.dropsWhilePlaying)")
            row("Drops after pause", drops.isEmpty ? "None" : drops)
        }
    }

    private var logSection: some View {
        Section("Log") {
            ForEach(connection.diagnostics.entries.reversed()) { entry in
                Text("\(DiagnosticsLog.stamp(entry.date)) \(entry.text)")
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private static func clock(_ milliseconds: Double) -> String {
        let total = max(0, Int(milliseconds / 1000))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func repeatName(_ mode: RemoteRepeatMode) -> String {
        switch mode {
        case .off: "Off"
        case .track: "Track"
        case .context: "Context"
        }
    }
}
