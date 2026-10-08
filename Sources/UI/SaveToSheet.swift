import SwiftUI

struct SaveToSheet: View {
    private enum Row: Identifiable {
        case liked
        case playlist(Playlist)

        var id: String {
            switch self {
            case .liked: "liked"
            case .playlist(let playlist): playlist.id
            }
        }
    }

    let track: Track
    var fromPlus = false

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var liked: Bool?
    @State private var rows: [Row] = []
    @State private var ready = false
    @State private var pending: Set<String> = []
    @State private var errorMessage: String?

    private var membership: MembershipStore { library.membership }

    var body: some View {
        NavigationStack {
            Group {
                if ready {
                    list
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Save to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
                }
            }
            .haptic(.selection, trigger: liked)
            .task { await prepare() }
        }
        .presentationDetents([.medium, .large])
    }

    private var list: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .listRowSeparator(.hidden)
            }
            ForEach(rows) { row in
                switch row {
                case .liked:
                    Button {
                        Task { await toggleLiked() }
                    } label: {
                        rowLabel(
                            title: "Liked Songs",
                            isOn: liked == true,
                            isBusy: pending.contains("liked")
                        ) {
                            LikedArtwork()
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                case .playlist(let playlist):
                    Button {
                        Task { await toggle(playlist) }
                    } label: {
                        rowLabel(
                            title: playlist.name,
                            isOn: membership.contains(playlist.id, uri: track.uri) == true,
                            isBusy: pending.contains(playlist.id)
                        ) {
                            ArtworkView(url: playlist.images.url(atLeast: 100), cornerRadius: 6)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
    }

    private func rowLabel<Art: View>(
        title: String,
        isOn: Bool,
        isBusy: Bool,
        @ViewBuilder art: () -> Art
    ) -> some View {
        HStack(spacing: 12) {
            art().frame(width: 48, height: 48)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isBusy {
                ProgressView()
            } else if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func prepare() async {
        if library.isSample {
            liked = false
        } else {
            let result: [Bool]? = try? await library.api.get("me/library/contains", query: ["uris": track.uri])
            liked = result?.first ?? false
        }
        await membership.scan(library.editablePlaylists)
        if fromPlus, liked == false, !membership.isInAny(track.uri) {
            await toggleLiked()
        }
        rows = buildRows()
        ready = true
    }

    private func buildRows() -> [Row] {
        let editable = Array(library.editablePlaylists.enumerated())
        func byUsage(_ items: [(offset: Int, element: Playlist)]) -> [Playlist] {
            items
                .sorted { lhs, rhs in
                    let left = library.usage(of: lhs.element.uri)
                    let right = library.usage(of: rhs.element.uri)
                    return left == right ? lhs.offset < rhs.offset : left > right
                }
                .map(\.element)
        }
        let assigned = byUsage(editable.filter { membership.contains($0.element.id, uri: track.uri) == true })
        let others = byUsage(editable.filter { membership.contains($0.element.id, uri: track.uri) != true })
        var result: [Row] = []
        if liked == true { result.append(.liked) }
        result += assigned.map(Row.playlist)
        if liked != true { result.append(.liked) }
        result += others.map(Row.playlist)
        return result
    }

    private func toggleLiked() async {
        guard let current = liked else { return }
        let target = !current
        liked = target
        pending.insert("liked")
        defer { pending.remove("liked") }
        if !library.isSample {
            do {
                try await library.api.perform(target ? "PUT" : "DELETE", "me/library", query: ["uris": track.uri])
            } catch {
                liked = current
                errorMessage = error.localizedDescription
                return
            }
        }
        library.adjustLikedTotal(by: target ? 1 : -1)
        player.syncLiked(uri: track.uri, liked: target)
    }

    private func toggle(_ playlist: Playlist) async {
        let isMember = membership.contains(playlist.id, uri: track.uri) ?? false
        pending.insert(playlist.id)
        defer { pending.remove(playlist.id) }
        errorMessage = nil
        if library.isSample {
            membership.record(playlistID: playlist.id, uri: track.uri, added: !isMember, snapshot: nil)
            return
        }
        do {
            let response: SnapshotResponse
            if isMember {
                response = try await library.api.request(
                    "DELETE",
                    "playlists/\(playlist.id)/items",
                    body: ["items": [["uri": track.uri]]]
                )
            } else {
                response = try await library.api.request(
                    "POST",
                    "playlists/\(playlist.id)/items",
                    body: ["uris": [track.uri]]
                )
                library.noteSave(playlist.uri)
            }
            membership.record(playlistID: playlist.id, uri: track.uri, added: !isMember, snapshot: response.snapshotId)
            if let snapshot = response.snapshotId {
                library.updateSnapshot(playlistID: playlist.id, snapshot: snapshot)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TrackActionsModifier: ViewModifier {
    let track: Track
    @State private var showSave = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Add to playlist", systemImage: "text.badge.plus") { showSave = true }
            }
            .sheet(isPresented: $showSave) {
                SaveToSheet(track: track)
            }
    }
}

extension View {
    func trackActions(_ track: Track) -> some View {
        modifier(TrackActionsModifier(track: track))
    }
}
