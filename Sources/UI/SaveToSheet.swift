import SwiftUI

struct SaveToSheet: View {
    let track: Track
    var autoLike = false

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var liked: Bool?
    @State private var pending: Set<String> = []
    @State private var errorMessage: String?
    @State private var scanDone = false

    private var membership: MembershipStore { library.membership }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .listRowSeparator(.hidden)
                }

                Button {
                    Task { await toggleLiked() }
                } label: {
                    HStack(spacing: 12) {
                        LikedArtwork()
                            .frame(width: 48, height: 48)
                        Text("Liked Songs")
                        Spacer(minLength: 0)
                        status(isOn: liked, isBusy: liked == nil || pending.contains("liked"), unknown: false, finished: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)

                ForEach(library.editablePlaylists) { playlist in
                    Button {
                        Task { await toggle(playlist) }
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: playlist.images.url(atLeast: 100), cornerRadius: 6)
                                .frame(width: 48, height: 48)
                            Text(playlist.name)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            status(
                                isOn: membership.contains(playlist.id, uri: track.uri),
                                isBusy: membership.scanning.contains(playlist.id) || pending.contains(playlist.id),
                                unknown: membership.skipped.contains(playlist.id)
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .disabled(membership.scanning.contains(playlist.id))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Save to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .haptic(.selection, trigger: liked)
            .task { await prepare() }
            .task {
                await membership.scan(library.editablePlaylists)
                scanDone = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func status(isOn: Bool?, isBusy: Bool, unknown: Bool = false, finished: Bool = false) -> some View {
        if isBusy || (isOn == nil && !unknown && !scanDone && !finished) {
            ProgressView()
        } else if isOn == true {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        } else {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func prepare() async {
        if library.isSample {
            liked = false
            if autoLike { await toggleLiked() }
            return
        }
        let result: [Bool]? = try? await library.api.get("me/library/contains", query: ["uris": track.uri])
        liked = result?.first ?? false
        if autoLike, liked == false { await toggleLiked() }
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
