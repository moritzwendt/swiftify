import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class ChromeState {
    private(set) var hiddenCount = 0

    var hidesPlayerBar: Bool { hiddenCount > 0 }

    func enter() { hiddenCount += 1 }

    func leave() { hiddenCount = max(0, hiddenCount - 1) }
}

private struct AppearanceProbe: UIViewControllerRepresentable {
    let onEnter: () -> Void
    let onLeave: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(onEnter: onEnter, onLeave: onLeave)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private let onEnter: () -> Void
        private let onLeave: () -> Void
        private var isEntered = false

        init(onEnter: @escaping () -> Void, onLeave: @escaping () -> Void) {
            self.onEnter = onEnter
            self.onLeave = onLeave
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !isEntered else { return }
            isEntered = true
            onEnter()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard isEntered else { return }
            isEntered = false
            DispatchQueue.main.async { [onLeave] in onLeave() }
        }
    }
}

private struct HidesBottomBars: ViewModifier {
    @Environment(ChromeState.self) private var chrome

    func body(content: Content) -> some View {
        content
            .toolbar(chrome.hidesPlayerBar ? .hidden : .visible, for: .tabBar)
            .background {
                AppearanceProbe(onEnter: { chrome.enter() }, onLeave: { chrome.leave() })
                    .frame(width: 0, height: 0)
            }
    }
}

extension View {
    func hidesBottomBars() -> some View {
        modifier(HidesBottomBars())
    }
}
