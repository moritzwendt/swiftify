import SwiftUI

struct MiniPlayer: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var dragX: CGFloat = 0
    @State private var swipeCount = 0
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        let inline = placement == .inline
        HStack(spacing: 12) {
            ArtworkView(url: player.artworkURL(atLeast: 100), cornerRadius: 6)
                .frame(width: 36, height: 36)
                .matchedTransitionSource(id: "player", in: namespace)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.track?.name ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !inline {
                    Text(player.track?.artistLine ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await player.togglePlay() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            if !inline {
                Button {
                    Task { await player.next() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .offset(x: dragX)
        .opacity(1 - min(abs(dragX) / 200, 0.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .simultaneousGesture(swipeGesture)
        .haptic(.impact(flexibility: .soft), trigger: swipeCount)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragX = value.translation.width * 0.5
            }
            .onEnded { value in
                let distance = value.translation.width
                let horizontal = abs(distance) > abs(value.translation.height)
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { dragX = 0 }
                guard horizontal, abs(distance) > 50 else { return }
                swipeCount += 1
                Task {
                    if distance < 0 {
                        await player.next()
                    } else {
                        await player.skipBack()
                    }
                }
            }
    }
}

struct ScrubberView: View {
    @Environment(PlayerManager.self) private var player
    @State private var dragFraction: Double?

    var body: some View {
        let duration = max(player.durationMs, 1)
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let position = dragFraction.map { $0 * duration } ?? player.positionMs(at: context.date)
            let fraction = min(max(position / duration, 0), 1)
            VStack(spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white).frame(width: geometry.size.width * fraction)
                    }
                    .frame(height: dragFraction == nil ? 6 : 12)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(max(value.location.x / geometry.size.width, 0), 1)
                            }
                            .onEnded { value in
                                let target = min(max(value.location.x / geometry.size.width, 0), 1) * duration
                                dragFraction = nil
                                Task { await player.seek(to: target) }
                            }
                    )
                    .animation(.snappy(duration: 0.2), value: dragFraction == nil)
                }
                .frame(height: 20)

                HStack {
                    Text(formatTime(position))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

struct FullPlayerView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var tint: Color = .gray
    @State private var showSave = false
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var lyricsFrame = CGRect.zero
    @State private var savedWhenOpened = false

    private var isSaved: Bool {
        guard let uri = player.track?.uri else { return false }
        return player.isLiked || library.membership.isInAny(uri)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [settings.dynamicPlayerBackground ? tint.mix(with: .black, by: 0.3) : Color(white: 0.2), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)

                    Group {
                        if showLyrics {
                            LyricsView()
                                .frame(maxHeight: .infinity)
                                .onGeometryChange(for: CGRect.self) { proxy in
                                    proxy.frame(in: .named("player"))
                                } action: { frame in
                                    lyricsFrame = frame
                                }
                        } else {
                            ArtworkView(url: player.artworkURL(atLeast: 640), cornerRadius: 16)
                                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                                .scaleEffect(player.isPlaying ? 1 : 0.86)
                                .animation(.spring(duration: 0.5, bounce: 0.3), value: player.isPlaying)
                        }
                    }
                    .transition(.opacity)
                }

                Spacer(minLength: 16)

                VStack(spacing: 22) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.track?.name ?? "")
                                .font(.title2.bold())
                                .lineLimit(1)
                            Text(player.track?.artistLine ?? "")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button {
                            savedWhenOpened = isSaved
                            showSave = true
                        } label: {
                            Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 28))
                                .foregroundStyle(isSaved ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .accessibilityLabel("Save to")
                        .buttonStyle(.plain)
                    }

                    ScrubberView()

                    HStack(spacing: 20) {
                        transportButton("shuffle", active: player.shuffle) {
                            await player.toggleShuffle()
                        }
                        transportButton("backward.fill", size: .title2) {
                            await player.skipBack()
                        }
                        Button {
                            Task { await player.togglePlay() }
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                                .frame(width: 56, height: 56)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        transportButton("forward.fill", size: .title2) {
                            await player.next()
                        }
                        transportButton(
                            player.repeatMode == "track" ? "repeat.1" : "repeat",
                            active: player.repeatMode != "off"
                        ) {
                            await player.cycleRepeat()
                        }
                    }

                    HStack(spacing: 12) {
                        Label(player.deviceName ?? "No device", systemImage: "airplayaudio")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        transportButton(showLyrics ? "quote.bubble.fill" : "quote.bubble", active: showLyrics, label: "Lyrics") {
                            withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
                        }
                        transportButton("list.bullet", label: "Queue") {
                            showQueue = true
                        }
                    }
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 28)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .coordinateSpace(name: "player")
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if showLyrics, lyricsFrame.contains(value.startLocation) { return }
                    let vertical = value.translation.height
                    if vertical > 90, abs(value.translation.width) < vertical * 0.5 {
                        dismiss()
                    }
                }
        )
        .sheet(isPresented: $showSave) {
            if let track = player.track {
                SaveToSheet(track: track, fromPlus: !savedWhenOpened)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet()
        }
        .haptic(.impact, trigger: player.isPlaying)
        .haptic(.selection, trigger: showLyrics)
        .haptic(.selection, trigger: player.shuffle)
        .haptic(.selection, trigger: player.repeatMode)
        .haptic(.success, trigger: player.isLiked)
        .task(id: player.track?.uri) {
            guard settings.dynamicPlayerBackground, let url = player.artworkURL(atLeast: 100) else { return }
            if let color = await ArtworkTint.color(for: url) {
                withAnimation(.easeInOut(duration: 0.6)) { tint = color }
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        size: Font = .title3,
        active: Bool = false,
        label: String? = nil,
        action: @escaping () async -> Void
    ) -> some View {
        let button = Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(size)
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        return Group {
            if let label {
                button.accessibilityLabel(label)
            } else {
                button
            }
        }
    }
}
