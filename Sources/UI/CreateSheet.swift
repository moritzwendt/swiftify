import SwiftUI

struct SpotifyLink {
    let type: String
    let id: String

    var uri: String { "spotify:\(type):\(id)" }
    var isPlayableTrack: Bool { type == "track" || type == "episode" }

    private static let types: Set<String> = ["track", "album", "playlist", "artist", "episode", "show"]

    static func parse(_ text: String) -> SpotifyLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("spotify:") {
            let parts = trimmed.split(separator: ":").map(String.init)
            guard parts.count >= 3, types.contains(parts[1]) else { return nil }
            return SpotifyLink(type: parts[1], id: parts[2])
        }
        guard let url = URL(string: trimmed), url.host?.contains("spotify.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { types.contains($0) }), parts.indices.contains(index + 1) else {
            return nil
        }
        return SpotifyLink(type: parts[index], id: parts[index + 1])
    }
}

enum SpotifyApp {
    static func open() {
        guard let url = URL(string: "spotify://") else { return }
        UIApplication.shared.open(url)
    }
}

enum CreateDestination: Identifiable, Hashable {
    case playlist
    case link
    case jam
    case smart(SmartKind)

    var id: String {
        switch self {
        case .playlist: "playlist"
        case .link: "link"
        case .jam: "jam"
        case .smart(let kind): "smart-\(kind.rawValue)"
        }
    }
}

struct CreateMenu: View {
    let onSelect: (CreateDestination) -> Void
    let onOpenSpotify: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            item("Playlist", symbol: "music.note") { onSelect(.playlist) }
            item("Play a link", symbol: "link") { onSelect(.link) }
            item("Join a Jam", symbol: "person.2.wave.2.fill") { onSelect(.jam) }

            if settings.showSmartPlaylists {
                ForEach(SmartKind.allCases) { kind in
                    item(kind.title, symbol: kind.symbol) { onSelect(.smart(kind)) }
                }
            }

