import SwiftUI

struct SearchHits {
    var tracks: [Track] = []
    var artists: [Artist] = []
    var albums: [Album] = []
    var playlists: [Playlist] = []

    init() {}

    init(_ results: SearchResults) {
        tracks = results.tracks?.items ?? []
        artists = results.artists?.items ?? []
        albums = results.albums?.items ?? []
        playlists = results.playlists?.items ?? []
    }

    var isEmpty: Bool { tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty }
}

enum SearchTop {
    case artist(Artist)
    case album(Album)
    case playlist(Playlist)
    case track(Track)
}

private enum SearchHistory {
    static let key = "searchHistory"
    static let limit = 12

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ items: [String]) {
        UserDefaults.standard.set(items, forKey: key)
    }
}

private func fold(_ text: String) -> String {
    text
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var query = ""
    @State private var committedQuery: String?
    @State private var hits = SearchHits()
    @State private var cache: [String: SearchHits] = [:]
    @State private var history = SearchHistory.load()
    @State private var path: [Route] = []
    @FocusState private var searchFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var suggestions: [String] {
        let needle = fold(query)
        guard !needle.isEmpty, committedQuery != query else { return [] }
        var seen: Set<String> = [needle]
        var result: [String] = []
        func offer(_ text: String) {
            guard result.count < 5 else { return }
            let key = fold(text)
            guard key.hasPrefix(needle), seen.insert(key).inserted else { return }
            result.append(text.lowercased())
        }
        history.forEach(offer)
        hits.artists.forEach { offer($0.name) }
        hits.albums.forEach { offer($0.name) }
        hits.tracks.forEach { offer($0.name) }
        hits.playlists.forEach { offer($0.name) }
        hits.albums.forEach { album in
            if let artist = album.artists?.first?.name { offer("\(artist) \(album.name)") }
        }
        hits.tracks.forEach { track in
            if let artist = track.artists?.first?.name { offer("\(artist) \(track.name)") }
        }
        library.artists.forEach { offer($0.name) }
        library.playlists.forEach { offer($0.name) }
        library.albums.forEach { offer($0.album.name) }
        return result
    }

    private var top: SearchTop? {
        let needle = fold(query)
        guard !needle.isEmpty else { return nil }
        let words = needle.split(separator: " ").map(String.init)
        func score(_ name: String, bias: Int) -> Int {
            let key = fold(name)
            var base = 0
            if key == needle {
                base = 100
            } else if key.hasPrefix(needle) {
                base = 80
            } else if !words.isEmpty, words.allSatisfy({ key.contains($0) }) {
                base = 60
            }
            return base == 0 ? 0 : base + bias
        }
        var best: (score: Int, item: SearchTop)?
        func consider(_ value: Int, _ item: SearchTop) {
            guard value > 0, value > (best?.score ?? 0) else { return }
            best = (value, item)
        }
        hits.artists.forEach { consider(score($0.name, bias: 5), .artist($0)) }
        hits.albums.forEach { consider(score($0.name, bias: 2), .album($0)) }
        hits.playlists.forEach { consider(score($0.name, bias: 0), .playlist($0)) }
        hits.tracks.forEach { consider(score($0.name, bias: -3), .track($0)) }
        return best?.item
    }

    private var topArtistID: String? {
        if case .artist(let artist) = top { return artist.id }
        return nil
    }

    private var topAlbumID: String? {
        if case .album(let album) = top { return album.id }
        return nil
    }

    private var topPlaylistID: String? {
        if case .playlist(let playlist) = top { return playlist.id }
        return nil
    }

    private var topTrackURI: String? {
        if case .track(let track) = top { return track.uri }
        return nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if trimmed.isEmpty {
                    idle
                } else {
                    resultList
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "What do you want to play?")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { commit(query) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileButton() }
            }
            .appDestinations()
            .task(id: query) { await search() }
        }
    }

    @ViewBuilder
    private var idle: some View {
        if history.isEmpty {
            ContentUnavailableView("Search Spotify", systemImage: "magnifyingglass")
        } else {
            List {
                Section {
                    ForEach(history, id: \.self) { item in
                        HStack(spacing: 14) {
                            Button {
                                commit(item)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    Text(item)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                remove(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove")
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent searches")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Spacer()
                        Button("Clear") {
                            withAnimation { history = [] }
                            SearchHistory.save([])
                        }
                        .font(.subheadline)
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var resultList: some View {
        List {
            ForEach(suggestions, id: \.self) { suggestion in
                suggestionRow(suggestion)
                    .listRowSeparator(.hidden)
            }

            if let top {
                Section("Top result") {
                    topRow(top)
                }
            }

            let tracks = hits.tracks.filter { $0.uri != topTrackURI }
            if !tracks.isEmpty {
                Section("Songs") {
                    ForEach(tracks, id: \.uri) { track in
                        Button {
                            record(trimmed)
                            Task { await player.play(uris: [track.uri], showing: track) }
                        } label: {
                            TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                        }
                        .buttonStyle(.plain)
                        .trackActions(track)
                    }
                }
            }
            let artists = hits.artists.filter { $0.id != topArtistID }
            if !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists) { artist in
                        routeRow(.artist(artist)) {
                            MediaRow(imageURL: artist.images.url(atLeast: 100), title: artist.name, subtitle: "Artist", circle: true)
                        }
                    }
                }
            }
            let albums = hits.albums.filter { $0.id != topAlbumID }
            if !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums) { album in
                        routeRow(.album(album)) {
                            MediaRow(imageURL: album.images.url(atLeast: 100), title: album.name, subtitle: album.artistLine)
                        }
                    }
                }
            }
            let playlists = hits.playlists.filter { $0.id != topPlaylistID }
            if !playlists.isEmpty {
                Section("Playlists") {
                    ForEach(playlists) { playlist in
                        routeRow(.playlist(playlist)) {
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
        .overlay {
            if hits.isEmpty && suggestions.isEmpty && committedQuery == query {
                ContentUnavailableView.search(text: trimmed)
            }
        }
    }

    @ViewBuilder
    private func topRow(_ item: SearchTop) -> some View {
        switch item {
        case .artist(let artist):
            routeRow(.artist(artist)) {
                MediaRow(imageURL: artist.images.url(atLeast: 100), title: artist.name, subtitle: "Artist", circle: true)
            }
        case .album(let album):
            routeRow(.album(album)) {
                MediaRow(
                    imageURL: album.images.url(atLeast: 100),
                    title: album.name,
                    subtitle: ["Album", album.artistLine].filter { !$0.isEmpty }.joined(separator: " \u{2022} ")
                )
            }
        case .playlist(let playlist):
            routeRow(.playlist(playlist)) {
                MediaRow(
                    imageURL: playlist.images.url(atLeast: 100),
                    title: playlist.name,
                    subtitle: ["Playlist", playlist.owner?.displayName ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{2022} ")
                )
            }
        case .track(let track):
            Button {
                record(trimmed)
                Task { await player.play(uris: [track.uri], showing: track) }
            } label: {
                TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
            }
            .buttonStyle(.plain)
            .trackActions(track)
        }
    }

    private func routeRow<Content: View>(_ route: Route, @ViewBuilder label: () -> Content) -> some View {
        Button {
            record(trimmed)
            searchFocused = false
            path.append(route)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    private func suggestionRow(_ suggestion: String) -> some View {
        let typed = min(trimmed.count, suggestion.count)
        return HStack(spacing: 14) {
            Button {
                commit(suggestion)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    (Text(String(suggestion.prefix(typed))).foregroundStyle(.secondary)
                        + Text(String(suggestion.dropFirst(typed))).fontWeight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                query = suggestion + " "
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use suggestion")
        }
    }

    private func commit(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        committedQuery = value
        query = value
        record(value)
        searchFocused = false
    }

    private func record(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var items = history.filter { fold($0) != fold(value) }
        items.insert(value, at: 0)
        history = Array(items.prefix(SearchHistory.limit))
        SearchHistory.save(history)
    }

    private func remove(_ item: String) {
        withAnimation { history.removeAll { $0 == item } }
        SearchHistory.save(history)
    }

    private func search() async {
        guard !trimmed.isEmpty else {
            hits = SearchHits()
            return
        }
        let key = fold(trimmed)
        if let cached = cache[key] {
            hits = cached
            return
        }
        try? await Task.sleep(for: .milliseconds(160))
        if Task.isCancelled { return }
        if library.isSample {
            hits = sampleHits(for: trimmed)
            return
        }
        let response: SearchResults? = try? await library.api.get(
            "search",
            query: ["q": trimmed, "type": "track,artist,album,playlist", "limit": "10"]
        )
        if Task.isCancelled { return }
        if let response {
            let found = SearchHits(response)
            cache[key] = found
            hits = found
        }
    }

    private func sampleHits(for text: String) -> SearchHits {
        let needle = fold(text)
        var found = SearchHits()
        found.tracks = SampleData.tracks.filter { $0.matches(text) }
        found.artists = library.artists.filter { fold($0.name).contains(needle) }
        found.albums = library.albums.map(\.album).filter { fold($0.name).contains(needle) }
        found.playlists = library.playlists.filter { fold($0.name).contains(needle) }
        return found
    }
}
