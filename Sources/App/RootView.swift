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
                LoginView()
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

struct LoginView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            LinearGradient(colors: [settings.accent.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Text("Swiftify")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Button {
                    Task { await auth.signIn() }
                } label: {
                    Text("Sign in with Spotify")
                        .font(.headline)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(auth.isSigningIn)

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

struct MainTabView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(QueueStore.self) private var queue
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(ChromeState.self) private var chrome
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var showCreate = false
    @State private var createDestination: CreateDestination?
    @State private var showPlayer = false
    @Namespace private var playerSpace

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView().createMenu(isPresented: $showCreate, onSelect: choose) }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) { SearchView().createMenu(isPresented: $showCreate, onSelect: choose) }
            Tab("Your Library", systemImage: "books.vertical.fill", value: AppTab.library) { LibraryView().createMenu(isPresented: $showCreate, onSelect: choose) }
            Tab(value: AppTab.create) {
                Color.clear
            } label: {
                createLabel
            }
        }
        .tabBarMinimizeBehavior(settings.tabBarMinimizes ? .onScrollDown : .never)
        .tabViewBottomAccessory(isEnabled: player.track != nil) {
            MiniPlayer(namespace: playerSpace) { showPlayer = true }
        }
        .sheet(item: $createDestination) { CreateDestinationSheet(destination: $0) }
        .sheet(isPresented: Binding(get: { chrome.showsSettings }, set: { chrome.showsSettings = $0 })) {
            NavigationStack { SettingsView() }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            FullPlayerView()
                .navigationTransition(.zoom(sourceID: "player", in: playerSpace))
        }
        .overlay(alignment: .top) { errorToast }
        .haptic(.success, trigger: queue.addedCount)
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

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { tab in
                if tab == .create {
                    withAnimation(.snappy) { showCreate.toggle() }
                } else {
                    selection = tab
                    if showCreate {
                        withAnimation(.snappy) { showCreate = false }
                    }
                }
            }
        )
    }

    private func choose(_ destination: CreateDestination) {
        withAnimation(.snappy) { showCreate = false }
        createDestination = destination
    }

    private var createLabel: some View {
        Label("Create", systemImage: showCreate ? "xmark" : "plus")
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
