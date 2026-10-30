import Foundation

/// If-then starts: "start this task after ⟨meeting⟩ / when I open ⟨app⟩ / after lunch". Planning when and where you'll
/// start roughly doubles follow-through (implementation intentions, d = 0.65, Gollwitzer & Sheeran 2006).
enum StartTrigger: Codable, Equatable, Hashable {
    case afterMeeting(id: String, title: String)
    case appOpens(name: String, bundle: String)
    case afterLunch

    var label: String {
        switch self {
        case .afterMeeting(_, let title): L("sau “\(TextClean.short(title, 28))”", "after “\(TextClean.short(title, 28))”")
        case .appOpens(let name, _): L("khi mở \(name)", "when I open \(name)")
        case .afterLunch: L("sau bữa trưa", "after lunch")
        }
    }
}

struct TaskTrigger: Codable, Equatable {
    var taskId: String
    var taskTitle: String
    /// The day it is for, "yyyy-MM-dd".
    var day: String
    var trigger: StartTrigger
    /// An app plan waits for the app to come to the front after this.
    var setAt: Date
    var fired = false
    /// "Later": not before this.
    var notBefore: Date?
}

enum TriggerRules {
    /// "After lunch" holds from this hour.
    static let lunchHour = 13
    static let maxApps = 3

    /// Today's unfired plans whose condition holds now, in list order.
    static func due(_ list: [TaskTrigger], today: String, now: Date, endedMeetings: Set<String>,
                    front: (bundle: String, since: Date)?) -> [TaskTrigger] {
        list.filter { t in
            guard t.day == today, !t.fired, now >= (t.notBefore ?? .distantPast) else { return false }
            switch t.trigger {
            case .afterMeeting(let id, _): return endedMeetings.contains(id)
            case .appOpens(_, let bundle):
                // The app has to come to the front after the plan was made: one already in front doesn't count.
                guard let f = front else { return false }
                return f.bundle == bundle && f.since > t.setAt
            case .afterLunch: return DayMath.hour(now) >= lunchHour
            }
        }
    }

    /// The task's "Start when…" menu: after each meeting today that hasn't ended, when I open one of up to 3 recent
    /// work apps (not the one in front), and after lunch while it's still before 13:00.
    static func choices(events: [CalEvent], now: Date, recentApps: [(name: String, bundle: String)], frontBundle: String?) -> [StartTrigger] {
        var out: [StartTrigger] = events.filter { $0.end > now }.sorted { $0.start < $1.start }.prefix(4)
            .map { .afterMeeting(id: $0.id, title: $0.title) }
        out += recentApps.filter { $0.bundle != frontBundle }.prefix(maxApps).map { .appOpens(name: $0.name, bundle: $0.bundle) }
        if DayMath.hour(now) < lunchHour { out.append(.afterLunch) }
        return out
    }
}

/// Today's if-then plans, saved for the day (fired ones too, so they don't fire again).
final class TriggerStore: ObservableObject {
    @Published private(set) var list: [TaskTrigger] = []
    private let defaults: UserDefaults?

    init(persist: Bool = true) {
        defaults = persist ? .standard : nil
        if let data = defaults?.data(forKey: "startTriggers"), let l = try? JSONDecoder().decode([TaskTrigger].self, from: data) {
            list = l
        }
        prune(today: DayMath.key(Date()))
    }

    func trigger(for taskId: String, day: String) -> TaskTrigger? { list.first { $0.taskId == taskId && $0.day == day } }

    /// One plan per task per day.
    func set(_ task: TodoTask, _ trigger: StartTrigger, day: String, now: Date) {
        list.removeAll { $0.taskId == task.id && $0.day == day }
        list.append(TaskTrigger(taskId: task.id, taskTitle: task.title, day: day, trigger: trigger, setAt: now))
        save()
    }

    func clear(_ taskId: String, day: String) {
        list.removeAll { $0.taskId == taskId && $0.day == day }
        save()
    }

    func markFired(_ taskId: String, day: String) {
        for i in list.indices where list[i].taskId == taskId && list[i].day == day { list[i].fired = true }
        save()
    }

    /// "Later": armed again, not before `notBefore`.
    func rearm(_ taskId: String, day: String, notBefore: Date) {
        for i in list.indices where list[i].taskId == taskId && list[i].day == day {
            list[i].fired = false
            list[i].notBefore = notBefore
        }
        save()
    }

    func prune(today: String) {
        let kept = list.filter { $0.day == today }
        if kept.count != list.count {
            list = kept
            save()
        }
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: "startTriggers")
    }
}
