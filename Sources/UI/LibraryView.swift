import SwiftUI

enum LibraryFilter: String, CaseIterable {
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
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
    @State private var filter: LibraryFilter?
    @State private var sort: LibrarySort = .recents

    private var items: [LibraryItem] {
        var all: [LibraryItem] = []
        if filter == nil || filter == .playlists || filter == .downloaded {
            all += library.playlists.map { playlist in
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
        if filter == nil || filter == .albums || filter == .downloaded {
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
        if filter == nil || filter == .artists {
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
        if filter == .downloaded {
            all = all.filter { library.isDownloaded($0.id) }
        }
        switch sort {
        case .recents: return all
        case .alphabetical: return all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .creator: return all.sorted { $0.creator.localizedCaseInsensitiveCompare($1.creator) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    chips
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    sortRow
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if filter == nil || filter == .playlists {
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
                            badge: library.isDownloaded(item.id)
                        )
                    }
                    .listRowSeparator(.hidden)
                    .navigationLinkIndicatorVisibility(.hidden)
                    .contextMenu {
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
            .navigationTitle("Your Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileButton() }
            }
            .appDestinations()
            .task { await library.load() }
            .refreshable { await library.load(force: true) }
            .overlay {
                if library.isLoading && library.playlists.isEmpty {
                    ProgressView()
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if let selected = filter {
                        Button {
                            withAnimation(.snappy) { filter = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glass)
                        chip(selected)
                    } else {
                        ForEach(LibraryFilter.allCases, id: \.self) { chip($0) }
                    }
                }
            }
        }
    }

    private func chip(_ value: LibraryFilter) -> some View {
        let selected = filter == value
        return Button {
            withAnimation(.snappy) { filter = value }
        } label: {
            Text(value.rawValue)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? .black : .primary)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.glass)
        .tint(selected ? Theme.accent : nil)
    }

    private var sortRow: some View {
        HStack {
            Menu {
                Picker("Sort by", selection: $sort) {
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
