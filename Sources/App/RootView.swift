import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @State private var result: String?

    var body: some View {
        VStack(spacing: 20) {
            if auth.isAuthenticated {
                Button("Test GET /me/playlists") {
                    Task { result = await testPlaylists() }
                }
                .buttonStyle(.borderedProminent)

                if let result {
                    ScrollView {
                        Text(result)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button("Sign out", role: .destructive) { auth.signOut() }
            } else {
                Button("Sign in with Spotify") {
                    Task { await auth.signIn() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isSigningIn)

                if let message = auth.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .padding()
    }

    private func testPlaylists() async -> String {
        do {
            let token = try await auth.validAccessToken()
            var request = URLRequest(url: SpotifyConfig.apiBase.appending(path: "me/playlists")
                .appending(queryItems: [URLQueryItem(name: "limit", value: "5")]))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return "HTTP \(status)\n" + (String(data: data, encoding: .utf8) ?? "")
        } catch {
            return error.localizedDescription
        }
    }
}
