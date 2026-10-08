import SwiftUI
import UIKit

enum CoverMode {
    case logo
    case verbose
}

struct LaunchCover: View {
    let mode: CoverMode
    var isPreview = false
    let onFinish: () -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(LibraryStore.self) private var library
    @Environment(ChromeState.self) private var chrome
    @State private var shown = 0
    @State private var logoVisible = false
    @State private var visibleSince: Date?
    @State private var fading = false

    var body: some View {
        ZStack {
            switch mode {
            case .logo: logo
            case .verbose: VerboseBootView(shown: shown)
            }
        }
        .opacity(fading ? 0 : 1)
        .statusBarHidden(mode == .verbose)
        .task { await run() }
    }

    private var logo: some View {
        ZStack {
            Color(uiColor: Self.launchBackground)
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .scaleEffect(logoVisible ? 1 : 0.9)
                .opacity(logoVisible ? 1 : 0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                logoVisible = true
            } completion: {
                visibleSince = Date()
            }
        }
    }

    private static var launchBackground: UIColor {
        let system = UITraitCollection(userInterfaceStyle: UIScreen.main.traitCollection.userInterfaceStyle)
        return UIColor.systemBackground.resolvedColor(with: system)
    }

    private func pump() {
        let backlog = BootLog.shared.lines.count - shown
        if backlog > 0 { shown += min(backlog, max(2, backlog / 14)) }
    }

    private func run() async {
        let verbose = mode == .verbose
        let started = Date()
        let hold: TimeInterval = verbose ? 1.6 : 0.25
        let timeout: TimeInterval = verbose ? 8 : 3
        while !Task.isCancelled {
            if verbose {
                pump()
                if visibleSince == nil, shown > 0 { visibleSince = Date() }
            }
            let held = visibleSince.map { Date().timeIntervalSince($0) } ?? 0
            let dataReady = isPreview || !auth.isAuthenticated || library.isSample || (library.hasLoaded && chrome.homeLoaded)
            let streamed = !verbose || shown >= BootLog.shared.lines.count
            if Date().timeIntervalSince(started) >= timeout || (visibleSince != nil && held >= hold && dataReady && streamed) { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        if !isPreview { BootLog.shared.finish() }
        if verbose {
            while shown < BootLog.shared.lines.count {
                pump()
                try? await Task.sleep(for: .milliseconds(16))
            }
            try? await Task.sleep(for: .milliseconds(450))
        }
        withAnimation(.easeOut(duration: 0.25)) { fading = true }
        try? await Task.sleep(for: .milliseconds(280))
        onFinish()
    }
}

struct VerboseBootView: View {
    let shown: Int

    private let lineHeight: CGFloat = 9.5

    private func color(_ kind: BootLine.Kind) -> Color {
        switch kind {
        case .plain: .white.opacity(0.88)
        case .dim: .white.opacity(0.4)
        case .info: Color(red: 0.4, green: 0.85, blue: 1)
        case .warn: Color(red: 1, green: 0.85, blue: 0.35)
        case .good: Color(red: 0.4, green: 1, blue: 0.5)
        case .strong: .white
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let capacity = max(1, Int((geometry.size.height - 28) / lineHeight))
            let lines = BootLog.shared.lines
            let end = min(shown, lines.count)
            let visible = lines[max(0, end - capacity)..<end]
            ZStack(alignment: .bottomLeading) {
                Color.black
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { line in
                        Text(line.text)
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(color(line.kind))
                            .fontWeight(line.kind == .strong ? .bold : .regular)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(height: lineHeight, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}
