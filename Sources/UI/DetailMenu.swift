import PhotosUI
import SwiftUI
import UIKit

final class SerialTasks {
    private var last: Task<Void, Never>?

    @MainActor
    func run(_ work: @escaping @MainActor () async -> Void) {
        let previous = last
        last = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}

enum MenuDestination: String, Identifiable {
    case addSongs
    case addToPlaylist
    case details
    case cover

    var id: String { rawValue }
}

private struct MenuRow: View {
    let symbol: String
    let title: String
    var isOn = false
    var destructive = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            Text(title)
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

private struct MenuButton: View {
    let symbol: String
    let title: String
    var isOn = false
    var destructive = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRow(symbol: symbol, title: title, isOn: isOn, destructive: destructive)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

private struct MenuHeader: View {
    let imageURL: URL?
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(url: imageURL, cornerRadius: 6)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }
}

private struct MenuContainer<Content: View>: View {
    @State private var height: CGFloat = 560
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
            }
            .padding(.top, 28)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }
}

struct FollowersBox: Decodable {
    struct Total: Decodable { let total: Int? }
    let followers: Total?
}

struct PlaylistMenuSheet: View {
    let playlist: Playlist
    let tracks: [Track]
    let isOwned: Bool
    let canEdit: Bool
    let isReady: Bool
    let saves: Int?
    let onSelect: (MenuDestination) -> Void
    let onEdit: () -> Void
    let onDeleted: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(QueueStore.self) private var queue
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var shareURL: URL {
        URL(string: "https://open.spotify.com/playlist/\(playlist.id)") ?? URL(string: "https://open.spotify.com")!
    }

    private var kind: String {
        if playlist.collaborative == true { return "Collaborative playlist" }
        switch playlist.public {
        case true: return "Public playlist"
        case false: return "Private playlist"
        default: return "Playlist"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let saves, saves > 0 { parts.append(Playlist.savesLabel(saves)) }
        parts.append(kind)
        return parts.joined(separator: " \u{2022} ")
    }

    private var isSaved: Bool { library.isSaved(playlist) }

    private func choose(_ destination: MenuDestination) {
        onSelect(destination)
        dismiss()
    }

    var body: some View {
        MenuContainer {
            MenuHeader(imageURL: playlist.images.url(atLeast: 100), title: playlist.name, subtitle: subtitle)

            ShareLink(item: shareURL) {
                MenuRow(symbol: "square.and.arrow.up", title: "Share")
            }
            .buttonStyle(.plain)

            if canEdit {
                MenuButton(symbol: "plus.circle", title: "Add songs to this playlist", enabled: isReady) {
                    choose(.addSongs)
                }
            }

            if !isOwned {
                MenuButton(
                    symbol: isSaved ? "checkmark.circle.fill" : "plus.circle",
                    title: isSaved ? "Remove from library" : "Save to library",
                    isOn: isSaved
                ) {
                    Task { await library.setSaved(playlist, saved: !isSaved) }
                    dismiss()
                }
            }

            MenuButton(symbol: "text.line.last.and.arrowtriangle.forward", title: "Add to queue", enabled: !tracks.isEmpty) {
                Task { await queue.add(tracks: tracks) }
                dismiss()
            }

            MenuButton(symbol: "text.badge.plus", title: "Add to other playlist", enabled: !tracks.isEmpty) {
                choose(.addToPlaylist)
            }

            MenuButton(
                symbol: library.isDownloaded(playlist.uri) ? "arrow.down.circle.fill" : "arrow.down.circle",
                title: library.isDownloaded(playlist.uri) ? "Remove download mark" : "Mark as downloaded",
                isOn: library.isDownloaded(playlist.uri)
            ) {
                library.toggleDownloaded(playlist.uri)
                dismiss()
            }

            MenuButton(
                symbol: library.isPinned(playlist.uri) ? "pin.slash" : "pin",
                title: library.isPinned(playlist.uri) ? "Unpin" : "Pin"
            ) {
                library.togglePin(playlist.uri)
                dismiss()
            }

            if canEdit {
                MenuButton(symbol: "line.3.horizontal", title: "Edit playlist", enabled: isReady) {
                    dismiss()
                    onEdit()
                }
            }

            if isOwned {
                MenuButton(symbol: "pencil", title: "Name and details") {
                    choose(.details)
                }
                MenuButton(symbol: "photo", title: "Change cover") {
                    choose(.cover)
                }
                MenuButton(symbol: "trash", title: "Delete playlist", destructive: true) {
                    confirmDelete = true
                }
            }
        }
        .confirmationDialog("Delete playlist", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await library.setSaved(playlist, saved: false) }
                dismiss()
                onDeleted()
            }
        }
    }
}

struct AlbumMenuSheet: View {
    let album: Album
    let tracks: [Track]
    let onSelect: (MenuDestination) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(QueueStore.self) private var queue
    @Environment(\.dismiss) private var dismiss

