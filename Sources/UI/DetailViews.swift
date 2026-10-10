import SwiftUI

struct HeaderAction {
    let symbol: String
    let label: String
    var isOn = false
    var isEnabled = true
    let action: () -> Void
}

struct DetailHeader: View {
    let imageURL: URL?
    var liked = false
    var circle = false
    let title: String
    let subtitle: String
    let isPlaying: Bool
    var leading: HeaderAction?
    var trailing: HeaderAction?
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
                if let leading {
                    sideButton(leading)
                } else if trailing != nil {
                    Color.clear.frame(width: 44, height: 44)
                }
                PlayButton(isPlaying: isPlaying, action: onPlay)
                if let trailing {
                    sideButton(trailing)
                } else if leading != nil {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func sideButton(_ item: HeaderAction) -> some View {
        Button(action: item.action) {
            Image(systemName: item.symbol)
                .font(.system(size: 26))
                .foregroundStyle(item.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.4)
        .accessibilityLabel(item.label)
    }
}

private struct TrackSearch: ViewModifier {
    @Binding var text: String
    @Binding var isActive: Bool
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(
                text: $text,
                isPresented: $isActive,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Find in playlist"
            )
        } else {
            content
        }
    }
}

private extension View {
    func trackSearch(text: Binding<String>, isActive: Binding<Bool>, enabled: Bool = true) -> some View {
        modifier(TrackSearch(text: text, isActive: isActive, enabled: enabled))
    }
}

private struct SearchButton: View {
    @Binding var isActive: Bool

