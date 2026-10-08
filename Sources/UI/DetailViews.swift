import SwiftUI

struct DetailHeader: View {
    let imageURL: URL?
    var liked = false
    var circle = false
    let title: String
    let subtitle: String
    let isPlaying: Bool
    var isShuffling = false
    var onShuffle: (() -> Void)?
    var onAdd: (() -> Void)?
    var addEnabled = true
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
            HStack(spacing: 20) {
                if let onShuffle {
                    sideButton("shuffle", label: "Shuffle", isOn: isShuffling, action: onShuffle)
                }
                PlayButton(isPlaying: isPlaying, action: onPlay)
                if let onAdd {
                    sideButton("plus.circle", label: "Add to playlist", isOn: false, action: onAdd)
                        .disabled(!addEnabled)
                        .opacity(addEnabled ? 1 : 0.4)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func sideButton(_ symbol: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @Environment(AppSettings.self) private var settings
    @State private var tracks: [Track] = []
    @State private var isComplete = false
    @State private var showAdd = false

    private var canList: Bool { library.canListTracks(of: playlist) }

    private var subtitle: String {
        let owner = playlist.owner?.displayName ?? "Spotify"
        guard let count = playlist.trackCount else { return owner }
        return "\(owner) \u{2022} \(count) songs"
    }

    var body: some View {
        List {
            DetailHeader(
                imageURL: playlist.images.url(atLeast: 640),
                title: playlist.name,
                subtitle: subtitle,
                isPlaying: player.isPlaying(context: playlist.uri),
                isShuffling: player.shuffle,
                onShuffle: { Task { await player.playShuffled(context: playlist.uri) } },
                onAdd: { showAdd = true },
                addEnabled: canList && isComplete && !tracks.isEmpty
            ) {
                Task { await player.playOrPause(context: playlist.uri) }
            }
            .detailRow(top: 0)

            if canList {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button {
                        Task { await player.play(context: playlist.uri, offset: track.uri, showing: track) }
                    } label: {
                        TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                    }
                    .buttonStyle(.plain)
                    .trackActions(track)
                    .detailRow()
                }
            } else {
                Text("The track list is not available for playlists you do not own")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .detailRow(top: 14)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            AddToPlaylistSheet(
                title: playlist.name,
                imageURL: playlist.images.url(atLeast: 100),
                uris: tracks.map(\.uri),
                excludingID: playlist.id
            )
        }
        .task { await load() }
    }

    private func load() async {
        if library.isSample {
            tracks = SampleData.tracks
            isComplete = true
            return
        }
        guard canList, !isComplete else { return }
        if settings.cacheLists, let snapshot = playlist.snapshotId,
           let cached = await TrackListCache.load(key: playlist.id), cached.stamp == snapshot {
            tracks = cached.tracks
            isComplete = true
            await prefetchImages()
            return
        }
        tracks = []
        guard let result = await TrackListLoader.playlist(api: library.api, id: playlist.id, progress: { tracks = $0 }) else { return }
        isComplete = true
        if settings.cacheLists, let snapshot = playlist.snapshotId {
            await TrackListCache.save(key: playlist.id, stamp: snapshot, tracks: result)
        }
        await prefetchImages()
    }

    private func prefetchImages() async {
        guard settings.prefetchesImages else { return }
        await ImageCache.shared.prefetchArtwork(of: tracks)
    }
}

struct AlbumDetailView: View {
    let album: Album
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var tracks: [Track] = []
    @State private var showAdd = false

    private var subtitle: String {
        [album.artistLine, album.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{2022} ")
    }

    var body: some View {
        List {
            DetailHeader(
                imageURL: album.images.url(atLeast: 640),
                title: album.name,
                subtitle: subtitle,
                isPlaying: player.isPlaying(context: album.uri),
                isShuffling: player.shuffle,
                onShuffle: { Task { await player.playShuffled(context: album.uri) } },
                onAdd: { showAdd = true },
                addEnabled: !tracks.isEmpty
            ) {
                Task { await player.playOrPause(context: album.uri) }
            }
            .detailRow(top: 0)

            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                Button {
                    Task { await player.play(context: album.uri, offset: track.uri, showing: track) }
                } label: {
                    TrackRow(track: track, number: index + 1)
                }
                .buttonStyle(.plain)
                .trackActions(track)
                .detailRow()
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            AddToPlaylistSheet(
                title: album.name,
                imageURL: album.images.url(atLeast: 100),
                uris: tracks.map(\.uri)
            )
        }
        .task {
            if let embedded = album.tracks?.items, !embedded.isEmpty {
                tracks = embedded
                return
            }
            if library.isSample {
                tracks = Array(SampleData.tracks.prefix(9))
                return
            }
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
                    subtitle: "",
                    isPlaying: player.isPlaying(context: artist.uri)
                ) {
                    Task { await player.playOrPause(context: artist.uri) }
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
    static let contextKey = "liked-songs"

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @Environment(AppSettings.self) private var settings
    @State private var tracks: [Track] = []
    @State private var isComplete = false

    var body: some View {
        List {
            DetailHeader(
                imageURL: nil,
                liked: true,
                title: "Liked Songs",
                subtitle: "\(library.likedTotal) songs",
                isPlaying: player.isPlaying(context: Self.contextKey)
            ) {
                Task { await player.playOrPause(uris: tracks.map(\.uri), key: Self.contextKey) }
            }
            .detailRow(top: 0)

            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                Button {
                    Task { await player.play(uris: tracks.map(\.uri), startAt: index, key: Self.contextKey, showing: track) }
                } label: {
                    TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                }
                .buttonStyle(.plain)
                .trackActions(track)
                .detailRow()
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if library.isSample {
            tracks = SampleData.tracks
            return
        }
        guard !isComplete else { return }
        let cached = settings.cacheLists ? await TrackListCache.load(key: Self.contextKey) : nil
        if let cached, tracks.isEmpty { tracks = cached.tracks }
        guard let result = await TrackListLoader.liked(api: library.api, known: cached, progress: { tracks = $0 }) else { return }
        tracks = result.tracks
        isComplete = true
        if settings.cacheLists, !result.fromCache {
            await TrackListCache.save(key: Self.contextKey, stamp: result.stamp, tracks: result.tracks)
        }
        await prefetchImages()
    }

    private func prefetchImages() async {
        guard settings.prefetchesImages else { return }
        await ImageCache.shared.prefetchArtwork(of: tracks)
    }
}
