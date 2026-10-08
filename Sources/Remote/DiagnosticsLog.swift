import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsLog {
    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let date: Date
        let text: String
    }

    private(set) var entries: [Entry]

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let limit: Int
    @ObservationIgnored private let now: () -> Date

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static var defaultFileURL: URL? {
        let manager = FileManager.default
        guard let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? manager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "sdk-diagnostics.json")
    }

    init(fileURL: URL? = nil, limit: Int = 400, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.limit = limit
        self.now = now
        entries = Self.load(fileURL)
    }

    func add(_ text: String) {
        entries.append(Entry(id: UUID(), date: now(), text: text))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func export() -> String {
        entries.map { "\(Self.stamp($0.date)) \($0.text)" }.joined(separator: "\n")
    }

    static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static func load(_ fileURL: URL?) -> [Entry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
