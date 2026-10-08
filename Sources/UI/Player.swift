import SwiftUI

struct MiniPlayer: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var dragX: CGFloat = 0
    @State private var swipeCount = 0
    let onTap: () -> Void

    var body: some View {
        let inline = placement == .inline
        HStack(spacing: 12) {
            ArtworkView(url: player.artworkURL(atLeast: 100), cornerRadius: 6)
                .frame(width: 36, height: 36)
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
    @Environment(\.dismiss) private var dismiss
    @State private var tint: Color = .gray
    @State private var dragOffset: CGFloat = 0
    @State private var screenHeight: CGFloat = 900

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

                    ArtworkView(url: player.artworkURL(atLeast: 640), cornerRadius: 16)
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                        .scaleEffect(player.isPlaying ? 1 : 0.86)
                        .animation(.spring(duration: 0.5, bounce: 0.3), value: player.isPlaying)
                }
                .contentShape(Rectangle())
                .gesture(dismissGesture)

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
                            Task { await player.toggleLike() }
                        } label: {
                            Image(systemName: player.isLiked ? "heart.fill" : "heart")
                                .font(.title3)
                                .foregroundStyle(player.isLiked ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
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

                    Label(player.deviceName ?? "No device", systemImage: "airplayaudio")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 28)
            .offset(y: dragOffset)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { screenHeight = geometry.size.height }
            }
        }
        .haptic(.impact, trigger: player.isPlaying)
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

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 400 {
                    withAnimation(.easeIn(duration: 0.22)) {
                        dragOffset = screenHeight
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { dismiss() }
                    }
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { dragOffset = 0 }
                }
            }
    }

    private func transportButton(
        _ symbol: String,
        size: Font = .title3,
        active: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(size)
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}