            Button(action: onOpenSpotify) {
                row(title: "Open Spotify") {
                    ZStack {
                        Circle()
                            .fill(.black)
                            .padding(2)
                        Image("SpotifyLogo")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color(hex: "1ED760"))
                    }
                    .frame(width: 48, height: 48)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private func item(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(title: title) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Color.primary.opacity(0.12), in: Circle())
            }
        }
        .buttonStyle(.plain)
    }

    private func row<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 16) {
            icon()
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

@MainActor
enum TabSnapshot {
    static let probes = NSHashTable<UIView>.weakObjects()
    static var latest: UIImage?
    static var isEnabled = true
    private static let observed = NSHashTable<UIWindow>.weakObjects()

    static func observe(_ window: UIWindow) {
        guard !observed.contains(window) else { return }
        observed.add(window)
        let recognizer = UILongPressGestureRecognizer(target: TouchObserver.shared, action: #selector(TouchObserver.handle(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = TouchObserver.shared
        window.addGestureRecognizer(recognizer)
    }

    static func refresh() {
        guard let probe = probes.allObjects.first(where: { $0.window != nil }) else { return }
        var target: UIViewController?
        var responder: UIResponder? = probe
        while let current = responder {
            if let controller = current as? UIViewController, controller.parent is UITabBarController {
                target = controller
                break
            }
            responder = current.next
        }
        guard let view = target?.view, view.bounds.width > 0 else { return }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        latest = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
    }
}

@MainActor
final class TouchObserver: NSObject, UIGestureRecognizerDelegate {
    static let shared = TouchObserver()

    @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
        guard TabSnapshot.isEnabled, recognizer.state == .began, let window = recognizer.view else { return }
        let point = recognizer.location(in: window)
        if point.y > window.bounds.height - 130, point.x > window.bounds.width * 0.6 {
            TabSnapshot.refresh()
        }
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

final class ProbeView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { TabSnapshot.observe(window) }
    }
}

struct TabProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        TabSnapshot.probes.add(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

struct CreateTabContent: View {
    let snapshot: UIImage?
    let isMenuVisible: Bool
    let onClose: () -> Void
    let onSelect: (CreateDestination) -> Void

    @State private var appeared = false

    private var isShown: Bool { appeared && isMenuVisible }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            CreateMenu(
                onSelect: onSelect,
                onOpenSpotify: {
                    onClose()
                    SpotifyApp.open()
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .scaleEffect(isShown ? 1 : 0.94, anchor: .bottom)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let size = snapshot?.size ?? CGSize(width: 1000, height: 2400)
                ZStack {
                    if let snapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                    } else {
                        Color(uiColor: .systemBackground)
                    }
                    Color.black.opacity(isShown ? 0.45 : 0)
                }
                .frame(width: size.width, height: size.height)
                .offset(x: -origin.x, y: -origin.y)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isShown)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

struct CreateDestinationSheet: View {
    let destination: CreateDestination
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { dismiss() }
                            .tint(.primary)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .background {
            LinearGradient(
                colors: [settings.accent.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .playlist: NewPlaylistForm(done: { dismiss() })
        case .link: LinkForm(done: { dismiss() })
        case .jam: JamForm(done: { dismiss() })
        case .smart(let kind): SmartPlaylistForm(kind: kind, done: { dismiss() })
        }
    }
}

struct CreateScene<Content: View>: View {
    let prompt: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 28) {
            Text(prompt)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            content
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CreateField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 34
    var selectsAll = false
    var isURL = false
    var onSubmit: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .font(.system(size: size, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .focused($focused)
                .submitLabel(.done)
                .textInputAutocapitalization(isURL ? .never : .sentences)
                .autocorrectionDisabled(isURL)
                .keyboardType(isURL ? .URL : .default)
                .tint(settings.accent)
                .onSubmit(onSubmit)
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                    guard selectsAll, let field = note.object as? UITextField else { return }
                    DispatchQueue.main.async { field.selectAll(nil) }
                }
            Rectangle()
                .fill(.secondary.opacity(0.5))
                .frame(height: 1)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
    }
}

struct CreateButton: View {
    let title: String
    var isBusy = false
    var isEnabled = true
    var prominent = true
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if isBusy { ProgressView() }
            }
            .font(.headline)
            .foregroundStyle(prominent ? settings.onAccent : Color.primary)
            .frame(minWidth: 72)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.glassProminent)
        .tint(prominent ? settings.accent : Color.primary.opacity(0.18))
        .controlSize(.large)
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct CreateError: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }
}

struct NewPlaylistForm: View {
    let done: () -> Void
    @Environment(LibraryStore.self) private var library
    @State private var name = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        CreateScene(prompt: "Give your playlist a name.") {
            CreateField(placeholder: "Playlist name", text: $name, selectsAll: true) {
                Task { await create() }
            }
            CreateButton(title: "Create", isBusy: isBusy, isEnabled: !trimmed.isEmpty) {
                Task { await create() }
            }
            CreateError(message: errorMessage)
        }
        .onAppear {
            if name.isEmpty { name = "My playlist #\(library.playlists.count + 1)" }
        }
    }

    private func create() async {
        guard !trimmed.isEmpty, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        if library.isSample {
            done()
            return
        }
        do {
            try await library.createPlaylist(named: trimmed)
            done()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum SmartKind: String, CaseIterable, Identifiable {
    case topSongs, recent, liked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topSongs: "From your top songs"
        case .recent: "From recently played"
        case .liked: "From Liked Songs"
        }
    }

    var symbol: String {
        switch self {
        case .topSongs: "chart.bar.fill"
        case .recent: "clock.fill"
        case .liked: "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .topSongs: .purple
        case .recent: .teal
        case .liked: .red
        }
    }

    var defaultName: String {
        switch self {
        case .topSongs: "My top songs"
        case .recent: "Recently played"
        case .liked: "Liked Songs mix"
        }
    }

    var counts: [Int] {
        switch self {
        case .topSongs, .recent: [25, 50]
        case .liked: [50, 100]
        }
    }
}

struct SmartPlaylistForm: View {
    let kind: SmartKind
    let done: () -> Void
    @Environment(LibraryStore.self) private var library
    @State private var name = ""
    @State private var range: TopArtistsRange = .mediumTerm
    @State private var count = 50
    @State private var isBusy = false
    @State private var created: Int?
    @State private var errorMessage: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        CreateScene(prompt: kind.title) {
            if let created {
                Label("\(created) songs added", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                CreateButton(title: "Done", action: done)
            } else {
                CreateField(placeholder: "Playlist name", text: $name, size: 28, selectsAll: true) {
                    Task { await create() }
                }
                HStack(spacing: 12) {
                    if kind == .topSongs {
                        Picker("Period", selection: $range) {
                            ForEach(TopArtistsRange.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Songs", selection: $count) {
                        ForEach(kind.counts, id: \.self) { Text("\($0) songs").tag($0) }
                    }
                }
                .pickerStyle(.menu)
                CreateButton(title: "Create", isBusy: isBusy, isEnabled: !trimmed.isEmpty) {
                    Task { await create() }
                }
                CreateError(message: errorMessage)
            }
        }
        .onAppear {
            if name.isEmpty { name = kind.defaultName }
            count = kind.counts.last ?? 50
        }
        .haptic(.success, trigger: created)
    }

    private func create() async {
        guard !trimmed.isEmpty, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        if library.isSample {
            created = count
            return
        }
        do {
            let uris = try await fetchURIs()
            guard !uris.isEmpty else {
                errorMessage = "No songs found"
                return
            }
            let playlist = try await library.createPlaylist(
                named: trimmed,
                description: "Created with Swiftify"
            )
            for start in stride(from: 0, to: uris.count, by: 100) {
                try await library.api.perform(
                    "POST",
                    "playlists/\(playlist.id)/items",
                    body: ["uris": Array(uris[start..<min(start + 100, uris.count)])]
                )
            }
            created = uris.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchURIs() async throws -> [String] {
        switch kind {
        case .topSongs:
            let page: Page<Track> = try await library.api.get(
                "me/top/tracks",
                query: ["limit": "\(count)", "time_range": range.rawValue]
            )
            return page.items.map(\.uri)
        case .recent:
            let page: Page<PlayHistory> = try await library.api.get(
                "me/player/recently-played",
                query: ["limit": "\(count)"]
            )
            var seen = Set<String>()
            return page.items.compactMap(\.track?.uri).filter { seen.insert($0).inserted }
        case .liked:
            var result: [String] = []
            var offset = 0
            while result.count < count {
                let page: Page<SavedTrack> = try await library.api.get(
                    "me/tracks",
                    query: ["limit": "50", "offset": "\(offset)"]
                )
                result += page.items.map(\.track.uri)
                if page.next == nil || page.items.isEmpty { break }
                offset += 50
            }
            return Array(result.prefix(count))
        }
    }
}

struct LinkForm: View {
    let done: () -> Void
    @Environment(PlayerManager.self) private var player
    @Environment(QueueStore.self) private var queue
    @State private var link = ""
    @State private var errorMessage: String?

    private var isEmpty: Bool { link.trimmingCharacters(in: .whitespaces).isEmpty }
    private var parsed: SpotifyLink? { SpotifyLink.parse(link) }

    var body: some View {
        CreateScene(prompt: "Paste a Spotify link.") {
            CreateField(placeholder: "Link", text: $link, size: 24, isURL: true) { play() }
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first { link = first }
            }
            .buttonBorderShape(.capsule)
            HStack(spacing: 12) {
                CreateButton(title: "Play", isEnabled: !isEmpty, action: play)
                CreateButton(title: "Add to queue", isEnabled: !isEmpty, prominent: false, action: enqueue)
            }
            CreateError(message: errorMessage)
        }
    }

    private func play() {
        guard let parsed else {
            errorMessage = "That is not a Spotify link"
            return
        }
        Task {
            if parsed.isPlayableTrack {
                await player.play(uris: [parsed.uri])
            } else {
                await player.play(context: parsed.uri)
            }
            done()
        }
    }

    private func enqueue() {
        guard let parsed, parsed.isPlayableTrack else {
            errorMessage = "Only songs and episodes can be queued"
            return
        }
        Task {
            await queue.add(uri: parsed.uri)
            done()
        }
    }
}

struct JamForm: View {
    let done: () -> Void
    @State private var link = ""
    @State private var errorMessage: String?

    private var isEmpty: Bool { link.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        CreateScene(prompt: "Paste a Jam link.") {
            CreateField(placeholder: "Link", text: $link, size: 24, isURL: true) { join() }
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first { link = first }
            }
            .buttonBorderShape(.capsule)
            CreateButton(title: "Join in Spotify", isEnabled: !isEmpty, action: join)
            CreateError(message: errorMessage)
        }
    }

    private func join() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("socialsession"), let url = URL(string: trimmed) else {
            errorMessage = "That is not a Jam link"
            return
        }
        UIApplication.shared.open(url)
        done()
    }
}
