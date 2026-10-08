import SwiftUI

@main
struct SwiftifyApp: App {
    @State private var auth: AuthManager
    @State private var library: LibraryStore
    @State private var player: PlayerManager

    init() {
        let auth = AuthManager()
        let api = SpotifyAPI(auth: auth)
        let library = LibraryStore(api: api)
        let player = PlayerManager(api: api)
        if ProcessInfo.processInfo.arguments.contains("-sample") {
            SampleData.install(library: library, player: player)
        }
        _auth = State(initialValue: auth)
        _library = State(initialValue: library)
        _player = State(initialValue: player)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(library)
                .environment(player)
                .onChange(of: auth.isAuthenticated) { _, signedIn in
                    if !signedIn {
                        library.reset()
                        player.reset()
                    }
                }
        }
    }
}
