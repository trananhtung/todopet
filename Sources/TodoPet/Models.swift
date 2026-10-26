import Foundation

// MARK: - Todoist API v1 objects (decoded with .convertFromSnakeCase)

struct TodoDue: Codable, Hashable {
    var date: String
    var string: String?
    var isRecurring: Bool?
    var datetime: String?
    var timezone: String?
}

struct TodoDeadline: Codable, Hashable {
    var date: String
}

struct TodoDuration: Codable, Hashable {
    var amount: Int
    var unit: String

    var minutes: Int { unit == "day" ? amount * 8 * 60 : amount }
}

struct TodoTask: Codable, Identifiable, Hashable {
    var id: String
    var content: String
    var description: String?
    var priority: Int?
    var due: TodoDue?
    var deadline: TodoDeadline?
    var duration: TodoDuration?
    var projectId: String?
    var parentId: String?
    var labels: [String]?
    var checked: Bool?
    var completedAt: String?
    var childOrder: Int?
    var dayOrder: Int?

    /// Todoist API priority: 4 = P1 (urgent) … 1 = P4 (normal).
    var apiPriority: Int { priority ?? 1 }
    /// Priority as the Todoist UI shows it: 1 = P1 … 4 = P4.
    var uiPriority: Int { 5 - min(max(apiPriority, 1), 4) }
    var title: String { TextClean.plain(content) }
    var isRecurring: Bool { due?.isRecurring ?? false }
    var dueDay: String? { due.map { String($0.date.prefix(10)) } }

    /// Exact due time if the task has one ("3pm"), else nil for all-day tasks.
    var dueTime: Date? {
        guard let due else { return nil }
        if let dt = due.datetime, let d = DateParse.parse(dt) { return d }
        if due.date.count > 10 { return DateParse.parse(due.date) }
        return nil
    }

    var completedDate: Date? { completedAt.flatMap(DateParse.parse) }
}

struct ProductivityStats: Decodable {
    struct Streak: Decodable { var count: Int? }
    struct Goals: Decodable {
        var dailyGoal: Int?
        var currentDailyStreak: Streak?
        var maxDailyStreak: Streak?
    }
    struct DayItems: Decodable {
        var date: String?
        var totalCompleted: Int?
    }
    var completedCount: Int?
    var daysItems: [DayItems]?
    var goals: Goals?
    var karma: Double?

    var streak: Int { goals?.currentDailyStreak?.count ?? 0 }
}

// MARK: - Helpers

enum DateParse {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let floating: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    /// Parses every date shape Todoist returns: "2026-10-25", "2026-10-25T09:00:00" (floating, local time),
    /// "2026-10-25T02:00:00Z" and "2026-10-25T02:00:00.123456Z".
    static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let d = iso.date(from: s) ?? isoFrac.date(from: s) { return d }
        // Long fractional seconds (microseconds) are not accepted by ISO8601DateFormatter: drop them.
        let noFrac = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        if let d = iso.date(from: noFrac) { return d }
        floating.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            floating.dateFormat = fmt
            if let d = floating.date(from: noFrac) { return d }
        }
        return nil
    }

    static func utcString(_ d: Date) -> String { iso.string(from: d) }
}

enum DayMath {
    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func at(hour: Int, minute: Int = 0, on d: Date) -> Date {
        Calendar.current.date(bySettingHour: min(max(hour, 0), 23), minute: minute, second: 0, of: d) ?? d
    }
    static func hour(_ d: Date) -> Int { Calendar.current.component(.hour, from: d) }

    /// Whole days from day key `a` to day key `b` ("yyyy-MM-dd").
    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let x = DateParse.parse(a), let y = DateParse.parse(b) else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: x),
                                               to: Calendar.current.startOfDay(for: y)).day ?? 0
    }

    /// "yesterday" / "3 days ago" for an overdue "yyyy-MM-dd".
    static func daysAgo(_ day: String, now: Date = Date()) -> String {
        let n = daysBetween(day, key(now))
        if n == 1 { return L("hôm qua", "yesterday") }
        return L("\(n) ngày trước", "\(n) days ago")
    }

    static func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

enum TextClean {
    /// Strips Todoist markdown so titles read nicely in bubbles.
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func short(_ s: String, _ max: Int = 42) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
}

/// Today's picture, derived from what Todoist returned.
struct DaySnapshot {
    var today: [TodoTask] = []      // active, due today (or undated tasks matched by the filter)
    var overdue: [TodoTask] = []    // active, due before today
    var completed: [TodoTask] = []  // completed today
    var late: [TodoTask] = []       // due today at a time that has passed

    var planned: Int { today.count + completed.count }
    var remaining: Int { today.count }
    var open: [TodoTask] { overdue + today }

    /// Open tasks in "eat the frog" order (highest priority, then earliest time, then oldest overdue).
    /// A task that was split into open sub-steps gives way to its steps.
    var actionable: [TodoTask] {
        let parents = Set(open.compactMap(\.parentId))
        return DaySnapshot.ranked(open).filter { !parents.contains($0.id) }
    }

    var next: TodoTask? { actionable.first ?? DaySnapshot.ranked(open).first }

    static func ranked(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.sorted { a, b in
            if a.apiPriority != b.apiPriority { return a.apiPriority > b.apiPriority }
            switch (a.dueTime, b.dueTime) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if let x = a.dueDay, let y = b.dueDay, x != y { return x < y }
            return (a.dayOrder ?? a.childOrder ?? 0) < (b.dayOrder ?? b.childOrder ?? 0)
        }
    }

    static func build(active: [TodoTask], completed: [TodoTask], now: Date) -> DaySnapshot {
        let todayKey = DayMath.key(now)
        var s = DaySnapshot()
        for t in active where t.checked != true {
            if let day = t.dueDay, day < todayKey {
                s.overdue.append(t)
            } else if t.dueDay == nil || t.dueDay == todayKey {
                s.today.append(t)
                if let time = t.dueTime, time < now { s.late.append(t) }
            }
            // Tasks due later (a custom filter may return them) don't count for today.
        }
        s.today = ranked(s.today)
        s.overdue = ranked(s.overdue)
        s.completed = completed.sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
        return s
    }
}