    private var shareURL: URL {
        URL(string: "https://open.spotify.com/album/\(album.id)") ?? URL(string: "https://open.spotify.com")!
    }

    private var subtitle: String {
        ["Album", album.artistLine, album.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{2022} ")
    }

    private var isSaved: Bool { library.isSaved(album) }

    var body: some View {
        MenuContainer {
            MenuHeader(imageURL: album.images.url(atLeast: 100), title: album.name, subtitle: subtitle)

            ShareLink(item: shareURL) {
                MenuRow(symbol: "square.and.arrow.up", title: "Share")
            }
            .buttonStyle(.plain)

            MenuButton(
                symbol: isSaved ? "checkmark.circle.fill" : "plus.circle",
                title: isSaved ? "Remove from library" : "Save to library",
                isOn: isSaved
            ) {
                Task { await library.setSaved(album, saved: !isSaved) }
                dismiss()
            }

            MenuButton(symbol: "text.line.last.and.arrowtriangle.forward", title: "Add to queue", enabled: !tracks.isEmpty) {
                Task { await queue.add(tracks: tracks) }
                dismiss()
            }

            MenuButton(symbol: "text.badge.plus", title: "Add to playlist", enabled: !tracks.isEmpty) {
                onSelect(.addToPlaylist)
                dismiss()
            }

            MenuButton(
                symbol: library.isDownloaded(album.uri) ? "arrow.down.circle.fill" : "arrow.down.circle",
                title: library.isDownloaded(album.uri) ? "Remove download mark" : "Mark as downloaded",
                isOn: library.isDownloaded(album.uri)
            ) {
                library.toggleDownloaded(album.uri)
                dismiss()
            }

            MenuButton(
                symbol: library.isPinned(album.uri) ? "pin.slash" : "pin",
                title: library.isPinned(album.uri) ? "Unpin" : "Pin"
            ) {
                library.togglePin(album.uri)
                dismiss()
            }
        }
    }
}

struct MenuDestinationSheet: View {
    let destination: MenuDestination
    var playlist: Playlist?
    var album: Album?
    let tracks: [Track]
    let onAdded: (Track, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .addSongs:
            if let playlist { AddSongsView(playlist: playlist, onAdded: onAdded) }
        case .addToPlaylist:
            AddToPlaylistView(
                title: playlist?.name ?? album?.name ?? "",
                imageURL: (playlist?.images ?? album?.images).url(atLeast: 100),
                uris: tracks.map(\.uri),
                excludingID: playlist?.id
            )
        case .details:
            if let playlist { PlaylistDetailsForm(playlist: playlist) }
        case .cover:
            if let playlist { PlaylistCoverView(playlist: playlist) }
        }
    }
}

