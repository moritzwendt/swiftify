import SwiftUI

struct DetailHeader: View {
    let imageURL: URL?
    var liked = false
    var circle = false
    let title: String
    let subtitle: String
    let onPlay: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if liked {
                    LikedArtwork(cornerRadius: 12)
                } else {
                    ArtworkView(url: imageURL, cornerRadius: 12, circle: circle)
                }
            }
            .frame(width: 240, height: 240)
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            PlayButton(action: onPlay)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var tracks: [Track] = []
    @State private var offset = 0
    @State private var total = 0
    @State private var isLoading = false

    private var canList: Bool { library.canListTracks(of: playlist) }

    private var subtitle: String {
        let owner = playlist.owner?.displayName ?? "Spotify"
        guard let count = playlist.trackCount else { return owner }
        return "\(owner) \u{2022} \(count) songs"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DetailHeader(
                    imageURL: playlist.images.url(atLeast: 640),
                    title: playlist.name,
                    subtitle: subtitle
                ) {
                    Task { await player.play(context: playlist.uri) }
                }

                if canList {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        Button {
                            Task { await player.play(context: playlist.uri, offset: track.uri) }
                        } label: {
                            TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if index == tracks.count - 5 { Task { await loadMore() } }
                        }
                    }
                } else {
                    Text("The track list is not available for playlists you do not own")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMore() }
    }

    private func loadMore() async {
        guard canList, !isLoading, (offset == 0 || offset < total) else { return }
        isLoading = true
        defer { isLoading = false }
        let page: Page<PlaylistItem>? = try? await library.api.get(
            "playlists/\(playlist.id)/items",
            query: ["limit": "50", "offset": "\(offset)"]
        )
        guard let page else { return }
        total = page.total ?? 0
        offset += 50
        tracks += page.items.compactMap(\.resolved)
    }
}

struct AlbumDetailView: View {
    let album: Album
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var tracks: [Track] = []

    private var subtitle: String {
        [album.artistLine, album.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{2022} ")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DetailHeader(
                    imageURL: album.images.url(atLeast: 640),
                    title: album.name,
                    subtitle: subtitle
                ) {
                    Task { await player.play(context: album.uri) }
                }
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button {
                        Task { await player.play(context: album.uri, offset: track.uri) }
                    } label: {
                        TrackRow(track: track, number: index + 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let embedded = album.tracks?.items, !embedded.isEmpty {
                tracks = embedded
                return
            }
            if library.isSample { return }
            let full: Album? = try? await library.api.get("albums/\(album.id)")
            tracks = full?.tracks?.items ?? []
        }
    }
}

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var albums: [Album] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DetailHeader(
                    imageURL: artist.images.url(atLeast: 640),
                    circle: true,
                    title: artist.name,
                    subtitle: ""
                ) {
                    Task { await player.play(context: artist.uri) }
                }
                if !albums.isEmpty {
                    Text("Albums")
                        .font(.title3.bold())
                        .padding(.top, 8)
                }
                ForEach(albums) { album in
                    NavigationLink(value: Route.album(album)) {
                        MediaRow(
                            imageURL: album.images.url(atLeast: 100),
                            title: album.name,
                            subtitle: [album.year, album.albumType?.capitalized]
                                .compactMap { $0 }
                                .joined(separator: " \u{2022} ")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if library.isSample { return }
        var result: [Album] = []
        for offset in stride(from: 0, to: 50, by: 10) {
            let page: Page<Album>? = try? await library.api.get(
                "artists/\(artist.id)/albums",
                query: ["include_groups": "album,single", "limit": "10", "offset": "\(offset)"]
            )
            guard let page else { break }
            result += page.items
            if page.next == nil { break }
        }
        albums = result
    }
}

struct LikedSongsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var tracks: [Track] = []
    @State private var offset = 0
    @State private var total = 0
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DetailHeader(
                    imageURL: nil,
                    liked: true,
                    title: "Liked Songs",
                    subtitle: "\(library.likedTotal) songs"
                ) {
                    Task { await player.play(uris: tracks.map(\.uri)) }
                }
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button {
                        Task { await player.play(uris: tracks.map(\.uri), startAt: index) }
                    } label: {
                        TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if index == tracks.count - 5 { Task { await loadMore() } }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMore() }
    }

    private func loadMore() async {
        if library.isSample { return }
        guard !isLoading, (offset == 0 || offset < total) else { return }
        isLoading = true
        defer { isLoading = false }
        let page: Page<SavedTrack>? = try? await library.api.get(
            "me/tracks",
            query: ["limit": "50", "offset": "\(offset)"]
        )
        guard let page else { return }
        total = page.total ?? 0
        offset += 50
        tracks += page.items.map(\.track)
    }
}
