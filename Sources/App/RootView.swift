import SwiftUI

enum AppTab: Hashable {
    case home, search, library, create
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if auth.isAuthenticated || library.isSample {
            MainTabView()
        } else {
            LoginView()
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
    @State private var showPlayer = false
    @Namespace private var playerSpace

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView() }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) { SearchView() }
            Tab("Your Library", systemImage: "books.vertical.fill", value: AppTab.library) { LibraryView() }
            Tab("Create", systemImage: "plus", value: AppTab.create) { Color.clear }
        }
        .tabBarMinimizeBehavior(settings.tabBarMinimizes ? .onScrollDown : .never)
        .tabViewBottomAccessory(isEnabled: player.track != nil) {
            MiniPlayer(namespace: playerSpace) { showPlayer = true }
        }
        .onChange(of: selection) { old, new in
            if new == .create {
                selection = old
                showCreate = true
            }
        }
        .sheet(isPresented: $showCreate) { CreateSheet() }
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
