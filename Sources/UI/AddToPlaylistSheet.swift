import SwiftUI

struct AddToPlaylistSheet: View {
    let title: String
    let imageURL: URL?
    let uris: [String]
    var excludingID: String?

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
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
            .navigationTitle("Add to")
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
                Button("Create") { Task { await create() } }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .haptic(.success, trigger: done.count)
        }
        .presentationDetents([.medium, .large])
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
                    .symbolEffect(.bounce, value: done.contains(playlist.id))
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
