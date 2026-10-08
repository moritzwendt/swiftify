import SwiftUI

@main
struct SwiftifyApp: App {
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
    }
}
