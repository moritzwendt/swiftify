import SwiftUI

struct CreateSheet: View {
    private enum Mode { case menu, playlist, jam }

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .menu
    @State private var name = ""
    @State private var link = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .menu: menu
                case .playlist: playlistForm
                case .jam: jamForm
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode != .menu {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") {
                            errorMessage = nil
                            mode = .menu
                        }
                    }
                }
            }
        }
        .presentationDetents([.height(mode == .menu ? 260 : 300)])
    }

    private var title: String {
        switch mode {
        case .menu: "Create"
        case .playlist: "New playlist"
        case .jam: "Join a Jam"
        }
    }

    private var menu: some View {
        VStack(spacing: 12) {
            option("Playlist", symbol: "music.note.list") { mode = .playlist }
            option("Jam", symbol: "person.2.wave.2.fill") { mode = .jam }
        }
    }

    private func option(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 28)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var playlistForm: some View {
        VStack(spacing: 16) {
            TextField("Playlist name", text: $name)
                .textFieldStyle(.roundedBorder)
            errorLabel
            Button {
                Task { await createPlaylist() }
            } label: {
                Text("Create").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
        }
    }

    private var jamForm: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Jam link", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Paste") {
                    link = UIPasteboard.general.string ?? link
                }
                .buttonStyle(.glass)
            }
            errorLabel
            Button {
                joinJam()
            } label: {
                Text("Join in Spotify").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func createPlaylist() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await library.createPlaylist(named: name.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func joinJam() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("socialsession"), let url = URL(string: trimmed) else {
            errorMessage = "That is not a Jam link"
            return
        }
        UIApplication.shared.open(url)
        dismiss()
    }
}
