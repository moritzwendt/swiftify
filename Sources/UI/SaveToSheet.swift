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

        var title: String {
            switch self {
            case .liked: "Liked Songs"
            case .playlist(let playlist): playlist.name
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
    @State private var initialAssigned: Set<String> = []
    @State private var ready = false
    @State private var pending: Set<String> = []
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var showNew = false
    @State private var newName = ""

    private var membership: MembershipStore { library.membership }

    private var visibleRows: [Row] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return rows }
        return rows.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

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
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .navigationTitle("Save to")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find a playlist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New playlist", systemImage: "plus") {
                        newName = ""
                        showNew = true
                    }
                    .tint(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
                }
            }
            .alert("New playlist", isPresented: $showNew) {
                TextField("Name", text: $newName)
                Button("Create") { Task { await createPlaylist() } }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .haptic(.selection, trigger: liked)
            .task { await prepare() }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.album?.images.url(atLeast: 100), cornerRadius: 6)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(track.artistLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var list: some View {
        let assigned = visibleRows.filter { initialAssigned.contains($0.id) }
        let others = visibleRows.filter { !initialAssigned.contains($0.id) }
        return List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .listRowSeparator(.hidden)
            }

            if !assigned.isEmpty {
                Section {
                    ForEach(assigned) { rowButton($0) }
                } header: {
                    if !others.isEmpty { Text("Saved in") }
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { rowButton($0) }
                } header: {
                    if !assigned.isEmpty { Text("Your playlists") }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func rowButton(_ row: Row) -> some View {
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
                    .symbolEffect(.bounce, value: isOn)
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
        initialAssigned = Set(rows.compactMap { row -> String? in
            switch row {
            case .liked: liked == true ? row.id : nil
            case .playlist(let playlist): membership.contains(playlist.id, uri: track.uri) == true ? row.id : nil
            }
        })
        ready = true
    }

    private func createPlaylist() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty, !library.isSample else { return }
        errorMessage = nil
        do {
            let created = try await library.createPlaylist(named: name)
            let response: SnapshotResponse = try await library.api.request(
                "POST",
                "playlists/\(created.id)/items",
                body: ["uris": [track.uri]]
            )
            membership.record(playlistID: created.id, uri: track.uri, added: true, snapshot: response.snapshotId)
            if let snapshot = response.snapshotId {
                library.updateSnapshot(playlistID: created.id, snapshot: snapshot)
            }
            library.noteSave(created.uri)
            let inserted: Row = .playlist(created)
            let insertAt = rows.first.map { if case .liked = $0, liked == true { 1 } else { 0 } } ?? 0
            rows.insert(inserted, at: insertAt)
            initialAssigned.insert(inserted.id)
        } catch {
            errorMessage = error.localizedDescription
        }
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
    @Environment(QueueStore.self) private var queue
    @State private var showSave = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
                    Task { await queue.add(track) }
                }
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
