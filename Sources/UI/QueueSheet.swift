import SwiftUI

struct QueueSheet: View {
    @Environment(PlayerManager.self) private var player
    @Environment(QueueStore.self) private var queue
    @Environment(LibraryStore.self) private var library

    private var nowPlaying: Track? { queue.current ?? player.track }

    private var queued: [Track] { Array(queue.upcoming.prefix(queue.queuedCount)) }

    private var following: [Track] { Array(queue.upcoming.dropFirst(queue.queuedCount)) }

    private var followingTitle: String {
        guard let name = contextName else { return "Next up" }
        return "Next from \(name)"
    }

    private var contextName: String? {
        if player.isActive(context: LikedSongsView.contextKey) { return "Liked Songs" }
        guard let uri = player.contextURI else { return nil }
        if let playlist = library.playlists.first(where: { $0.uri == uri }) { return playlist.name }
        if let album = library.albums.first(where: { $0.album.uri == uri }) { return album.album.name }
        if let artist = library.artists.first(where: { $0.uri == uri }) { return artist.name }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let track = nowPlaying {
                        QueueRow(track: track, isCurrent: true)
                    }
                    if queued.isEmpty {
                        rows(following, offset: 0)
                    } else {
                        sectionTitle("Next in queue")
                        rows(queued, offset: 0)
                        if !following.isEmpty {
                            sectionTitle(followingTitle)
                            rows(following, offset: queued.count)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .overlay { placeholder }
            .overlay(alignment: .bottom) { reshuffleButton }
            controls
        }
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .task(id: player.track?.uri) {
            guard !player.isSkipping else { return }
            await queue.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Queue")
                .font(.system(size: 22, weight: .bold))
            if let contextName {
                Text("Playing from \u{201C}\(contextName)\u{201D}")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 14)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func rows(_ tracks: [Track], offset: Int) -> some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
            QueueRow(track: track, isCurrent: false)
                .contentShape(Rectangle())
                .onTapGesture { skip(to: track, steps: offset + index + 1) }
        }
    }

    private func skip(to track: Track, steps: Int) {
        queue.advance(by: steps)
        Task {
            await player.skipAhead(to: track, steps: steps)
            if !queue.isSample { await queue.refresh() }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if nowPlaying == nil && queue.upcoming.isEmpty {
            if queue.loadFailed {
                ContentUnavailableView("Could not load the queue", systemImage: "wifi.exclamationmark")
            } else if queue.hasLoaded {
                ContentUnavailableView("Nothing is playing", systemImage: "list.bullet")
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var reshuffleButton: some View {
        if player.shuffle && nowPlaying != nil {
            Button {
                Task {
                    await player.reshuffle()
                    if queue.isSample {
                        queue.shuffleSample()
                    } else {
                        await queue.refresh()
                    }
                }
            } label: {
                Text("Reshuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            control("Shuffle", symbol: "shuffle", active: player.shuffle) {
                await player.toggleShuffle()
            }
            control(
                "Repeat",
                symbol: player.repeatMode == "track" ? "repeat.1" : "repeat",
                active: player.repeatMode != "off"
            ) {
                await player.cycleRepeat()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func control(
        _ title: String,
        symbol: String,
        active: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 15))
            }
            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct QueueRow: View {
    @Environment(PlayerManager.self) private var player
    @Environment(AppSettings.self) private var settings
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(url: track.album?.images.url(atLeast: 100), cornerRadius: 7)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 17))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if settings.showExplicitBadge && track.explicit == true {
                        Image(systemName: "e.square.fill")
                            .font(.system(size: 15))
                    }
                    Text(track.artistLine)
                        .font(.system(size: 15))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Button {
                    Task { await player.togglePlay() }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(.white, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
