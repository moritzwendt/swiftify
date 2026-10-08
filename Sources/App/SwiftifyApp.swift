import SwiftUI

@main
struct SwiftifyApp: App {
    @State private var auth: AuthManager
    @State private var settings: AppSettings
    @State private var chrome = ChromeState()
    @State private var library: LibraryStore
    @State private var player: PlayerManager
    @State private var queue: QueueStore
    @State private var lyrics: LyricsStore
    @State private var warmer = CacheWarmer()

    init() {
        _ = BootLog.origin
        SystemBoot.record()
        let auth = AuthManager()
        let settings = AppSettings()
        BootLog.shared.note("settings", "appearance \(settings.appearance.rawValue), accent #\(settings.accentHex), haptics \(settings.haptics ? "on" : "off")")
        BootLog.shared.note("settings", "cache song lists \(settings.cacheLists ? "on" : "off"), images \(settings.cacheImages ? "on" : "off"), limit \(settings.imageCacheLimitMB) MB")
        Task {
            let lists = await TrackListCache.stats()
            let images = await ImageCache.shared.stats()
            let listSize = ByteCountFormatter.string(fromByteCount: Int64(lists.bytes), countStyle: .file)
            let imageSize = ByteCountFormatter.string(fromByteCount: Int64(images.bytes), countStyle: .file)
            BootLog.post("cache", "\(lists.count) song lists (\(listSize)), \(images.count) images (\(imageSize))")
        }
        let api = SpotifyAPI(auth: auth)
        let library = LibraryStore(api: api)
        let player = PlayerManager(api: api, settings: settings)
        let queue = QueueStore(api: api)
        let lyrics = LyricsStore()
        if ProcessInfo.processInfo.arguments.contains("-sample") {
            SampleData.install(library: library, player: player, queue: queue, lyrics: lyrics)
        }
        _auth = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _player = State(initialValue: player)
        _queue = State(initialValue: queue)
        _lyrics = State(initialValue: lyrics)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(library)
                .environment(player)
                .environment(queue)
                .environment(lyrics)
                .environment(settings)
                .environment(chrome)
                .environment(warmer)
                .tint(settings.accent)
                .preferredColorScheme(settings.appearance.colorScheme)
                .onChange(of: auth.isAuthenticated) { _, signedIn in
                    if !signedIn {
                        library.reset()
                        player.reset()
                        queue.reset()
                        lyrics.reset()
                        warmer.cancel()
                        TrackListCache.clear()
                        Task { await ImageCache.shared.clear() }
                    }
                }
        }
    }
}
