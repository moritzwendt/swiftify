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
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerManager.self) private var player
    @Namespace private var chipSpace
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
                        markable: true
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
                    markable: true
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
                    markable: false
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

    var body: some View {
        NavigationStack {
            List {
                if settings.showLikedSongsRow && sub == nil && (filter == nil || filter == .playlists) {
                    NavigationLink(value: Route.likedSongs) {
                        MediaRow(
                            imageURL: nil,
                            title: "Liked Songs",
                            subtitle: "Playlist \u{2022} \(library.likedTotal) songs",
                            liked: true
                        )
                    }
                    .listRowSeparator(.hidden)
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
                    .contextMenu {
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
                }
            }
            .listStyle(.plain)
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .navigationTitle("Your Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileButton() }
            }
            .appDestinations()
            .haptic(.success, trigger: library.pinned)
            .task { await library.load() }
            .refreshable { await library.load(force: true) }
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

    private var marked: Bool { filter == .downloaded || sub == .downloaded }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            chips
            sortRow
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if filter != nil {
                        Button {
                            select(nil)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 20, height: 20)
                                .padding(9)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("clear", in: chipSpace)
                        .accessibilityLabel("Clear filter")
                    }
                    if let filter {
                        chip(filter.rawValue, id: filter.rawValue, selected: true) {}
                        ForEach(subFilters(for: filter), id: \.rawValue) { value in
                            chip(value.rawValue, id: "sub-\(value.rawValue)", selected: sub == value) {
                                withAnimation(.bouncy) { sub = sub == value ? nil : value }
                            }
                        }
                    } else {
                        ForEach(LibraryFilter.allCases, id: \.self) { value in
                            chip(value.rawValue, id: value.rawValue, selected: false) { select(value) }
                        }
                    }
                }
                .padding(.vertical, 4)
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
        withAnimation(.bouncy) {
            filter = value
            sub = nil
        }
    }

    private func chip(_ title: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? settings.onAccent : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? .regular.tint(settings.accent).interactive() : .regular.interactive(),
            in: .capsule
        )
        .glassEffectID(id, in: chipSpace)
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
        }
    }
}
