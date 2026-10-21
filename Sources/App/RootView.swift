import SwiftUI

enum AppTab: Hashable {
    case home, search, library, create
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LibraryStore.self) private var library
    @State private var coverMode: CoverMode? = {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "settings.verboseBoot") { return .verbose }
        if defaults.object(forKey: "settings.launchCover") as? Bool ?? true { return .logo }
        return nil
    }()

    var body: some View {
        ZStack {
            if auth.isAuthenticated || library.isSample {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
            if let coverMode {
                LaunchCover(mode: coverMode) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { self.coverMode = nil }
                }
                .zIndex(1)
            }
        }
        .task {
            if coverMode == nil {
                try? await Task.sleep(for: .seconds(3))
                BootLog.shared.finish()
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LyricsStore.self) private var lyrics
    @Environment(CacheWarmer.self) private var warmer
    @Environment(PlayerManager.self) private var player
    @Environment(QueueStore.self) private var queue
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(ChromeState.self) private var chrome
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var previousTab: AppTab = .home
    @State private var createSnapshot: UIImage?
    @State private var createDestination: CreateDestination?
    @State private var createClosing = false

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView().background(TabProbe()) }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) { SearchView().background(TabProbe()) }
            Tab("Your Library", systemImage: "books.vertical.fill", value: AppTab.library) { LibraryView().background(TabProbe()) }
            Tab(value: AppTab.create) {
                CreateTabContent(
                    snapshot: createSnapshot,
                    isMenuVisible: createDestination == nil && !createClosing,
                    onClose: closeCreate,
                    onSelect: choose
                )
            } label: {
                createLabel
            }
        }
        .tabBarMinimizeBehavior(settings.tabBarMinimizes ? .onScrollDown : .never)
        .tabViewBottomAccessory(isEnabled: player.track != nil) {
            MiniPlayer(onTap: openPlayer)
        }
        .sheet(item: $createDestination, onDismiss: finishCreate) { CreateDestinationSheet(destination: $0) }
        .onChange(of: settings.createOpensSpotify, initial: true) { _, opensSpotify in
            TabSnapshot.isEnabled = !opensSpotify
        }
        .sheet(isPresented: Binding(get: { chrome.showsSettings }, set: { chrome.showsSettings = $0 })) {
            NavigationStack { SettingsView() }
        }
        .overlay(alignment: .top) { errorToast }
        .haptic(.success, trigger: queue.addedCount)
        .onChange(of: player.isPlaying ? player.contextURI : nil) { _, uri in
            if let uri { library.noteRecent(uri) }
        }
        .task {
            BootLog.post("player", "polling started")
            await library.load()
            player.startPolling()
            await library.membership.scan(library.editablePlaylists)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                player.startPolling()
                Task { await player.resumePendingPlayback() }
            } else {
                player.stopPolling()
                if phase == .background { player.appDidEnterBackground() }
            }
        }
    }

    private func openPlayer() {
        PlayerPresenter.shared.present(
            FullPlayerView()
                .environment(auth)
                .environment(library)
                .environment(player)
                .environment(queue)
                .environment(lyrics)
                .environment(settings)
                .environment(chrome)
                .environment(warmer)
                .tint(settings.accent)
        )
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { tab in
                if tab == .create {
                    if selection == .create {
                        closeCreate()
                    } else if settings.createOpensSpotify {
                        SpotifyApp.open()
                    } else {
                        previousTab = selection
                        createSnapshot = TabSnapshot.latest
                        selection = .create
                    }
                } else {
                    createClosing = false
                    selection = tab
                }
            }
        )
    }

    private func closeCreate() {
        guard selection == .create, !createClosing else { return }
        createClosing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            finishCreate()
        }
    }

    private func finishCreate() {
        createClosing = false
        guard selection == .create else { return }
        selection = previousTab
        createSnapshot = nil
    }

    private func choose(_ destination: CreateDestination) {
        createDestination = destination
    }

    @ViewBuilder
    private var createLabel: some View {
        if settings.createOpensSpotify {
            Label {
                Text("Spotify")
            } icon: {
                Image("SpotifyLogo")
            }
        } else {
            Label("Create", systemImage: selection == .create ? "xmark" : "plus")
        }
    }

    @ViewBuilder
    private var errorToast: some View {
        if let message = player.errorMessage ?? queue.message ?? library.message {
            Text(message)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: "\(message)|\(queue.addedCount)") {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation {
                        player.clearError()
                        queue.clearMessage()
                        library.clearMessage()
                    }
                }
        }
    }
}
