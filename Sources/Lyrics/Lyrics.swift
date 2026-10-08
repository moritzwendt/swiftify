import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

enum Lyrics: Equatable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound

    static func index(of lines: [LyricLine], at seconds: Double) -> Int? {
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].time <= seconds {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return result
    }
}

enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        var entries: [(time: Double, text: String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = seconds(from: tag) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            let content = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                entries.append((time, content))
            }
        }
        entries.sort { $0.time < $1.time }
        return entries.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }

    private static func seconds(from tag: Substring) -> Double? {
        var parts = tag.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 {
            parts = [parts[0], parts[1] + "." + parts[2]]
        }
        guard parts.count == 2,
              let minutes = Double(parts[0]), minutes >= 0,
              let seconds = Double(parts[1]), seconds >= 0 else { return nil }
        return minutes * 60 + seconds
    }
}
