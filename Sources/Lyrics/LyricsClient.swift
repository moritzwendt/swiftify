import Foundation

struct LyricsClient {
    struct Record: Decodable, Equatable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    enum ClientError: Error {
        case server(Int)
    }

    var session: URLSession = .shared
    var retryDelays: [Duration] = [.milliseconds(600), .milliseconds(1200)]

    private static let base = URL(string: "https://lrclib.net/api")!

    func lyrics(for track: Track) async throws -> Lyrics {
        let artist = track.artists?.first?.name ?? ""
        let seconds = track.durationMs.map { Double($0) / 1000 }
        let album = track.album?.name

        if let record = try await get(name: track.name, artist: artist, album: album, seconds: seconds) {
            return Self.lyrics(from: record)
        }
        if album != nil, let record = try await get(name: track.name, artist: artist, album: nil, seconds: seconds) {
            return Self.lyrics(from: record)
        }
        let candidates = try await search(name: Self.cleanedTitle(track.name), artist: artist)
        if let record = Self.best(of: candidates, seconds: seconds) {
            return Self.lyrics(from: record)
        }
        return .notFound
    }

    static func lyrics(from record: Record) -> Lyrics {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .plain(plain)
        }
        return .notFound
    }

    static func best(of records: [Record], seconds: Double?, tolerance: Double = 3) -> Record? {
        let usable = records.filter { record in
            guard record.instrumental == true || record.syncedLyrics?.isEmpty == false || record.plainLyrics?.isEmpty == false else {
                return false
            }
            guard let seconds, let duration = record.duration else { return true }
            return abs(duration - seconds) <= tolerance
        }
        return usable.min { lhs, rhs in
            let leftSynced = lhs.syncedLyrics?.isEmpty == false
            let rightSynced = rhs.syncedLyrics?.isEmpty == false
            if leftSynced != rightSynced { return leftSynced }
            guard let seconds else { return false }
            return abs((lhs.duration ?? .infinity) - seconds) < abs((rhs.duration ?? .infinity) - seconds)
        }
    }

    static func cleanedTitle(_ title: String) -> String {
        var result = title
        if let range = result.range(of: " - ") {
            result = String(result[..<range.lowerBound])
        }
        result = result.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    private func get(name: String, artist: String, album: String?, seconds: Double?) async throws -> Record? {
        var items = [
            URLQueryItem(name: "track_name", value: name),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let seconds { items.append(URLQueryItem(name: "duration", value: "\(Int(seconds.rounded()))")) }
        let (data, status) = try await send("get", items)
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw ClientError.server(status) }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    private func search(name: String, artist: String) async throws -> [Record] {
        let items = [
            URLQueryItem(name: "track_name", value: name),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        let (data, status) = try await send("search", items)
        if status == 404 { return [] }
        guard (200..<300).contains(status) else { throw ClientError.server(status) }
        return try JSONDecoder().decode([Record].self, from: data)
    }

    private func send(_ path: String, _ items: [URLQueryItem]) async throws -> (Data, Int) {
        var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (status == 503 || status == 429), attempt < retryDelays.count else { return (data, status) }
            try await Task.sleep(for: retryDelays[attempt])
            attempt += 1
        }
    }

    private static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Swiftify/\(version) (https://github.com/moritzwendt/swiftify)"
    }
}
