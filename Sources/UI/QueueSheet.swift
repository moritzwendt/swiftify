import SwiftUI

struct QueueSheet: View {
    @Environment(PlayerManager.self) private var player
    @Environment(QueueStore.self) private var queue
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    private var nowPlaying: Track? { queue.current ?? player.track }

    private var queued: [Track] { Array(queue.upcoming.prefix(queue.queuedCount)) }

    private var following: [Track] { Array(queue.upcoming.dropFirst(queue.queuedCount)) }

    private var followingTitle: String {
        guard let name = contextName else { return "Next up" }
        return "Next from \(name)"
    }

    private var contextName: String? {
        if player.isActive(context: LikedSongsView.contextKey) { return "Liked Songs" }
        guard let uri = player.contextURI else { return nil }
        if let playlist = library.playlists.first(where: { $0.uri == uri }) { return playlist.name }
        if let album = library.albums.first(where: { $0.album.uri == uri }) { return album.album.name }
        if let artist = library.artists.first(where: { $0.uri == uri }) { return artist.name }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                if let track = nowPlaying {
                    Section("Now playing") {
                        row(track)
                    }
                }
                if !queued.isEmpty {
                    Section("Next in queue") {
                        ForEach(Array(queued.enumerated()), id: \.offset) { _, track in
                            row(track)
                        }
                    }
                }
                if !following.isEmpty {
                    Section(followingTitle) {
                        ForEach(Array(following.enumerated()), id: \.offset) { _, track in
                            row(track)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if nowPlaying == nil && queue.upcoming.isEmpty {
                    if queue.loadFailed {
                        ContentUnavailableView("Could not load the queue", systemImage: "wifi.exclamationmark")
                    } else if queue.hasLoaded {
                        ContentUnavailableView("Nothing is playing", systemImage: "list.bullet")
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
                }
            }
            .refreshable { await queue.refresh() }
            .task(id: player.track?.uri) { await queue.refresh() }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ track: Track) -> some View {
        TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
            .listRowSeparator(.hidden)
    }
}
