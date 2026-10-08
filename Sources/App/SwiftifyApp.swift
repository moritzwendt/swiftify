import SwiftUI

@main
struct SwiftifyApp: App {
    @State private var auth: AuthManager
    @State private var settings: AppSettings
    @State private var chrome = ChromeState()
    @State private var library: LibraryStore
    @State private var player: PlayerManager
    @State private var queue: QueueStore

    init() {
        let auth = AuthManager()
        let settings = AppSettings()
        let api = SpotifyAPI(auth: auth)
        let library = LibraryStore(api: api)
        let player = PlayerManager(api: api, settings: settings)
        let queue = QueueStore(api: api)
        if ProcessInfo.processInfo.arguments.contains("-sample") {
            SampleData.install(library: library, player: player, queue: queue)
        }
        _auth = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _player = State(initialValue: player)
        _queue = State(initialValue: queue)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(library)
                .environment(player)
                .environment(queue)
                .environment(settings)
                .environment(chrome)
                .tint(settings.accent)
                .preferredColorScheme(settings.appearance.colorScheme)
                .onChange(of: auth.isAuthenticated) { _, signedIn in
                    if !signedIn {
                        library.reset()
                        player.reset()
                        queue.reset()
                    }
                }
        }
    }
}
