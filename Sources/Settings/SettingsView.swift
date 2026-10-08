import SwiftUI

struct ProfileButton: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    private var initial: String {
        String((library.me?.displayName ?? "S").prefix(1)).uppercased()
    }

    var body: some View {
        Button {
            showSettings = true
        } label: {
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
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
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

                Section("Appearance") {
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
                }

                Section("Account") {
                    Button("Open Spotify") {
                        if let url = URL(string: "spotify://") { UIApplication.shared.open(url) }
                    }
                    Button("Sign out", role: .destructive) {
                        dismiss()
                        auth.signOut()
                    }
                }

                Section("Developer") {
                    NavigationLink("Playback test") {
                        PlaybackTestView(auth: auth)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
