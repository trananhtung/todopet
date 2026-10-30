import Foundation

/// Task estimates plus meetings against the work hours left: the overbooked warning and the board's day strip.
struct DayLoad: Equatable {
    /// Sum of the open tasks' estimates.
    var taskMinutes = 0
    /// Meeting minutes still ahead in work hours, overlaps counted once.
    var meetingMinutes = 0
    /// Work minutes left today.
    var capacity = 0
    /// How much the load runs past the time left, never below 0.
    var overBy = 0
}

enum LoadLevel { case ok, tight, over }

struct StripSegment: Identifiable, Equatable {
    enum Kind { case meeting, task }
    var kind: Kind
    var id: String
    var title: String
    /// Fractions of the work day, 0 ≤ start < end ≤ 1.
    var start: Double
    var end: Double
    /// 0 for the first row; a block that overlaps one above it goes a row down.
    var lane = 0
}

enum DayLoadRules {
    static let defaultEstimate = 30
    /// How far load may exceed the time left before the pet calls the day overbooked.
    static let overbookedMinutes = 60
    static let tightRatio = 0.85

    /// The Todoist duration when set, else the default estimate.
    static func estimate(_ t: TodoTask, defaultMinutes: Int) -> Int {
        if let m = t.duration?.minutes, m > 0 { return m }
        return defaultMinutes > 0 ? defaultMinutes : defaultEstimate
    }

    /// Open tasks that carry their own work: a task split into open steps gives way to them.
    static func workTasks(_ tasks: [TodoTask]) -> [TodoTask] {
        let open = tasks.filter { $0.checked != true }
        let parents = Set(open.compactMap(\.parentId))
        return open.filter { !parents.contains($0.id) }
    }

    static func load(tasks: [TodoTask], events: [CalEvent], now: Date, workStart: Int, workEnd: Int, defaultMinutes: Int) -> DayLoad {
        let dayStart = DayMath.at(hour: workStart, on: now)
        let dayEnd = workEnd >= 24 ? Calendar.current.startOfDay(for: now).addingTimeInterval(86400) : DayMath.at(hour: workEnd, on: now)
        let from = max(now, dayStart)
        // A timed task inside a meeting only adds the part outside it: those minutes are the meeting's.
        let taskMinutes = workTasks(tasks).reduce(0.0) { sum, t in
            let e = Double(estimate(t, defaultMinutes: defaultMinutes))
            guard let time = t.dueTime else { return sum + e }
            let s = max(time, now)
            let end = max(s, time.addingTimeInterval(e * 60))
            let covered = CalendarMath.busy(events, from: s, to: end).reduce(0) { $0 + $1.duration / 60 }
            return sum + max(0, e - covered)
        }
        var l = DayLoad(taskMinutes: Int(taskMinutes.rounded()))
        guard from < dayEnd else {
            l.overBy = l.taskMinutes
            return l
        }
        l.meetingMinutes = Int((CalendarMath.busy(events, from: from, to: dayEnd).reduce(0) { $0 + $1.duration } / 60).rounded())
        l.capacity = Int((dayEnd.timeIntervalSince(from) / 60).rounded())
        l.overBy = max(0, l.taskMinutes + l.meetingMinutes - l.capacity)
        return l
    }

    static func isOverbooked(_ l: DayLoad) -> Bool { l.overBy >= overbookedMinutes }

    static func level(_ l: DayLoad) -> LoadLevel {
        guard l.capacity > 0 else { return .ok }
        if isOverbooked(l) { return .over }
        if l.overBy > 0 || Double(l.taskMinutes + l.meetingMinutes) / Double(l.capacity) >= tightRatio { return .tight }
        return .ok
    }

    /// Meetings and timed tasks as fractions of the work day, each in the first row free where it starts; and where now is.
    static func strip(tasks: [TodoTask], events: [CalEvent], now: Date, workStart: Int, workEnd: Int,
                      defaultMinutes: Int) -> (segments: [StripSegment], now: Double) {
        let dayStart = DayMath.at(hour: workStart, on: now)
        let dayEnd = workEnd >= 24 ? Calendar.current.startOfDay(for: now).addingTimeInterval(86400) : DayMath.at(hour: workEnd, on: now)
        let length = dayEnd.timeIntervalSince(dayStart)
        guard length > 0 else { return ([], 0) }
        func fraction(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(dayStart) / length)) }
        var segs: [StripSegment] = []
        func add(_ kind: StripSegment.Kind, _ id: String, _ title: String, _ s: Date, _ e: Date) {
            let a = fraction(s), b = fraction(e)
            if a < b { segs.append(StripSegment(kind: kind, id: id, title: title, start: a, end: b)) }
        }
        for e in events { add(.meeting, e.id, e.title, e.start, e.end) }
        for t in workTasks(tasks) {
            if let time = t.dueTime {
                add(.task, t.id, t.title, time, time.addingTimeInterval(Double(estimate(t, defaultMinutes: defaultMinutes)) * 60))
            }
        }
        segs.sort { $0.start != $1.start ? $0.start < $1.start : ($0.kind == .meeting && $1.kind == .task) }
        var rowEnds: [Double] = []
        for i in segs.indices {
            let lane = rowEnds.firstIndex { $0 <= segs[i].start } ?? rowEnds.count
            if lane == rowEnds.count { rowEnds.append(segs[i].end) } else { rowEnds[lane] = segs[i].end }
            segs[i].lane = lane
        }
        return (segs, fraction(now))
    }

    /// "1h30" / "45'".
    static func text(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m)'" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(String(format: "%02d", m % 60))"
    }
}

/// Meeting bookends: open tasks that look related to a meeting, by shared words in the titles.
enum RelatedTasks {
    /// Words too common in meeting or task titles to mean anything (lower case, no diacritics; short words never count).
    private static let stopWords: Set<String> = [
        "meeting", "meetings", "call", "calls", "sync", "weekly", "daily", "monthly", "team", "teams", "review", "with",
        "about", "from", "into", "this", "that", "your", "ours", "their", "what", "when", "will", "have", "need", "some",
        "more", "today", "tomorrow", "week", "morning", "afternoon", "evening", "quick", "catch", "chat", "online", "zoom",
        "google", "update", "updates", "discussion",
        "nhung", "trong", "cong", "sang", "chieu", "trao", "nhanh", "khach", "hang",
    ]

    /// "Họp nhóm: Đề xuất ngân sách" → ["hop", "nhom", "de", "xuat", "ngan", "sach"].
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    /// Words that can link two titles: 4+ characters with a letter, not a stop word.
    static func significant(_ text: String) -> Set<String> {
        Set(words(text).filter { $0.count >= 4 && $0.contains(where: \.isLetter) && !stopWords.contains($0) })
    }

    /// Up to `limit` open tasks sharing a word with the meeting title: most shared words first, then in the order given.
    static func related(to meetingTitle: String, in tasks: [TodoTask], limit: Int = 2) -> [TodoTask] {
        let wanted = significant(meetingTitle)
        guard limit > 0, !wanted.isEmpty else { return [] }
        var matches: [(task: TodoTask, index: Int, shared: Int)] = []
        for (i, t) in tasks.enumerated() where t.checked != true {
            let shared = significant(t.title).intersection(wanted).count
            if shared > 0 { matches.append((t, i, shared)) }
        }
        matches.sort { $0.shared != $1.shared ? $0.shared > $1.shared : $0.index < $1.index }
        return matches.prefix(limit).map(\.task)
    }
}
