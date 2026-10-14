import SwiftUI

struct ClientIDSetupView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var clientID = ""
    @State private var copied = false
    @FocusState private var focused: Bool

    var onCancel: (() -> Void)?
    let onSaved: () -> Void

    private var isValid: Bool { AuthManager.isValidClientID(clientID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.glass)
                }

                Text("Set up Spotify")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                SetupStep(number: 1, title: "Open the Spotify Developer Dashboard and log in.") {
                    Button("Open Dashboard") { openURL(SpotifyConfig.dashboardURL) }
                        .buttonStyle(.glass)
                }

                SetupStep(number: 2, title: "Create an app. Select Web API and add this Redirect URI.") {
                    Button {
                        UIPasteboard.general.string = SpotifyConfig.redirectURI
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(SpotifyConfig.redirectURI)
                                .font(.system(.body, design: .monospaced))
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                    }
                    .buttonStyle(.glass)
                }

                SetupStep(number: 3, title: "Open the app settings and copy the Client ID.")

                SetupStep(number: 4, title: "Paste the Client ID here.") {
                    HStack(spacing: 8) {
                        TextField("Client ID", text: $clientID)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focused)
                        Button {
                            if let value = UIPasteboard.general.string {
                                clientID = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }

                Button {
                    focused = false
                    if auth.saveClientID(clientID) {
                        onSaved()
                        Task { await auth.signIn() }
                    }
                } label: {
                    Text("Sign in with Spotify")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!isValid || auth.isSigningIn)

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { clientID = auth.clientID }
    }
}

private struct SetupStep<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.18), in: .circle)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            Spacer(minLength: 0)
        }
    }
}

extension SetupStep where Content == EmptyView {
    fileprivate init(number: Int, title: String) {
        self.init(number: number, title: title) { EmptyView() }
    }
}
