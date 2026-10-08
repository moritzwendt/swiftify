import SwiftUI

struct ProfileButton: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LibraryStore.self) private var library
    @State private var showTest = false

    private var initial: String {
        String((library.me?.displayName ?? "S").prefix(1)).uppercased()
    }

    var body: some View {
        Menu {
            Button("Playback test") { showTest = true }
            Button("Sign out", role: .destructive) { auth.signOut() }
        } label: {
            Text(initial)
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(Theme.accent, in: Circle())
        }
        .sheet(isPresented: $showTest) {
            NavigationStack {
                PlaybackTestView(auth: auth)
            }
        }
    }
}

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var recentAlbums: [Album] = []
    @State private var topArtists: [Artist] = []

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    quickGrid

                    if !recentAlbums.isEmpty {
                        shelf("Recently played") {
                            ForEach(recentAlbums) { album in
                                NavigationLink(value: Route.album(album)) {
                                    ShelfCard(
                                        imageURL: album.images.url(atLeast: 300),
                                        title: album.name,
                                        subtitle: album.artistLine
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !topArtists.isEmpty {
                        shelf("Your top artists") {
                            ForEach(topArtists) { artist in
                                NavigationLink(value: Route.artist(artist)) {
                                    ShelfCard(
                                        imageURL: artist.images.url(atLeast: 300),
                                        title: artist.name,
                                        subtitle: "",
                                        circle: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .appDestinations()
            .task { await loadShelves() }
            .refreshable {
                await library.load(force: true)
                await loadShelves()
            }
        }
    }

    private var quickGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            NavigationLink(value: Route.likedSongs) {
                quickCard(title: "Liked Songs", imageURL: nil, liked: true)
            }
            ForEach(library.playlists.prefix(5)) { playlist in
                NavigationLink(value: Route.playlist(playlist)) {
                    quickCard(title: playlist.name, imageURL: playlist.images.url(atLeast: 100), liked: false)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func quickCard(title: String, imageURL: URL?, liked: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if liked {
                    LikedArtwork(cornerRadius: 0)
                } else {
                    ArtworkView(url: imageURL, cornerRadius: 0)
                }
            }
            .frame(width: 52, height: 52)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func shelf<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    content()
                }
            }
            .scrollClipDisabled()
        }
    }

    private func loadShelves() async {
        if library.isSample { return }
        let history: Page<PlayHistory>? = try? await library.api.get(
            "me/player/recently-played",
            query: ["limit": "50"]
        )
        var seen = Set<String>()
        recentAlbums = (history?.items ?? []).compactMap { $0.track?.album }.filter { seen.insert($0.id).inserted }.prefix(12).map { $0 }
        let top: Page<Artist>? = try? await library.api.get(
            "me/top/artists",
            query: ["limit": "12", "time_range": "medium_term"]
        )
        topArtists = top?.items ?? []
    }
}
