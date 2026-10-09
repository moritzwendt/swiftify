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
}

struct LyricRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case line
        case interlude
    }

    let id: Int
    let kind: Kind
    let start: Double
    let end: Double
    let text: String

    var duration: Double { max(end - start, 0.001) }

    var fillDuration: Double {
        let natural = max(Double(text.count) * 0.15, 0.8)
        return min(natural, max(duration * 0.9, 0.4))
    }

    private static let introThreshold = 5.0
    private static let pauseThreshold = 4.0
    private static let breakThreshold = 8.0

    static func rows(from lines: [LyricLine], trackDuration: Double?) -> [LyricRow] {
        guard let first = lines.first else { return [] }
        var rows: [LyricRow] = []
        func append(_ kind: Kind, _ start: Double, _ end: Double, _ text: String = "") {
            rows.append(LyricRow(id: rows.count, kind: kind, start: start, end: end, text: text))
        }
        if first.time >= introThreshold {
            append(.interlude, 0, first.time)
        }
        for (index, line) in lines.enumerated() {
            let next = index + 1 < lines.count ? lines[index + 1].time : trackDuration
            let end = max(next ?? line.time + 6, line.time)
            if line.text.isEmpty {
                if end - line.time >= pauseThreshold {
                    append(.interlude, line.time, end)
                }
                continue
            }
            let sung = line.time + min(Double(line.text.count) * 0.11 + 1.2, 7)
            if end - sung >= breakThreshold {
                append(.line, line.time, sung, line.text)
                append(.interlude, sung, end)
            } else {
                append(.line, line.time, end, line.text)
            }
        }
        while rows.last?.kind == .interlude {
            rows.removeLast()
        }
        return rows
    }

    static func index(of rows: [LyricRow], at seconds: Double) -> Int? {
        var low = 0
        var high = rows.count - 1
        var result: Int?
        while low <= high {
            let middle = (low + high) / 2
            if rows[middle].start <= seconds {
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
