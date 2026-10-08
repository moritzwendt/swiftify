import SwiftUI

enum LibraryFilter: String, CaseIterable {
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
    case downloaded = "Downloaded"
}

enum LibrarySubFilter: String {
    case byYou = "By you"
    case bySpotify = "By Spotify"
    case downloaded = "Downloaded"
}

enum LibrarySort: String, CaseIterable {
    case recents = "Recents"
    case alphabetical = "Alphabetical"
    case creator = "Creator"
}

struct LibraryItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let creator: String
    let imageURL: URL?
    let route: Route
    let circle: Bool
    let markable: Bool
    let kind: String
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerManager.self) private var player
    @State private var filter: LibraryFilter?
    @State private var sub: LibrarySubFilter?

    private var sort: LibrarySort {
        get { LibrarySort(rawValue: settings.librarySortRaw) ?? .recents }
        nonmutating set { settings.librarySortRaw = newValue.rawValue }
    }

    private var items: [LibraryItem] {
        var all: [LibraryItem] = []
        let marked = filter == .downloaded || sub == .downloaded
        if filter == nil || filter == .playlists || filter == .downloaded {
            all += library.playlists
                .filter { playlist in
                    switch sub {
                    case .byYou: playlist.owner?.id == library.me?.id
                    case .bySpotify: playlist.owner?.id == "spotify"
                    default: true
                    }
                }
                .map { playlist in
                    LibraryItem(
                        id: playlist.uri,
                        title: playlist.name,
                        subtitle: "Playlist \u{2022} \(playlist.owner?.displayName ?? "Spotify")",
                        creator: playlist.owner?.displayName ?? "",
                        imageURL: playlist.images.url(atLeast: 100),
                        route: .playlist(playlist),
                        circle: false,
                        markable: true,
                        kind: "Playlist"
                    )
                }
        }
        if sub == nil || sub == .downloaded, filter == nil || filter == .albums || filter == .downloaded {
            all += library.albums.map { saved in
                LibraryItem(
                    id: saved.album.uri,
                    title: saved.album.name,
                    subtitle: "Album \u{2022} \(saved.album.artistLine)",
                    creator: saved.album.artistLine,
                    imageURL: saved.album.images.url(atLeast: 100),
                    route: .album(saved.album),
                    circle: false,
                    markable: true,
                    kind: "Album"
                )
            }
        }
        if sub == nil, filter == nil || filter == .artists {
            all += library.artists.map { artist in
                LibraryItem(
                    id: artist.uri,
                    title: artist.name,
                    subtitle: "Artist",
                    creator: artist.name,
                    imageURL: artist.images.url(atLeast: 100),
                    route: .artist(artist),
                    circle: true,
                    markable: false,
                    kind: "Artist"
                )
            }
        }
        if marked {
            all = all.filter { library.isDownloaded($0.id) }
        }
        let sorted: [LibraryItem]
        switch sort {
        case .recents:
            let rank = Dictionary(uniqueKeysWithValues: library.recentOrder.enumerated().map { ($1, $0) })
            sorted = all.enumerated()
                .sorted { lhs, rhs in
                    let left = rank[lhs.element.id] ?? Int.max
                    let right = rank[rhs.element.id] ?? Int.max
                    return left == right ? lhs.offset < rhs.offset : left < right
                }
                .map(\.element)
        case .alphabetical:
            sorted = all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .creator:
            sorted = all.sorted { $0.creator.localizedCaseInsensitiveCompare($1.creator) == .orderedAscending }
        }
        let pins = library.pinned
        let pinnedItems = pins.compactMap { id in sorted.first { $0.id == id } }
        return pinnedItems + sorted.filter { !pins.contains($0.id) }
    }

    private var showLiked: Bool {
        settings.showLikedSongsRow && (sub == nil || sub == .byYou) && (filter == nil || filter == .playlists)
    }

    var body: some View {
        NavigationStack {
            Group {
                if settings.libraryGrid {
                    gridContent
                } else {
                    listContent
                }
            }
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .navigationTitle("Your Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileButton() }
            }
            .appDestinations()
            .haptic(.success, trigger: library.pinned)
            .task { await library.load() }
            .onChange(of: player.contextURI) { _, uri in
                if let uri { library.noteRecent(uri) }
            }
            .overlay {
                if library.isLoading && library.playlists.isEmpty {
                    ProgressView()
                } else if items.isEmpty && filter != nil {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: "tray",
                        description: Text(marked ? "Touch and hold an item to mark it as downloaded" : "")
                    )
                }
            }
        }
    }

    private var listContent: some View {
        List {
            sortRow
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))

            if showLiked {
                NavigationLink(value: Route.likedSongs) {
                    MediaRow(
                        imageURL: nil,
                        title: "Liked Songs",
                        subtitle: "Playlist \u{2022} \(library.likedTotal) songs",
                        liked: true
                    )
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .navigationLinkIndicatorVisibility(.hidden)
            }

            ForEach(items) { item in
                NavigationLink(value: item.route) {
                    MediaRow(
                        imageURL: item.imageURL,
                        title: item.title,
                        subtitle: item.subtitle,
                        circle: item.circle,
                        badge: library.isDownloaded(item.id),
                        pinned: library.isPinned(item.id)
                    )
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .navigationLinkIndicatorVisibility(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation(.snappy) { library.togglePin(item.id) }
                    } label: {
                        Label(
                            library.isPinned(item.id) ? "Unpin" : "Pin",
                            systemImage: library.isPinned(item.id) ? "pin.slash.fill" : "pin.fill"
                        )
                    }
                    .tint(settings.accent)
                }
                .contextMenu { menuItems(item) }
            }
        }
        .listStyle(.plain)
        .refreshable { await library.load(force: true) }
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sortRow
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    if showLiked {
                        NavigationLink(value: Route.likedSongs) {
                            gridCell(imageURL: nil, title: "Liked Songs", kind: "Playlist", liked: true)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(items) { item in
                        NavigationLink(value: item.route) {
                            gridCell(
                                imageURL: item.imageURL,
                                title: item.title,
                                kind: item.kind,
                                circle: item.circle,
                                pinned: library.isPinned(item.id),
                                downloaded: library.isDownloaded(item.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menuItems(item) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .refreshable { await library.load(force: true) }
    }

    private func gridCell(
        imageURL: URL?,
        title: String,
        kind: String,
        liked: Bool = false,
        circle: Bool = false,
        pinned: Bool = false,
        downloaded: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if liked {
                    LikedArtwork()
                } else {
                    ArtworkView(url: imageURL, circle: circle)
                }
            }
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                if pinned {
                    Image(systemName: "pin.fill").foregroundStyle(.tint)
                }
                if downloaded {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                }
                Text(kind)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func menuItems(_ item: LibraryItem) -> some View {
        Button(
            library.isPinned(item.id) ? "Unpin" : "Pin",
            systemImage: library.isPinned(item.id) ? "pin.slash" : "pin"
        ) {
            withAnimation(.snappy) { library.togglePin(item.id) }
        }
        if item.markable {
            Button(
                library.isDownloaded(item.id) ? "Remove download mark" : "Mark as downloaded",
                systemImage: "arrow.down.circle"
            ) {
                library.toggleDownloaded(item.id)
            }
        }
    }

    private var marked: Bool { filter == .downloaded || sub == .downloaded }

    private var header: some View {
        chips
            .padding(.horizontal, 16)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if let selected = filter {
                        Button {
                            withAnimation(.snappy) { select(nil) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Clear filter")
                        chip(selected.rawValue, selected: true) {}
                        ForEach(subFilters(for: selected), id: \.rawValue) { value in
                            chip(value.rawValue, selected: sub == value) {
                                withAnimation(.snappy) { sub = sub == value ? nil : value }
                            }
                        }
                    } else {
                        ForEach(LibraryFilter.allCases, id: \.self) { value in
                            chip(value.rawValue, selected: false) {
                                withAnimation(.snappy) { select(value) }
                            }
                        }
                    }
                }
            }
        }
        .scrollClipDisabled()
        .frame(height: 52)
    }

    private func subFilters(for filter: LibraryFilter) -> [LibrarySubFilter] {
        switch filter {
        case .playlists: [.byYou, .bySpotify, .downloaded]
        case .albums: [.downloaded]
        default: []
        }
    }

    private func select(_ value: LibraryFilter?) {
        filter = value
        sub = nil
    }

    @ViewBuilder
    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        if selected {
            Button(action: action) {
                chipLabel(title, selected: true)
            }
            .buttonStyle(.glassProminent)
            .tint(settings.accent)
        } else {
            Button(action: action) {
                chipLabel(title, selected: false)
            }
            .buttonStyle(.glass)
        }
    }

    private func chipLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? settings.onAccent : .primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
    }

    private var sortRow: some View {
        HStack {
            Menu {
                Picker("Sort by", selection: Binding(get: { sort }, set: { sort = $0 })) {
                    ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.primary)
            Spacer()
            Button {
                withAnimation(.snappy) { settings.libraryGrid.toggle() }
            } label: {
                Image(systemName: settings.libraryGrid ? "list.bullet" : "square.grid.2x2")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityLabel(settings.libraryGrid ? "List layout" : "Grid layout")
        }
    }
}