    var body: some View {
        Button {
            isActive = true
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Find in playlist")
    }
}

private func indexedTracks(_ tracks: [Track], matching query: String) -> [(offset: Int, element: Track)] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    let all = Array(tracks.enumerated())
    guard !needle.isEmpty else { return all }
    return all.filter { $0.element.matches(needle) }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Track] = []
    @State private var isComplete = false
    @State private var showMenu = false
    @State private var pendingDestination: MenuDestination?
    @State private var destination: MenuDestination?
    @State private var editMode: EditMode = .inactive
    @State private var serial = SerialTasks()
    @State private var query = ""
    @State private var isSearching = false
    @State private var saves: Int?

    private var live: Playlist { library.playlists.first { $0.id == playlist.id } ?? playlist }
    private var canList: Bool { library.canListTracks(of: live) }
    private var isOwned: Bool { library.me != nil && live.owner?.id == library.me?.id }
    private var isEditing: Bool { editMode == .active }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var visibleTracks: [(offset: Int, element: Track)] { indexedTracks(tracks, matching: query) }

    private var trailingAction: HeaderAction {
        if isOwned {
            let pinned = library.isPinned(live.uri)
            return HeaderAction(symbol: pinned ? "pin.fill" : "pin", label: pinned ? "Unpin" : "Pin", isOn: pinned) {
                withAnimation(.snappy) { library.togglePin(live.uri) }
            }
        }
        let saved = library.isSaved(live)
        return HeaderAction(
            symbol: saved ? "checkmark.circle.fill" : "plus.circle",
            label: saved ? "Remove from library" : "Save to library",
            isOn: saved
        ) {
            Task { await library.setSaved(live, saved: !saved) }
        }
    }

    private var subtitle: String {
        var parts = [live.owner?.displayName ?? "Spotify"]
        if let count = live.trackCount { parts.append("\(count) songs") }
        if let saves, saves > 0 { parts.append(Playlist.savesLabel(saves)) }
        return parts.joined(separator: " \u{2022} ")
    }

    var body: some View {
        List {
            if !isSearching {
                DetailHeader(
                    imageURL: live.images.url(atLeast: 640),
                    title: live.name,
                    subtitle: subtitle,
                    isPlaying: player.isPlaying(context: live.uri),
                    leading: HeaderAction(symbol: "shuffle", label: "Shuffle", isOn: player.shuffle) {
                        Task { await player.toggleShuffle() }
                    },
                    trailing: trailingAction
                ) {
                    Task { await player.playOrPause(context: live.uri) }
                }
                .detailRow(top: 0)
            }

            if canList {
                ForEach(visibleTracks, id: \.offset) { index, track in
                    Button {
                        guard !isEditing else { return }
                        Task { await player.play(context: live.uri, offset: track.uri, showing: track) }
                    } label: {
                        TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                    }
                    .buttonStyle(.plain)
                    .trackActions(track)
                    .detailRow()
                    .moveDisabled(!isEditing || isSearching)
                    .deleteDisabled(!isEditing || isSearching)
                }
                .onMove(perform: move)
                .onDelete(perform: remove)

                if hasQuery && visibleTracks.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .detailRow(top: 24)
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
        .environment(\.editMode, $editMode)
        .navigationBarTitleDisplayMode(.inline)
        .trackSearch(text: $query, isActive: $isSearching, enabled: canList && isSearching)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button("Done") { editMode = .inactive }
                } else {
                    if canList {
                        SearchButton(isActive: $isSearching)
                    }
                    Button {
                        showMenu = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $showMenu, onDismiss: {
            destination = pendingDestination
            pendingDestination = nil
        }) {
            PlaylistMenuSheet(
                playlist: live,
                tracks: tracks,
                isOwned: isOwned,
                canEdit: canList && (isOwned || live.collaborative == true),
                isReady: isComplete,
                saves: saves,
                onSelect: { pendingDestination = $0 },
                onEdit: { editMode = .active },
                onDeleted: { dismiss() }
            )
        }
        .sheet(item: $destination) { destination in
            MenuDestinationSheet(
                destination: destination,
                playlist: live,
                tracks: tracks,
                onAdded: { track, snapshot in
                    tracks.append(track)
                    persist(snapshot: snapshot)
                }
            )
        }
        .task { await load() }
        .task { await loadSaves() }
    }

    private func loadSaves() async {
        if library.isSample { return }
        let box: FollowersBox? = try? await library.api.get("playlists/\(playlist.id)", query: ["fields": "followers(total)"])
        saves = box?.followers?.total
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard !isSearching, let from = source.first else { return }
        let previous = tracks
        tracks.move(fromOffsets: source, toOffset: destination)
        let id = live.id
        serial.run {
            if library.isSample { return }
            do {
                let response: SnapshotResponse = try await library.api.request(
                    "PUT",
                    "playlists/\(id)/items",
                    body: ["range_start": from, "insert_before": destination, "range_length": 1]
                )
                persist(snapshot: response.snapshotId)
            } catch {
                tracks = previous
                library.report(error.localizedDescription)
            }
        }
    }

    private func remove(at offsets: IndexSet) {
        guard !isSearching else { return }
        let uris = Set(offsets.map { tracks[$0].uri })
        let previous = tracks
        tracks.removeAll { uris.contains($0.uri) }
        let id = live.id
        serial.run {
            if library.isSample { return }
            do {
                let response: SnapshotResponse = try await library.api.request(
                    "DELETE",
                    "playlists/\(id)/items",
                    body: ["items": uris.map { ["uri": $0] }]
                )
                library.membership.recordRemoval(playlistID: id, uris: Array(uris), snapshot: response.snapshotId)
                persist(snapshot: response.snapshotId)
            } catch {
                tracks = previous
                library.report(error.localizedDescription)
            }
        }
    }

    private func persist(snapshot: String?) {
        guard let snapshot else { return }
        library.updateSnapshot(playlistID: live.id, snapshot: snapshot)
        guard settings.cacheLists else { return }
        let key = live.id
        let current = tracks
        Task { await TrackListCache.save(key: key, stamp: snapshot, tracks: current) }
    }

    private func load() async {
        if library.isSample {
            tracks = SampleData.tracks
            isComplete = true
            return
        }
        guard canList, !isComplete else { return }
        if settings.cacheLists, let snapshot = live.snapshotId,
           let cached = await TrackListCache.load(key: live.id), cached.stamp == snapshot {
            tracks = cached.tracks
            isComplete = true
            await prefetchImages()
            return
        }
        tracks = []
        guard let result = await TrackListLoader.playlist(api: library.api, id: live.id, progress: { tracks = $0 }) else { return }
        isComplete = true
        if settings.cacheLists, let snapshot = live.snapshotId {
            await TrackListCache.save(key: live.id, stamp: snapshot, tracks: result)
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
    @State private var showMenu = false
    @State private var pendingDestination: MenuDestination?
    @State private var destination: MenuDestination?

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
                leading: HeaderAction(symbol: "shuffle", label: "Shuffle", isOn: player.shuffle) {
                    Task { await player.toggleShuffle() }
                },
                trailing: HeaderAction(
                    symbol: library.isSaved(album) ? "checkmark.circle.fill" : "plus.circle",
                    label: library.isSaved(album) ? "Remove from library" : "Save to library",
                    isOn: library.isSaved(album)
                ) {
                    let saved = library.isSaved(album)
                    Task { await library.setSaved(album, saved: !saved) }
                }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showMenu, onDismiss: {
            destination = pendingDestination
            pendingDestination = nil
        }) {
            AlbumMenuSheet(album: album, tracks: tracks, onSelect: { pendingDestination = $0 })
        }
        .sheet(item: $destination) { destination in
            MenuDestinationSheet(destination: destination, album: album, tracks: tracks, onAdded: { _, _ in })
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
    @State private var showMenu = false
    @State private var pendingDestination: MenuDestination?
    @State private var destination: MenuDestination?
    @State private var query = ""
    @State private var isSearching = false

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var visibleTracks: [(offset: Int, element: Track)] { indexedTracks(tracks, matching: query) }

    var body: some View {
        List {
            if !isSearching {
                DetailHeader(
                    imageURL: nil,
                    liked: true,
                    title: "Liked Songs",
                    subtitle: "\(library.likedTotal) songs",
                    isPlaying: player.isPlaying(context: Self.contextKey),
                    leading: HeaderAction(symbol: "shuffle", label: "Shuffle", isOn: player.shuffle) {
                        Task { await player.toggleShuffle() }
                    }
                ) {
                    Task { await player.playOrPause(uris: tracks.map(\.uri), key: Self.contextKey) }
                }
                .detailRow(top: 0)
            }

            ForEach(visibleTracks, id: \.offset) { index, track in
                Button {
                    Task { await player.play(uris: tracks.map(\.uri), startAt: index, key: Self.contextKey, showing: track) }
                } label: {
                    TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                }
                .buttonStyle(.plain)
                .trackActions(track)
                .detailRow()
            }

            if hasQuery && visibleTracks.isEmpty {
                ContentUnavailableView.search(text: query)
                    .detailRow(top: 24)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationBarTitleDisplayMode(.inline)
        .trackSearch(text: $query, isActive: $isSearching, enabled: isSearching)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SearchButton(isActive: $isSearching)
                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showMenu, onDismiss: {
            destination = pendingDestination
            pendingDestination = nil
        }) {
            LikedMenuSheet(tracks: tracks, total: library.likedTotal, onSelect: { pendingDestination = $0 })
        }
        .sheet(item: $destination) { destination in
            MenuDestinationSheet(destination: destination, liked: true, tracks: tracks, onAdded: { _, _ in })
        }
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
