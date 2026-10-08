import Observation
import SwiftUI

@MainActor
@Observable
final class ChromeState {
    private(set) var hiddenCount = 0

    var hidesPlayerBar: Bool { hiddenCount > 0 }

    func enter() { hiddenCount += 1 }

    func leave() { hiddenCount = max(0, hiddenCount - 1) }
}

private struct HidesBottomBars: ViewModifier {
    @Environment(ChromeState.self) private var chrome

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .onAppear { chrome.enter() }
            .onDisappear { chrome.leave() }
    }
}

extension View {
    func hidesBottomBars() -> some View {
        modifier(HidesBottomBars())
    }
}
