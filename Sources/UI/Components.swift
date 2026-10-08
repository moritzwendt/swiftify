import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum Route: Hashable {
    case playlist(Playlist)
    case album(Album)
    case artist(Artist)
    case likedSongs
}

func formatTime(_ ms: Double) -> String {
    let seconds = max(0, Int(ms / 1000))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var circle = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: circle ? "person.fill" : "music.note")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
            }
            .clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

struct LikedArtwork: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
    }
}

struct MediaRow: View {
    let imageURL: URL?
    let title: String
    let subtitle: String
    var circle = false
    var liked = false
    var badge = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if liked {
                    LikedArtwork()
                } else {
                    ArtworkView(url: imageURL, circle: circle)
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if badge {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}

struct TrackRow: View {
    let track: Track
    var number: Int?
    var artworkURL: URL?
    @Environment(PlayerManager.self) private var player

    private var isCurrent: Bool { player.track?.uri == track.uri }

    var body: some View {
        HStack(spacing: 12) {
            if let artworkURL {
                ArtworkView(url: artworkURL, cornerRadius: 6)
                    .frame(width: 48, height: 48)
            } else if let number {
                Text("\(number)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(track.artistLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isCurrent && player.isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ShelfCard: View {
    let imageURL: URL?
    let title: String
    let subtitle: String
    var circle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: imageURL, cornerRadius: 10, circle: circle)
                .frame(width: 140, height: 140)
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 140, alignment: circle ? .center : .leading)
        .multilineTextAlignment(circle ? .center : .leading)
    }
}

struct PlayButton: View {
    @Environment(AppSettings.self) private var settings
    var title = "Play"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(settings.onAccent)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

enum ArtworkTint {
    private static let cache = NSCache<NSURL, UIColor>()

    static func color(for url: URL) async -> Color? {
        if let cached = cache.object(forKey: url as NSURL) { return Color(cached) }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = CIImage(data: data) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let color = UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        cache.setObject(color, forKey: url as NSURL)
        return Color(color)
    }
}

extension View {
    func appDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .playlist(let playlist): PlaylistDetailView(playlist: playlist)
            case .album(let album): AlbumDetailView(album: album)
            case .artist(let artist): ArtistDetailView(artist: artist)
            case .likedSongs: LikedSongsView()
            }
        }
    }
}
