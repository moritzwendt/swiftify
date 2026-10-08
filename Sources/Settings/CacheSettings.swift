import SwiftUI

struct CacheSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(CacheWarmer.self) private var warmer
    @State private var listStats = (count: 0, bytes: 0)
    @State private var imageStats = (count: 0, bytes: 0)
    @State private var confirmRebuild = false
    @State private var confirmClearAll = false

    private static let limits = [100, 300, 500, 1000, 2000]

    private func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func limitTitle(_ megabytes: Int) -> String {
        megabytes >= 1000 ? "\(megabytes / 1000) GB" : "\(megabytes) MB"
    }

    private func refresh() async {
        listStats = await TrackListCache.stats()
        imageStats = await ImageCache.shared.stats()
    }

    private func clearAll() {
        TrackListCache.clear()
        URLCache.shared.removeAllCachedResponses()
        Task {
            await ImageCache.shared.clear()
            await refresh()
        }
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section("Storage") {
                LabeledContent("Song lists") {
                    Text("\(listStats.count) \u{2022} \(size(listStats.bytes))")
                }
                LabeledContent("Images") {
                    Text("\(imageStats.count) \u{2022} \(size(imageStats.bytes))")
                }
                LabeledContent("Total", value: size(listStats.bytes + imageStats.bytes))
            }

            Section("Options") {
                Toggle("Cache song lists", isOn: $settings.cacheLists)
                Toggle("Cache images", isOn: $settings.cacheImages)
                Toggle("Preload images", isOn: $settings.preloadImages)
                    .disabled(!settings.cacheImages)
                Picker("Image cache limit", selection: $settings.imageCacheLimitMB) {
                    ForEach(Self.limits, id: \.self) { Text(limitTitle($0)).tag($0) }
                }
                .disabled(!settings.cacheImages)
            }

            Section("Actions") {
                if warmer.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(warmer.done), total: Double(max(warmer.total, 1)))
                        HStack {
                            Text(warmer.currentName).lineLimit(1)
                            Spacer(minLength: 12)
                            Text("\(warmer.done) of \(warmer.total)").foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                    Button("Stop", role: .destructive) { warmer.cancel() }
                } else {
                    Button("Cache all playlists") {
                        warmer.start(library: library, settings: settings, force: false)
                    }
                    Button("Rebuild cache") { confirmRebuild = true }
                    if let result = warmer.lastResult {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!settings.cacheLists && !settings.cacheImages)

            Section {
                Button("Clear song list cache") {
                    TrackListCache.clear()
                    Task { await refresh() }
                }
                Button("Clear image cache") {
                    URLCache.shared.removeAllCachedResponses()
                    Task {
                        await ImageCache.shared.clear()
                        await refresh()
                    }
                }
                Button("Clear all caches", role: .destructive) { confirmClearAll = true }
            }
        }
        .navigationTitle("Cache")
        .navigationBarTitleDisplayMode(.inline)
        .hidesBottomBars()
        .task(id: warmer.done) { await refresh() }
        .onChange(of: warmer.isRunning) { Task { await refresh() } }
        .onChange(of: settings.imageCacheLimitMB) {
            Task {
                await ImageCache.shared.trimNow()
                await refresh()
            }
        }
        .confirmationDialog("Rebuild cache", isPresented: $confirmRebuild, titleVisibility: .visible) {
            Button("Rebuild", role: .destructive) {
                TrackListCache.clear()
                Task {
                    await ImageCache.shared.clear()
                    warmer.start(library: library, settings: settings, force: true)
                    await refresh()
                }
            }
        }
        .confirmationDialog("Clear all caches", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { clearAll() }
        }
    }
}
