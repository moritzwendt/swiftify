import AVKit
import SwiftUI

struct DeviceSheet: View {
    @Environment(PlayerManager.self) private var player
    @AppStorage("devices.helpCollapsed") private var helpCollapsed = false
    @State private var routeTrigger = 0
    @State private var switchCount = 0

    private func isCurrent(_ device: SpotifyDevice) -> Bool {
        if let id = device.id, let current = player.deviceID { return id == current }
        return device.isActive
    }

    private var others: [SpotifyDevice] {
        var rest = player.devices.filter { !isCurrent($0) }
        if let local = player.devices.localDevice, let index = rest.firstIndex(of: local) {
            rest.insert(rest.remove(at: index), at: 0)
        }
        return rest
    }

    private func name(of device: SpotifyDevice) -> String {
        device == player.devices.localDevice ? "This iPhone" : device.name
    }

    private var currentName: String {
        player.isOnThisPhone ? "This iPhone" : (player.deviceName ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Connect")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 20)
                    if player.deviceName != nil {
                        currentCard
                    }
                    help
                    list
                }
                .padding(.top, 30)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .haptic(.selection, trigger: switchCount)
        .task {
            while !Task.isCancelled {
                await player.refreshDevices()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentName)
                        .font(.system(size: 24, weight: .bold))
                        .lineLimit(1)
                    if let track = player.track {
                        Text("\(track.name) \u{2022} \(track.artistLine)")
                            .font(.system(size: 14))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.tint)
                Spacer(minLength: 0)
                DeviceGlyph(type: player.deviceType, size: 34, underlined: true)
                    .foregroundStyle(.tint)
            }
            if player.deviceSupportsVolume {
                VolumeControl()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { helpCollapsed.toggle() }
            } label: {
                HStack(spacing: 16) {
                    ConnectGlyph()
                        .frame(width: 30, height: 26)
                    Text("Don't see your device?")
                        .font(.system(size: 18))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 16, weight: .semibold))
                        .rotationEffect(.degrees(helpCollapsed ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !helpCollapsed {
                Text("Open Spotify on your device and connect it to Wi-Fi to find it here.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy) { helpCollapsed = true }
                    } label: {
                        Text("Close")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 22)
                            .frame(height: 40)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var list: some View {
        VStack(spacing: 0) {
            ForEach(others) { device in
                row(device)
            }
            if player.devices.isEmpty {
                if !player.devicesLoaded {
                    ProgressView()
                        .padding(.top, 24)
                } else if player.devicesFailed {
                    Text("Could not load devices")
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ device: SpotifyDevice) -> some View {
        Button {
            guard device.isUsable else { return }
            switchCount += 1
            Task { await player.transfer(to: device) }
        } label: {
            HStack(spacing: 18) {
                Image(systemName: device.symbol)
                    .font(.system(size: 26))
                    .frame(width: 32)
                Text(name(of: device))
                    .font(.system(size: 19))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(device.isUsable ? 1 : 0.4)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(.white.opacity(0.12))
            Button {
                routeTrigger += 1
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 22))
                    Text("Bluetooth and AirPlay")
                        .font(.system(size: 15))
                }
                .frame(maxWidth: .infinity, minHeight: 66)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(RoutePickerTrigger(trigger: routeTrigger).frame(width: 1, height: 1).opacity(0.01))
    }
}

private struct VolumeControl: View {
    @Environment(PlayerManager.self) private var player
    @State private var dragging: Double?

    var body: some View {
        let value = dragging ?? Double(player.deviceVolume ?? 0) / 100
        HStack(spacing: 14) {
            Image(systemName: "speaker")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.tint).frame(width: max(width * value, 12))
                    Capsule()
                        .fill(.white)
                        .frame(width: 5, height: 20)
                        .offset(x: min(max(width * value - 2.5, 0), width - 5))
                }
                .frame(height: 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let fraction = min(max(drag.location.x / width, 0), 1)
                            dragging = fraction
                            player.setVolume(Int((fraction * 100).rounded()))
                        }
                        .onEnded { _ in dragging = nil }
                )
            }
            .frame(height: 30)
            Image(systemName: "speaker.wave.3")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 28)
        }
    }
}

struct DeviceGlyph: View {
    let type: String?
    var size: CGFloat = 24
    var underlined = false

    var body: some View {
        VStack(spacing: size * 0.14) {
            Image(systemName: type.map { SpotifyDevice.symbol(for: $0) } ?? "airplayaudio")
                .font(.system(size: size))
            if underlined {
                Capsule()
                    .frame(width: size * 1.4, height: max(size * 0.07, 1.5))
            }
        }
    }
}

struct ConnectGlyph: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let line = max(min(width, height) * 0.085, 1.5)
            var device = Path()
            device.move(to: CGPoint(x: width * 0.46, y: height * 0.1))
            device.addLine(to: CGPoint(x: width * 0.2, y: height * 0.1))
            device.addQuadCurve(to: CGPoint(x: width * 0.06, y: height * 0.24), control: CGPoint(x: width * 0.06, y: height * 0.1))
            device.addLine(to: CGPoint(x: width * 0.06, y: height * 0.66))
            device.addQuadCurve(to: CGPoint(x: width * 0.2, y: height * 0.8), control: CGPoint(x: width * 0.06, y: height * 0.8))
            device.addLine(to: CGPoint(x: width * 0.3, y: height * 0.8))
            let speaker = Path(
                roundedRect: CGRect(x: width * 0.5, y: height * 0.14, width: width * 0.46, height: height * 0.8),
                cornerRadius: width * 0.1
            )
            let tweeter = Path(ellipseIn: CGRect(x: width * 0.73 - line * 0.7, y: height * 0.3 - line * 0.7, width: line * 1.4, height: line * 1.4))
            let woofer = Path(ellipseIn: CGRect(x: width * 0.73 - width * 0.12, y: height * 0.62 - width * 0.12, width: width * 0.24, height: width * 0.24))
            let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            context.stroke(device, with: .foreground, style: style)
            context.stroke(speaker, with: .foreground, style: style)
            context.stroke(woofer, with: .foreground, style: style)
            context.fill(tweeter, with: .foreground)
        }
    }
}

private struct RoutePickerTrigger: UIViewRepresentable {
    let trigger: Int

    final class Coordinator {
        var last = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        guard trigger != context.coordinator.last else { return }
        context.coordinator.last = trigger
        view.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
    }
}
