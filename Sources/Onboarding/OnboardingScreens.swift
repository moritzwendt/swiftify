import SwiftUI

struct OnboardingDashboardScreen: View {
    @Environment(\.openURL) private var openURL
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(title: "Create a Spotify app") {
            VStack(spacing: 14) {
                OnboardingHero(symbol: "plus.app.fill")
                OnboardingCard {
                    OnboardingInfoRow(
                        symbol: "crown.fill",
                        color: .orange,
                        title: "Spotify Premium",
                        detail: "A Premium account is required."
                    )
                }
                OnboardingCard {
                    OnboardingInfoRow(
                        symbol: "safari.fill",
                        color: .blue,
                        title: "Developer Dashboard",
                        detail: "Log in and tap Create app."
                    )
                }
            }
        } actions: {
            Button {
                openURL(SpotifyConfig.dashboardURL)
            } label: {
                HStack(spacing: 8) {
                    Text("Open Dashboard")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .buttonStyle(OnboardingOutlineButtonStyle())

            Button("Continue", action: onContinue)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }
}

struct OnboardingAppSettingsScreen: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(title: "Add these settings") {
            VStack(spacing: 14) {
                OnboardingHero(symbol: "slider.horizontal.3")
                OnboardingCard(padding: 0) {
                    VStack(spacing: 0) {
                        OnboardingFormRow(label: "App name and description", value: "Anything you like")
                        OnboardingDivider(inset: 16)
                        OnboardingCopyRow(label: "Redirect URI, tap Add after pasting", value: SpotifyConfig.redirectURI)
                        OnboardingDivider(inset: 16)
                        OnboardingFormRow(label: "APIs", value: "Check Web API", emphasized: true)
                    }
                }
                OnboardingCard {
                    OnboardingInfoRow(
                        symbol: "checkmark.circle.fill",
                        color: .green,
                        title: "Save",
                        detail: "Tap Save at the bottom of the form."
                    )
                }
            }
        } actions: {
            Button("Continue", action: onContinue)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }
}

struct OnboardingClientIDScreen: View {
    @Environment(AuthManager.self) private var auth
    @State private var clientID = ""
    @FocusState private var focused: Bool
    let showsRedirect: Bool
    let onContinue: () -> Void

    private var isValid: Bool { AuthManager.isValidClientID(clientID) }

    var body: some View {
        OnboardingScaffold(title: "Paste your Client ID") {
            VStack(spacing: 14) {
                OnboardingHero(symbol: "key.fill")
                OnboardingCard {
                    OnboardingInfoRow(
                        symbol: "key.fill",
                        color: .indigo,
                        title: "Client ID",
                        detail: "Open your app, tap Settings and copy the Client ID."
                    )
                }

                HStack(spacing: 10) {
                    TextField("", text: $clientID, prompt: Text("Client ID").foregroundColor(.white.opacity(0.3)))
                        .font(.system(size: 14, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { submit() }
                    if isValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "34C759"))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Button {
                            if let value = UIPasteboard.general.string {
                                clientID = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(OnboardingPressStyle())
                    }
                }
                .onboardingField(focused: focused)
                .animation(.smooth(duration: 0.2), value: isValid)

                if showsRedirect {
                    OnboardingCard(padding: 0) {
                        OnboardingCopyRow(label: "Add this Redirect URI to your app", value: SpotifyConfig.redirectURI)
                    }
                }
            }
        } actions: {
            Button("Continue", action: submit)
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!isValid)
        }
        .onAppear { clientID = auth.clientID }
    }

    private func submit() {
        guard isValid else { return }
        focused = false
        if auth.saveClientID(clientID) { onContinue() }
    }
}

struct OnboardingAppearanceScreen: View {
    @Environment(AppSettings.self) private var settings
    let onContinue: () -> Void

