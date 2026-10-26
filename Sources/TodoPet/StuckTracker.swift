import Foundation

struct StuckTask: Identifiable, Hashable {
    let task: TodoTask
    /// Number of days this task has been on your "today" list without getting done.
    let days: Int
    var id: String { task.id }
}

/// Remembers on which days each task sat in your day without being finished, to spot tasks you keep postponing.
/// Todoist doesn't expose how often a task was rescheduled, so the pet keeps its own small log (task id → day keys).
final class StuckTracker {
    private let defaults: UserDefaults?
    private let key = "stuckSeenDays"
    private var seen: [String: [String]]

    /// `persist: false` keeps the log in memory (demo mode).
    init(persist: Bool = true) {
        defaults = persist ? .standard : nil
        seen = (defaults?.dictionary(forKey: key) as? [String: [String]]) ?? [:]
    }

    func record(_ tasks: [TodoTask], now: Date) {
        let today = DayMath.key(now)
        let cutoff = DayMath.key(now.addingTimeInterval(-21 * 86_400))
        var changed = false
        for t in tasks where !t.isRecurring {
            var days = seen[t.id] ?? []
            if !days.contains(today) {
                days.append(today)
                seen[t.id] = Array(days.suffix(30))
                changed = true
            }
        }
        for (id, days) in seen where (days.last ?? "") < cutoff {
            seen[id] = nil
            changed = true
        }
        if changed { defaults?.set(seen, forKey: key) }
    }

    func seenDays(_ id: String) -> Int { seen[id]?.count ?? 0 }

    /// Pre-fills history (demo mode).
    func pretend(_ id: String, days: Int, now: Date) {
        seen[id] = (0..<days).reversed().map { DayMath.key(now.addingTimeInterval(-Double($0) * 86_400)) }
    }

    func stuck(_ tasks: [TodoTask], minDays: Int, now: Date) -> [StuckTask] {
        let today = DayMath.key(now)
        return tasks.filter { !$0.isRecurring }
            .map { StuckTask(task: $0, days: StuckTracker.days(seen: seenDays($0.id), dueDay: $0.dueDay, today: today)) }
            .filter { $0.days >= minDays }
            .sorted { $0.days > $1.days }
    }

    /// Days on the list: what we saw ourselves, or how long it has been overdue (counting today), whichever is larger.
    static func days(seen: Int, dueDay: String?, today: String) -> Int {
        guard let dueDay, dueDay < today else { return seen }
        return max(seen, DayMath.daysBetween(dueDay, today) + 1)
    }
}