struct PlaylistDetailsForm: View {
    let playlist: Playlist

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var details: String
    @State private var isPublic: Bool
    @State private var collaborative: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    init(playlist: Playlist) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
        _details = State(initialValue: playlist.description ?? "")
        _isPublic = State(initialValue: playlist.public ?? false)
        _collaborative = State(initialValue: playlist.collaborative ?? false)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !saving
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Description", text: $details, axis: .vertical)
                    .lineLimit(1...5)
            }
            Section {
                Toggle("Public", isOn: $isPublic)
                if !isPublic {
                    Toggle("Collaborative", isOn: $collaborative)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Name and details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave)
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await library.updatePlaylist(
                playlist,
                name: name.trimmingCharacters(in: .whitespaces),
                description: details.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: isPublic,
                collaborative: collaborative
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddSongsView: View {
    let playlist: Playlist
    let onAdded: (Track, String?) -> Void

    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var results: [Track] = []
    @State private var added: Set<String> = []
    @State private var busy: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .listRowSeparator(.hidden)
            }
            ForEach(results) { track in
                HStack(spacing: 12) {
                    TrackRow(track: track, artworkURL: track.album?.images.url(atLeast: 100))
                    if busy.contains(track.uri) {
                        ProgressView()
                    } else if added.contains(track.uri) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    } else {
                        Button {
                            Task { await add(track) }
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add")
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search for songs", systemImage: "magnifyingglass")
            }
        }
        .navigationTitle("Add songs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search songs")
        .haptic(.success, trigger: added.count)
        .task(id: query) { await search() }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        if library.isSample {
            results = SampleData.tracks.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            return
        }
        let response: SearchResults? = try? await library.api.get(
            "search",
            query: ["q": trimmed, "type": "track", "limit": "10"]
        )
        results = response?.tracks?.items ?? []
    }

    private func add(_ track: Track) async {
        errorMessage = nil
        busy.insert(track.uri)
        defer { busy.remove(track.uri) }
        if library.isSample {
            added.insert(track.uri)
            onAdded(track, nil)
            return
        }
        do {
            let response: SnapshotResponse = try await library.api.request(
                "POST",
                "playlists/\(playlist.id)/items",
                body: ["uris": [track.uri]]
            )
            library.membership.record(playlistID: playlist.id, uri: track.uri, added: true, snapshot: response.snapshotId)
            if let snapshot = response.snapshotId {
                library.updateSnapshot(playlistID: playlist.id, snapshot: snapshot)
            }
            added.insert(track.uri)
            onAdded(track, response.snapshotId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddToPlaylistView: View {
    let title: String
    let imageURL: URL?
    let uris: [String]
    var excludingID: String?

    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var busy: Set<String> = []
    @State private var done: Set<String> = []
    @State private var errorMessage: String?
    @State private var showNew = false
    @State private var newName = ""

    private var addable: [String] { uris.filter { !$0.hasPrefix("spotify:local:") } }

    private var playlists: [Playlist] {
        let editable = Array(library.editablePlaylists.enumerated()).filter { $0.element.id != excludingID }
        let sorted = editable
            .sorted { lhs, rhs in
                let left = library.usage(of: lhs.element.uri)
                let right = library.usage(of: rhs.element.uri)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .listRowSeparator(.hidden)
            }
            ForEach(playlists) { playlist in
                Button {
                    Task { await add(to: playlist) }
                } label: {
                    row(playlist)
                }
                .buttonStyle(.plain)
                .disabled(done.contains(playlist.id) || busy.contains(playlist.id))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .safeAreaBar(edge: .top, spacing: 0) { header }
        .navigationTitle("Add to playlist")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find a playlist")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New playlist", systemImage: "plus") {
                    newName = ""
                    showNew = true
                }
            }
        }
        .alert("New playlist", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .haptic(.success, trigger: done.count)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(url: imageURL, cornerRadius: 6)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(addable.count) songs")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func row(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: playlist.images.url(atLeast: 100), cornerRadius: 6)
                .frame(width: 48, height: 48)
            Text(playlist.name)
                .lineLimit(1)
            Spacer(minLength: 0)
            if busy.contains(playlist.id) {
                ProgressView()
            } else if done.contains(playlist.id) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty, !library.isSample else { return }
        errorMessage = nil
        do {
            let created = try await library.createPlaylist(named: name)
            await add(to: created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(to playlist: Playlist) async {
        errorMessage = nil
        busy.insert(playlist.id)
        defer { busy.remove(playlist.id) }
        if library.isSample {
            done.insert(playlist.id)
            return
        }
        do {
            var snapshot: String?
            for start in stride(from: 0, to: addable.count, by: 100) {
                let chunk = Array(addable[start..<min(start + 100, addable.count)])
                let response: SnapshotResponse = try await library.api.request(
                    "POST",
                    "playlists/\(playlist.id)/items",
                    body: ["uris": chunk]
                )
                snapshot = response.snapshotId ?? snapshot
            }
            library.membership.recordAll(playlistID: playlist.id, uris: addable, snapshot: snapshot)
            if let snapshot {
                library.updateSnapshot(playlistID: playlist.id, snapshot: snapshot)
            }
            library.noteSave(playlist.uri)
            done.insert(playlist.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlaylistCoverView: View {
    let playlist: Playlist

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var uploading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Group {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkView(url: playlist.images.url(atLeast: 640), cornerRadius: 0)
                }
            }
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            PhotosPicker(selection: $item, matching: .images) {
                Label("Choose photo", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .navigationTitle("Change cover")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if uploading {
                    ProgressView()
                } else {
                    Button("Save") { Task { await upload() } }
                        .disabled(preview == nil)
                }
            }
        }
        .onChange(of: item) { Task { await load() } }
    }

    private func load() async {
        errorMessage = nil
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        preview = Self.squared(image, side: 640)
    }

    private func upload() async {
        guard let preview, let jpeg = Self.jpeg(preview) else { return }
        uploading = true
        errorMessage = nil
        defer { uploading = false }
        if library.isSample {
            dismiss()
            return
        }
        do {
            try await library.api.uploadJPEG("playlists/\(playlist.id)/images", base64: jpeg.base64EncodedString())
            dismiss()
            Task {
                try? await Task.sleep(for: .seconds(3))
                await library.refreshImages(of: playlist)
            }
        } catch let error as APIError where error.status == 401 || error.status == 403 {
            errorMessage = "Sign out and sign in again to allow cover uploads"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func squared(_ image: UIImage, side: CGFloat) -> UIImage {
        let size = image.size
        let crop = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - crop) / 2, y: (size.height - crop) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            let scale = side / crop
            image.draw(in: CGRect(
                x: -origin.x * scale,
                y: -origin.y * scale,
                width: size.width * scale,
                height: size.height * scale
            ))
        }
    }

    private static func jpeg(_ image: UIImage) -> Data? {
        var quality: CGFloat = 0.85
        while quality > 0.15 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= 180_000 { return data }
            quality -= 0.1
        }
        return image.jpegData(compressionQuality: 0.15)
    }
}
