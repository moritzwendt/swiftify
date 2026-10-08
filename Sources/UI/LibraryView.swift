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
    @State private var path: [Route] = []

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
        NavigationStack(path: $path) {
            List {
                sortRow
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))

                if settings.libraryGrid {
                    gridRows
                } else {
                    listRows
                }
            }
            .listStyle(.plain)
            .refreshable { await library.load(force: true) }
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

    @ViewBuilder
    private var listRows: some View {
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
            .listRowInsets(rowInsets)
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
            .listRowInsets(rowInsets)
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

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
    }

    private struct GridEntry: Identifiable {
        let item: LibraryItem?
        var id: String { item?.id ?? "liked" }
    }

    private struct GridLine: Identifiable {
        let entries: [GridEntry]
        var id: String { entries.map(\.id).joined(separator: "|") }
    }

    private var gridLines: [GridLine] {
        let entries = (showLiked ? [GridEntry(item: nil)] : []) + items.map { GridEntry(item: $0) }
        return stride(from: 0, to: entries.count, by: 3).map {
            GridLine(entries: Array(entries[$0..<min($0 + 3, entries.count)]))
        }
    }

    private var gridRows: some View {
        ForEach(gridLines) { line in
            HStack(alignment: .top, spacing: 12) {
                ForEach(line.entries) { entry in
                    gridButton(entry)
                }
                ForEach(0..<(3 - line.entries.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    @ViewBuilder
    private func gridButton(_ entry: GridEntry) -> some View {
        if let item = entry.item {
            Button {
                path.append(item.route)
            } label: {
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
            .frame(maxWidth: .infinity)
            .contextMenu { menuItems(item) }
        } else {
            Button {
                path.append(.likedSongs)
            } label: {
                gridCell(imageURL: nil, title: "Liked Songs", kind: "Playlist", liked: true)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
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

    @ViewBuilder
    private var chips: some View {
        if filter == nil {
            GeometryReader { geometry in
                let widths = Self.fillWidths(
                    LibraryFilter.allCases.map(\.rawValue),
                    available: geometry.size.width,
                    spacing: 8
                )
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Array(LibraryFilter.allCases.enumerated()), id: \.element) { index, value in
                            chip(value.rawValue, selected: false, fill: true) {
                                withAnimation(.snappy) { select(value) }
                            }
                            .frame(width: widths[index])
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(height: 52)
        } else if let selected = filter {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
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
                    }
                }
            }
            .scrollClipDisabled()
            .frame(height: 52)
        }
    }

    private static func fillWidths(_ titles: [String], available: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let size = UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        let font = UIFont.systemFont(ofSize: size, weight: .medium)
        let weights = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width + 24 }
        let usable = available - spacing * CGFloat(max(titles.count - 1, 0))
        let total = weights.reduce(0, +)
        return weights.map { $0 / total * usable }
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
    private func chip(_ title: String, selected: Bool, fill: Bool = false, action: @escaping () -> Void) -> some View {
        if selected {
            Button(action: action) {
                chipLabel(title, selected: true, fill: fill)
            }
            .buttonStyle(.glassProminent)
            .tint(settings.accent)
        } else {
            Button(action: action) {
                chipLabel(title, selected: false, fill: fill)
            }
            .buttonStyle(.glass)
        }
    }

    private func chipLabel(_ title: String, selected: Bool, fill: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(selected ? settings.onAccent : .primary)
            .padding(.vertical, 8)
            .padding(.horizontal, fill ? 0 : 6)
            .frame(maxWidth: fill ? .infinity : nil)
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
                settings.libraryGrid.toggle()
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

