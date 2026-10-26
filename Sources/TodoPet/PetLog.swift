import AppKit
import Combine

/// One line of the pet's diary: what it did (or held back) and why.
struct LogEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case bubble, response, antic, hold, flow, meeting, focus, mood, life, distraction, sync, system

        var icon: String {
            switch self {
            case .bubble: "💬"
            case .response: "↳"
            case .antic: "😤"
            case .hold: "⏸"
            case .flow: "🎧"
            case .meeting: "📅"
            case .focus: "🍅"
            case .mood: "🎭"
            case .life: "🍙"
            case .distraction: "👀"
            case .sync: "🔄"
            case .system: "⚙️"
            }
        }
    }

    var id = UUID()
    let time: Date
    let kind: Kind
    let text: String
    /// Machine-readable detail for the daily summary ("ignored", "picked", "closed", "flowEnd"…).
    var tag: String?
    var minutes: Int?

    /// "10:32 💬 text"
    var line: String { "\(DayMath.timeString(time)) \(kind.icon) \(text)" }
}

/// Counts that show at a glance whether the pet is too pushy or too quiet.
struct LogSummary: Equatable {
    var bubbles = 0
    var ignored = 0
    var dismissed = 0
    var holds = 0
    var flows = 0
    var flowMinutes = 0
    var antics = 0
    var distractedMinutes = 0

    init(_ entries: [LogEntry]) {
        for e in entries {
            switch (e.kind, e.tag) {
            case (.bubble, _): bubbles += 1
            case (.antic, _): antics += 1
            case (.response, "ignored"?): ignored += 1
            case (.response, "closed"?): dismissed += 1
            case (.hold, _): holds += 1
            case (.flow, "flowEnd"?):
                flows += 1
                flowMinutes += e.minutes ?? 0
            case (.distraction, "end"?): distractedMinutes += e.minutes ?? 0
            default: break
            }
        }
    }

    var text: String {
        var parts = [L("💬 \(bubbles) lời nhắc", "💬 \(bubbles) reminders")]
        if ignored + dismissed > 0 {
            parts.append(L("bạn bỏ qua \(ignored), đóng \(dismissed)", "you ignored \(ignored), closed \(dismissed)"))
        }
        if holds > 0 { parts.append(L("⏸ hoãn \(holds) lần", "⏸ held \(holds)×")) }
        if flows > 0 { parts.append(L("🎧 vào guồng \(flows) lần (\(CalendarMath.hoursText(Double(flowMinutes))))",
                                      "🎧 in the zone \(flows)× (\(CalendarMath.hoursText(Double(flowMinutes))))")) }
        if antics > 0 { parts.append(L("😤 quậy \(antics) lần", "😤 \(antics) antic(s)")) }
        if distractedMinutes > 0 { parts.append(L("👀 xao nhãng \(distractedMinutes)'", "👀 distracted \(distractedMinutes)'")) }
        return parts.joined(separator: " · ")
    }
}

/// The pet's diary: kept on this Mac only (one JSON-lines file per day, last 14 days).
final class PetLog: ObservableObject {
    @Published private(set) var today: [LogEntry] = []
    var enabled = true
    let folder: URL?
    private var dayKey = DayMath.key(Date())
    private var lastByKey: [String: Date] = [:]
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static var defaultFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TodoPet/log", isDirectory: true)
    }

    /// `folder: nil` keeps the diary in memory only (demo mode, snapshots, tests).
    init(folder: URL?, now: Date = Date()) {
        self.folder = folder
        dayKey = DayMath.key(now)
        if let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            prune(now: now)
            today = load(day: dayKey)
        }
    }

    /// Adds an entry. With `throttle`, the same key is logged at most once every `minutes`.
    func add(_ kind: LogEntry.Kind, _ text: String, tag: String? = nil, minutes: Int? = nil,
             throttle key: String? = nil, every interval: Double = 0, now: Date = Date()) {
        guard enabled else { return }
        if let key {
            if let last = lastByKey[key], now.timeIntervalSince(last) < interval * 60 { return }
            lastByKey[key] = now
        }
        let day = DayMath.key(now)
        if day != dayKey {
            dayKey = day
            today = []
        }
        let entry = LogEntry(time: now, kind: kind, text: text, tag: tag, minutes: minutes)
        today.append(entry)
        if today.count > 1000 { today.removeFirst(today.count - 1000) }
        append(entry, day: day)
    }

    private func file(_ day: String) -> URL? { folder?.appendingPathComponent("\(day).jsonl") }

    private func append(_ entry: LogEntry, day: String) {
        guard let url = file(day), var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func load(day: String) -> [LogEntry] {
        if day == dayKey && !today.isEmpty { return today }
        guard let url = file(day), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(LogEntry.self, from: Data($0.utf8)) }
    }

    /// Days that have a diary file, newest first.
    func days() -> [String] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [dayKey] }
        let found = names.filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }
        return Array(Set(found + [dayKey])).sorted(by: >)
    }

    private func prune(now: Date) {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let cutoff = DayMath.key(now.addingTimeInterval(-14 * 86_400))
        for name in names where name.hasSuffix(".jsonl") && String(name.dropLast(6)) < cutoff {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Plain text for copying (e.g. to paste into a chat when tuning the pet).
    static func export(_ entries: [LogEntry], day: String) -> String {
        (["TodoPet — \(L("nhật ký", "diary")) \(day)", LogSummary(entries).text, ""]
            + entries.sorted { $0.time < $1.time }.map(\.line)).joined(separator: "\n")
    }
}