    private var previewScheme: ColorScheme {
        switch settings.appearance {
        case .light: .light
        case .dark: .dark
        case .system: UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
    }

    private func symbol(for mode: AppearanceMode) -> String {
        switch mode {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var body: some View {
        OnboardingScaffold(title: "Choose your look") {
            VStack(spacing: 14) {
                OnboardingThemePreview(scheme: previewScheme, accent: settings.accent)

                HStack(spacing: 10) {
                    ForEach(AppearanceMode.allCases) { mode in
                        OnboardingChoiceCard(
                            title: mode.title,
                            symbol: symbol(for: mode),
                            isSelected: settings.appearance == mode
                        ) {
                            settings.appearance = mode
                        }
                    }
                }

                OnboardingCard {
                    HStack(spacing: 0) {
                        ForEach(AccentPreset.all) { preset in
                            Button {
                                withAnimation(.smooth(duration: 0.3)) { settings.accentHex = preset.hex }
                            } label: {
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Circle()
                                            .stroke(.white, lineWidth: 2)
                                            .padding(-4)
                                            .opacity(settings.accentHex == preset.hex ? 1 : 0)
                                    }
                                    .animation(.smooth(duration: 0.25), value: settings.accentHex)
                            }
                            .buttonStyle(OnboardingPressStyle())
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(preset.name)
                        }
                    }
                }
            }
        } actions: {
            Button("Continue", action: onContinue)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
        .haptic(.selection, trigger: settings.appearance)
        .haptic(.selection, trigger: settings.accentHex)
    }
}

struct OnboardingLayoutScreen: View {
    @Environment(AppSettings.self) private var settings
    let onContinue: () -> Void

    var body: some View {
        @Bindable var settings = settings
        OnboardingScaffold(title: "Make it yours") {
            OnboardingCard(padding: 0) {
                VStack(spacing: 0) {
                    OnboardingToggleRow(title: "Haptics", symbol: "iphone.radiowaves.left.and.right", color: .pink, isOn: $settings.haptics)
                    OnboardingDivider()
                    OnboardingToggleRow(title: "Minimize tab bar", symbol: "rectangle.bottomthird.inset.filled", color: .blue, isOn: $settings.tabBarMinimizes)
                    OnboardingDivider()
                    OnboardingToggleRow(title: "Smart playlists", symbol: "sparkles", color: .purple, isOn: $settings.showSmartPlaylists)
                    OnboardingDivider()
                    OnboardingToggleRow(title: "Library as grid", symbol: "square.grid.2x2.fill", color: .orange, isOn: $settings.libraryGrid)
                    OnboardingDivider()
                    OnboardingToggleRow(title: "Explicit badge", symbol: "e.square.fill", color: .gray, isOn: $settings.showExplicitBadge)
                }
            }
        } actions: {
            Text("You can change this later in Settings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button("Continue", action: onContinue)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }
}

struct OnboardingCacheScreen: View {
    @Environment(AppSettings.self) private var settings
    let onContinue: () -> Void

    private static let limits = [100, 300, 500, 1000, 2000]

    private func limitTitle(_ megabytes: Int) -> String {
        megabytes >= 1000 ? "\(megabytes / 1000) GB" : "\(megabytes) MB"
    }

    var body: some View {
        @Bindable var settings = settings
        OnboardingScaffold(title: "Keep it fast") {
            VStack(spacing: 14) {
                OnboardingCard(padding: 0) {
                    VStack(spacing: 0) {
                        OnboardingToggleRow(title: "Cache song lists", symbol: "music.note.list", color: .teal, isOn: $settings.cacheLists)
                        OnboardingDivider()
                        OnboardingToggleRow(title: "Cache images", symbol: "photo.fill", color: .teal, isOn: $settings.cacheImages)
                        OnboardingDivider()
                        OnboardingToggleRow(title: "Preload images", symbol: "arrow.down.circle.fill", color: .teal, isOn: $settings.preloadImages)
                            .disabled(!settings.cacheImages)
                            .opacity(settings.cacheImages ? 1 : 0.4)
                    }
                }

                OnboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image cache limit")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        HStack(spacing: 8) {
                            ForEach(Self.limits, id: \.self) { limit in
                                OnboardingChip(title: limitTitle(limit), isSelected: settings.imageCacheLimitMB == limit) {
                                    settings.imageCacheLimitMB = limit
                                }
                            }
                        }
                    }
                    .disabled(!settings.cacheImages)
                    .opacity(settings.cacheImages ? 1 : 0.4)
                }
                .animation(.smooth(duration: 0.25), value: settings.cacheImages)
            }
        } actions: {
            Text("You can change this later in Settings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button("Continue", action: onContinue)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
        .haptic(.selection, trigger: settings.imageCacheLimitMB)
    }
}

struct OnboardingSignInScreen: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    private var maskedClientID: String {
        let id = auth.clientID
        guard id.count > 8 else { return id }
        return "\(id.prefix(4))\u{2026}\(id.suffix(4))"
    }

    private var appearanceSummary: String {
        let accent = AccentPreset.all.first { $0.hex == settings.accentHex }?.name ?? "Custom"
        return "\(settings.appearance.title), \(accent)"
    }

    private var cacheSummary: String {
        switch (settings.cacheLists, settings.cacheImages) {
        case (true, true): "Song lists and images"
        case (true, false): "Song lists"
        case (false, true): "Images"
        case (false, false): "Off"
        }
    }

    var body: some View {
        OnboardingScaffold(title: "Ready to go", banner: auth.errorMessage) {
            VStack(spacing: 14) {
                OnboardingHero(symbol: "checkmark.seal.fill")
                OnboardingCard(padding: 0) {
                    VStack(spacing: 0) {
                        OnboardingFormRow(label: "Client ID", value: maskedClientID)
                        OnboardingDivider(inset: 16)
                        OnboardingFormRow(label: "Appearance", value: appearanceSummary)
                        OnboardingDivider(inset: 16)
                        OnboardingFormRow(label: "Cache", value: cacheSummary)
                    }
                }
            }
        } actions: {
            Button {
                Task { await auth.signIn() }
            } label: {
                HStack(spacing: 10) {
                    if auth.isSigningIn {
                        ProgressView().tint(.black)
                    }
                    Text("Sign in with Spotify")
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(auth.isSigningIn)
        }
    }
}
