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

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth
    @Environment(LibraryStore.self) private var library
    @State private var devices: [SpotifyDevice] = []
    @State private var confirmClearMarks = false
    @State private var confirmClearPins = false
    @State private var confirmReset = false

    private var sortBinding: Binding<LibrarySort> {
        Binding(
            get: { LibrarySort(rawValue: settings.librarySortRaw) ?? .recents },
            set: { settings.librarySortRaw = $0.rawValue }
        )
    }

    private var deviceBinding: Binding<String?> {
        Binding(
            get: { settings.preferredDeviceID },
            set: { id in
                settings.preferredDeviceID = id
                settings.preferredDeviceName = devices.first { $0.id == id }?.name
            }
        )
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            profileSection
            appearanceSection
            Section("Home") {
                Toggle("Recently played", isOn: $settings.homeShowRecent)
                Toggle("Your top artists", isOn: $settings.homeShowTopArtists)
                Picker("Top artists range", selection: $settings.topArtistsRange) {
                    ForEach(TopArtistsRange.allCases) { Text($0.title).tag($0) }
                }
                Picker("Quick picks", selection: $settings.homeQuickCount) {
                    ForEach([4, 6, 8], id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section("Library") {
                Picker("Sort", selection: sortBinding) {
                    ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Show Liked Songs", isOn: $settings.showLikedSongsRow)
                Button("Clear download marks", role: .destructive) { confirmClearMarks = true }
                Button("Clear pins", role: .destructive) { confirmClearPins = true }
            }
            Section("Playback") {
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
                Toggle("Show explicit label", isOn: $settings.showExplicitBadge)
                Toggle("Haptics", isOn: $settings.haptics)
            }
            Section("Data") {
                Button("Clear image cache") { URLCache.shared.removeAllCachedResponses() }
                Button("Reset all settings", role: .destructive) { confirmReset = true }
            }
            Section("Account") {
                Button("Open Spotify") {
                    if let url = URL(string: "spotify://") { UIApplication.shared.open(url) }
                }
                Button("Sign out", role: .destructive) { auth.signOut() }
            }
            Section("Developer") {
                NavigationLink("Playback test") {
                    PlaybackTestView(auth: auth)
                }
            }
            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
            }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDevices() }
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

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                Group {
                    if let url = library.me?.images.url(atLeast: 120) {
                        ArtworkView(url: url, circle: true)
                    } else {
                        Text(String((library.me?.displayName ?? "S").prefix(1)).uppercased())
                            .font(.title2.bold())
                            .foregroundStyle(settings.onAccent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(settings.accent, in: Circle())
                    }
                }
                .frame(width: 56, height: 56)
                Text(library.me?.displayName ?? "Spotify")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    private var appearanceSection: some View {
        @Bindable var settings = settings
        return Section("Appearance") {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

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
            Toggle("Dynamic player background", isOn: $settings.dynamicPlayerBackground)
            Toggle("Square artwork", isOn: $settings.squareArtwork)
            Toggle("Minimize tab bar on scroll", isOn: $settings.tabBarMinimizes)
        }
    }

    private func loadDevices() async {
        if library.isSample { return }
        let response: DevicesResponse? = try? await library.api.get("me/player/devices")
        devices = response?.devices ?? []
    }
}
