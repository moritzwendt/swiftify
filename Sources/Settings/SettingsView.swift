import SwiftUI

struct ProfileButton: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings

    private var initial: String {
        String((library.me?.displayName ?? "S").prefix(1)).uppercased()
    }

    var body: some View {
        NavigationLink(value: Route.settings) {
            if let url = library.me?.images.url(atLeast: 64) {
                ArtworkView(url: url, circle: true)
                    .frame(width: 32, height: 32)
            } else {
                Text(initial)
                    .font(.subheadline.bold())
                    .foregroundStyle(settings.onAccent)
                    .frame(width: 32, height: 32)
                    .background(settings.accent, in: Circle())
            }
        }
        .accessibilityLabel("Settings")
    }
}

private struct SettingsRow<Destination: View>: View {
    let title: String
    let symbol: String
    let color: Color
    var value: String?
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: color)
                Text(title)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth
    @Environment(LibraryStore.self) private var library

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Group {
                        if let url = library.me?.images.url(atLeast: 160) {
                            ArtworkView(url: url, circle: true)
                        } else {
                            Text(String((library.me?.displayName ?? "S").prefix(1)).uppercased())
                                .font(.largeTitle.bold())
                                .foregroundStyle(settings.onAccent)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(settings.accent, in: Circle())
                        }
                    }
                    .frame(width: 72, height: 72)
                    Text(library.me?.displayName ?? "Spotify")
                        .font(.title2.weight(.semibold))
                }
                .padding(.vertical, 6)
            }

            Section {
                SettingsRow(title: "Appearance", symbol: "paintbrush.fill", color: .purple, value: settings.appearance.title) {
                    AppearanceSettings()
                }
                SettingsRow(title: "Home", symbol: "house.fill", color: .blue) {
                    HomeSettings()
                }
                SettingsRow(title: "Library", symbol: "books.vertical.fill", color: .orange) {
                    LibrarySettings()
                }
                SettingsRow(title: "Playback", symbol: "play.circle.fill", color: .pink, value: settings.preferredDeviceName ?? "Automatic") {
                    PlaybackSettings()
                }
            }

            Section {
                SettingsRow(title: "Storage and reset", symbol: "internaldrive.fill", color: .gray) {
                    StorageSettings()
                }
            }

            Section {
                Button {
                    if let url = URL(string: "spotify://") { UIApplication.shared.open(url) }
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "arrow.up.forward.app.fill", color: .green)
                        Text("Open Spotify")
                    }
                }
                .tint(.primary)
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "rectangle.portrait.and.arrow.right.fill", color: .red)
                        Text("Sign out")
                    }
                }
            }

            Section {
                SettingsRow(title: "Playback test", symbol: "hammer.fill", color: .indigo) {
                    PlaybackTestView(auth: auth)
                        .hidesBottomBars()
                }
            }

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .hidesBottomBars()
    }
}

struct AppearanceSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Theme") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Accent color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                    ForEach(AccentPreset.all) { preset in
                        Button {
                            settings.accentHex = preset.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if settings.accentHex == preset.hex {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(Color(hex: preset.hex).isLight ? .black : .white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 4)

                ColorPicker(
                    "Custom color",
                    selection: Binding(
                        get: { settings.accent },
                        set: { settings.accentHex = $0.hexString }
                    ),
                    supportsOpacity: false
                )
            }

            Section("Interface") {
                Toggle("Dynamic player background", isOn: $settings.dynamicPlayerBackground)
                Toggle("Square artwork", isOn: $settings.squareArtwork)
                Toggle("Minimize tab bar on scroll", isOn: $settings.tabBarMinimizes)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .hidesBottomBars()
    }
}

struct HomeSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Sections") {
                Toggle("Recently played", isOn: $settings.homeShowRecent)
                Toggle("Your top artists", isOn: $settings.homeShowTopArtists)
            }
            Section("Content") {
                Picker("Top artists range", selection: $settings.topArtistsRange) {
                    ForEach(TopArtistsRange.allCases) { Text($0.title).tag($0) }
                }
                Picker("Quick picks", selection: $settings.homeQuickCount) {
                    ForEach([4, 6, 8], id: \.self) { Text("\($0)").tag($0) }
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .hidesBottomBars()
    }
}

struct LibrarySettings: View {
    @Environment(AppSettings.self) private var settings

    private var sortBinding: Binding<LibrarySort> {
        Binding(
            get: { LibrarySort(rawValue: settings.librarySortRaw) ?? .recents },
            set: { settings.librarySortRaw = $0.rawValue }
        )
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Sort", selection: sortBinding) {
                    ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Grid layout", isOn: $settings.libraryGrid)
                Toggle("Show Liked Songs", isOn: $settings.showLikedSongsRow)
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .hidesBottomBars()
    }
}

struct PlaybackSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @State private var devices: [SpotifyDevice] = []

    private var deviceBinding: Binding<String?> {
        Binding(
            get: { settings.preferredDeviceID },
            set: { id in
                settings.preferredDeviceID = id
                settings.preferredDeviceName = devices.first { $0.id == id }?.name
            }
        )
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Device", selection: deviceBinding) {
                    Text("Automatic").tag(String?.none)
                    if let id = settings.preferredDeviceID, !devices.contains(where: { $0.id == id }) {
                        Text(settings.preferredDeviceName ?? "Saved device").tag(String?.some(id))
                    }
                    ForEach(devices) { device in
                        if let id = device.id {
                            Text(device.name).tag(String?.some(id))
                        }
                    }
                }
                Picker("Previous button", selection: $settings.previousRestartSeconds) {
                    Text("Previous song").tag(0)
                    Text("Restart after 3 seconds").tag(3)
                    Text("Restart after 5 seconds").tag(5)
                    Text("Restart after 10 seconds").tag(10)
                }
            }
            Section {
                Toggle("Show explicit label", isOn: $settings.showExplicitBadge)
                Toggle("Haptics", isOn: $settings.haptics)
            }
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .hidesBottomBars()
        .task { await loadDevices() }
    }

    private func loadDevices() async {
        if library.isSample { return }
        let response: DevicesResponse? = try? await library.api.get("me/player/devices")
        devices = response?.devices ?? []
    }
}

struct StorageSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @State private var confirmClearMarks = false
    @State private var confirmClearPins = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle("Cache song lists", isOn: $settings.cacheLists)
                Toggle("Cache images", isOn: $settings.cacheImages)
            }
            Section {
                Button("Clear song list cache") { TrackListCache.clear() }
                Button("Clear image cache") {
                    URLCache.shared.removeAllCachedResponses()
                    Task { await ImageCache.shared.clear() }
                }
                Button("Clear download marks", role: .destructive) { confirmClearMarks = true }
                Button("Clear pins", role: .destructive) { confirmClearPins = true }
            }
            Section {
                Button("Reset all settings", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Storage and reset")
        .navigationBarTitleDisplayMode(.inline)
        .hidesBottomBars()
        .confirmationDialog("Clear download marks", isPresented: $confirmClearMarks, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { library.clearDownloaded() }
        }
        .confirmationDialog("Clear pins", isPresented: $confirmClearPins, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { library.clearPins() }
        }
        .confirmationDialog("Reset all settings", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { settings.reset() }
        }
    }
}
