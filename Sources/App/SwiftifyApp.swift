import SwiftUI

@main
struct SwiftifyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth: AuthManager
    @State private var settings: AppSettings
    @State private var chrome = ChromeState()
    @State private var library: LibraryStore
    @State private var player: PlayerManager
    @State private var remote: AppRemoteConnection

    init() {
        let auth = AuthManager()
        let settings = AppSettings()
        let api = SpotifyAPI(auth: auth)
        let library = LibraryStore(api: api)
        let player = PlayerManager(api: api, settings: settings)
        let isSample = ProcessInfo.processInfo.arguments.contains("-sample")
        let remote = AppRemoteConnection(
            client: SpotifyAppRemoteClient(
                clientID: SpotifyConfig.clientID,
                redirectURL: URL(string: SpotifyConfig.redirectURI)!
            ),
            tokenProvider: {
                if isSample { return "sample" }
                return try await auth.validAccessToken()
            },
            diagnostics: DiagnosticsLog(fileURL: DiagnosticsLog.defaultFileURL)
        )
        if isSample {
            SampleData.install(library: library, player: player)
        }
        _auth = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _player = State(initialValue: player)
        _remote = State(initialValue: remote)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(library)
                .environment(player)
                .environment(settings)
                .environment(chrome)
                .environment(remote)
                .tint(settings.accent)
                .preferredColorScheme(settings.appearance.colorScheme)
                .onOpenURL { remote.handleOpenURL($0) }
                .onChange(of: scenePhase) { _, phase in
                    remote.scenePhaseChanged(phase)
                }
                .task { remote.scenePhaseChanged(scenePhase) }
                .onChange(of: auth.isAuthenticated) { _, signedIn in
                    if !signedIn {
                        library.reset()
                        player.reset()
                        remote.reset()
                    }
                }
        }
    }
}
