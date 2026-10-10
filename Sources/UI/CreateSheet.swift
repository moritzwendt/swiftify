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

enum SpotifyGlyph {
    static let image: UIImage = {
        let side: CGFloat = 26
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let drawn = renderer.image { context in
            let cg = context.cgContext
            cg.scaleBy(x: side / 24, y: side / 24)
            cg.setFillColor(UIColor.black.cgColor)
            cg.fillEllipse(in: CGRect(x: 0, y: 0, width: 24, height: 24))
            cg.setBlendMode(.clear)
            cg.setLineCap(.round)
            let bars: [(start: CGPoint, control: CGPoint, end: CGPoint, width: CGFloat)] = [
                (CGPoint(x: 5.4, y: 9.4), CGPoint(x: 12, y: 5.6), CGPoint(x: 18.8, y: 10.4), 2.4),
                (CGPoint(x: 6.4, y: 12.9), CGPoint(x: 12, y: 9.9), CGPoint(x: 17.8, y: 13.6), 2),
                (CGPoint(x: 7.4, y: 16.1), CGPoint(x: 12, y: 13.7), CGPoint(x: 16.8, y: 16.7), 1.7)
            ]
            for bar in bars {
                cg.setLineWidth(bar.width)
                cg.move(to: bar.start)
                cg.addQuadCurve(to: bar.end, control: bar.control)
                cg.strokePath()
            }
        }
        return drawn.withRenderingMode(.alwaysTemplate)
    }()
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
                        Circle().fill(.black)
                        Image(uiImage: SpotifyGlyph.image)
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
        guard recognizer.state == .began, let window = recognizer.view else { return }
        if recognizer.location(in: window).y > window.bounds.height - 130 {
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
    let onClose: () -> Void
    let onSelect: (CreateDestination) -> Void

    @State private var shown = false

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
            .scaleEffect(shown ? 1 : 0.92, anchor: .bottom)
            .opacity(shown ? 1 : 0)
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
                    Color.black.opacity(shown ? 0.45 : 0)
                }
                .frame(width: size.width, height: size.height)
                .offset(x: -origin.x, y: -origin.y)
            }
        }
        .onAppear {
            withAnimation(.snappy(duration: 0.28)) { shown = true }
        }
        .onDisappear { shown = false }
    }
}

struct CreateDestinationSheet: View {
    let destination: CreateDestination
    @Environment(\.dismiss) private var dismiss

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
        .presentationDetents([.medium, .large])
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

struct NewPlaylistForm: View {
    let done: () -> Void
    @Environment(LibraryStore.self) private var library
    @State private var name = ""
    @State private var details = ""
    @State private var isPublic = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Description", text: $details, axis: .vertical)
                    .lineLimit(1...4)
            }
            Section {
                Toggle("Public", isOn: $isPublic)
            }
            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Text("Create playlist")
                        if isBusy { ProgressView() }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("New playlist")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        if library.isSample { return }
        do {
            try await library.createPlaylist(
                named: name.trimmingCharacters(in: .whitespaces),
                description: details.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: isPublic
            )
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

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
            }
            Section {
                if kind == .topSongs {
                    Picker("Period", selection: $range) {
                        ForEach(TopArtistsRange.allCases) { Text($0.title).tag($0) }
                    }
                }
                Picker("Songs", selection: $count) {
                    ForEach(kind.counts, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section {
                if let created {
                    Label("\(created) songs added", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                    Button("Done", action: done)
                } else {
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            Text("Create playlist")
                            if isBusy { ProgressView() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if name.isEmpty { name = kind.defaultName }
            count = kind.counts.last ?? 50
        }
        .haptic(.success, trigger: created)
    }

    private func create() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        if library.isSample { return }
        do {
            let uris = try await fetchURIs()
            guard !uris.isEmpty else {
                errorMessage = "No songs found"
                return
            }
            let playlist = try await library.createPlaylist(
                named: name.trimmingCharacters(in: .whitespaces),
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

    private var parsed: SpotifyLink? { SpotifyLink.parse(link) }

    var body: some View {
        Form {
            Section {
                TextField("Spotify link", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Paste") {
                    link = UIPasteboard.general.string ?? link
                }
            }
            Section {
                Button("Play") {
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
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Add to queue") {
                    guard let parsed, parsed.isPlayableTrack else {
                        errorMessage = "Only songs and episodes can be queued"
                        return
                    }
                    Task {
                        await queue.add(uri: parsed.uri)
                        done()
                    }
                }
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Play or queue a link")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct JamForm: View {
    let done: () -> Void
    @State private var link = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Jam link", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Paste") {
                    link = UIPasteboard.general.string ?? link
                }
            }
            Section {
                Button("Join in Spotify") {
                    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.contains("socialsession"), let url = URL(string: trimmed) else {
                        errorMessage = "That is not a Jam link"
                        return
                    }
                    UIApplication.shared.open(url)
                    done()
                }
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Join a Jam")
        .navigationBarTitleDisplayMode(.inline)
    }
}
