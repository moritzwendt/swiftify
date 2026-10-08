import SwiftUI

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var query = ""
    @State private var results: SearchResults?

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Search Spotify", systemImage: "magnifyingglass")
                } else {
                    resultList
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "What do you want to play?")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileButton() }
            }
            .appDestinations()
            .task(id: query) { await search() }
        }
    }

    private var resultList: some View {
        List {
            if let tracks = results?.tracks?.items, !tracks.isEmpty {
                Section("Songs") {
                    ForEach(tracks) { track in
                        Button {
                            Task { await player.play(uris: [track.uri]) }
                        } label: {
                            TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                        }
                        .buttonStyle(.plain)
                        .trackActions(track)
                    }
                }
            }
            if let artists = results?.artists?.items, !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists) { artist in
                        NavigationLink(value: Route.artist(artist)) {
                            MediaRow(imageURL: artist.images.url(atLeast: 100), title: artist.name, subtitle: "Artist", circle: true)
                        }
                    }
                }
            }
            if let albums = results?.albums?.items, !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums) { album in
                        NavigationLink(value: Route.album(album)) {
                            MediaRow(imageURL: album.images.url(atLeast: 100), title: album.name, subtitle: album.artistLine)
                        }
                    }
                }
            }
            if let playlists = results?.playlists?.items, !playlists.isEmpty {
                Section("Playlists") {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: Route.playlist(playlist)) {
                            MediaRow(
                                imageURL: playlist.images.url(atLeast: 100),
                                title: playlist.name,
                                subtitle: playlist.owner?.displayName ?? ""
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled || library.isSample { return }
        results = try? await library.api.get(
            "search",
            query: ["q": trimmed, "type": "track,artist,album,playlist", "limit": "10"]
        )
    }
}
