import SwiftUI

enum ClientIDSetupMode {
    case guide
    case entry
}

struct PillButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isDisabled ? Color.white.opacity(0.4) : Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isDisabled ? Color.white.opacity(0.18) : Color.white, in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct ClientIDSetupView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var clientID = ""
    @State private var copied = false
    @FocusState private var focused: Bool

    let mode: ClientIDSetupMode
    let onBack: () -> Void
    let onSaved: () -> Void

    private var isValid: Bool { AuthManager.isValidClientID(clientID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(mode == .guide ? "Set up Client ID" : "Enter Client ID")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if mode == .guide {
                    guideSteps
                } else {
                    card { redirectRow(label: "Add this Redirect URI to your Spotify app") }
                    clientIDField
                }

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 60)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .overlay(alignment: .topLeading) { backButton }
        .safeAreaInset(edge: .bottom) { signInButton }
        .onAppear { clientID = auth.clientID }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 4)
    }

    private var signInButton: some View {
        PillButton(title: "Sign in with Spotify", isDisabled: !isValid || auth.isSigningIn) {
            focused = false
            if auth.saveClientID(clientID) {
                onSaved()
                Task { await auth.signIn() }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private var guideSteps: some View {
        VStack(alignment: .leading, spacing: 22) {
            SetupStep(number: 1, title: "Open the Spotify Developer Dashboard and log in.") {
                Text("Spotify Premium is required.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                Button("Open Dashboard") { openURL(SpotifyConfig.dashboardURL) }
                    .buttonStyle(.glass)
            }

            SetupStep(number: 2, title: "Create an app with these settings and tap Save.") {
                card {
                    FormRow(label: "App name and description") { Text("Anything you like") }
                    Divider().overlay(.white.opacity(0.15))
                    redirectRow(label: "Redirect URI, then tap Add")
                    Divider().overlay(.white.opacity(0.15))
                    FormRow(label: "APIs") {
                        Text("Check Web API").fontWeight(.semibold)
                    }
                }
            }

            SetupStep(number: 3, title: "Open the app, tap Settings and copy the Client ID.")

            SetupStep(number: 4, title: "Paste the Client ID.") {
                clientIDField
            }
        }
    }

    private var clientIDField: some View {
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

    private func redirectRow(label: String) -> some View {
        Button {
            UIPasteboard.general.string = SpotifyConfig.redirectURI
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            FormRow(label: label) {
                HStack {
                    Text(SpotifyConfig.redirectURI)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            content
                .font(.body)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension SetupStep where Content == EmptyView {
    fileprivate init(number: Int, title: String) {
        self.init(number: number, title: title) { EmptyView() }
    }
}
