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

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
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
                .tint(Theme.accent)
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
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var showCreate = false
    @State private var showPlayer = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView() }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) { SearchView() }
            Tab("Your Library", systemImage: "books.vertical.fill", value: AppTab.library) { LibraryView() }
            Tab("Create", systemImage: "plus", value: AppTab.create) { Color.clear }
        }
        .tint(Theme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: player.track != nil) {
            MiniPlayer { showPlayer = true }
        }
        .onChange(of: selection) { old, new in
            if new == .create {
                selection = old
                showCreate = true
            }
        }
        .sheet(isPresented: $showCreate) { CreateSheet() }
        .sheet(isPresented: $showPlayer) { FullPlayerView() }
        .overlay(alignment: .top) { errorToast }
        .task {
            await library.load()
            player.startPolling()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                player.startPolling()
            } else {
                player.stopPolling()
            }
        }
    }

    @ViewBuilder
    private var errorToast: some View {
        if let message = player.errorMessage {
            Text(message)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { player.clearError() }
                }
        }
    }
}
