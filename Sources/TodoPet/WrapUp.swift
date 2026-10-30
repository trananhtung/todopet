import Foundation

/// What you chose for a day when you wrapped up the one before: its frog and a note to your future self.
struct DayPlan: Codable, Equatable {
    /// The day it is for, "yyyy-MM-dd".
    var day: String
    var frogId: String?
    var note: String?
}

/// What to do with an unfinished task in the wrap-up: leave it, move it to tomorrow, or take it off the plan.
enum WrapMove: String, CaseIterable, Identifiable {
    case keep, tomorrow, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .keep: L("Giữ", "Keep")
        case .tomorrow: L("Mai", "Tomorrow")
        case .none: L("Bỏ hạn", "No date")
        }
    }
}

/// The shutdown ritual: planning tomorrow at the end of the day helps you detach from work (Smit 2016), and seeing
/// your progress is the strongest motivator at work (Amabile & Kramer 2011).
enum WrapRules {
    /// The wrap-up is offered from this hour, or half an hour before work ends when that is earlier.
    static let wrapUpHour = 15
    static let maxNote = 140

    static func canWrapUp(_ now: Date, workEnd: Int) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return minutes >= min(wrapUpHour * 60, workEnd * 60 - 30)
    }

    /// One tidy line, at most `maxNote` characters; nil when empty.
    static func tidyNote(_ raw: String) -> String? {
        let t = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : String(t.prefix(maxNote))
    }

    /// The first workday after `now`'s day (tomorrow if none in the next 70 days looks like one).
    static func nextWorkday(after now: Date, isWorkday: (Date) -> Bool) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for i in 1...70 {
            if let d = cal.date(byAdding: .day, value: i, to: today), isWorkday(d) { return d }
        }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// When "done for today" ends: the start of the next workday's work hours.
    static func nextWorkdayStart(after now: Date, workStart: Int, isWorkday: (Date) -> Bool) -> Date {
        DayMath.at(hour: workStart, on: nextWorkday(after: now, isWorkday: isWorkday))
    }
}

/// Tomorrow's frog and note, and "done for today", saved until the day they are for is over.
final class DayPlanStore: ObservableObject {
    @Published private(set) var plans: [DayPlan] = []
    @Published private(set) var doneUntil: Date?
    private let defaults: UserDefaults?

    init(persist: Bool = true) {
        defaults = persist ? .standard : nil
        if let data = defaults?.data(forKey: "dayPlans"), let p = try? JSONDecoder().decode([DayPlan].self, from: data) {
            plans = p
        }
        if let d = defaults?.object(forKey: "doneUntil") as? Date, d > Date(), d < Date().addingTimeInterval(75 * 86400) {
            doneUntil = d
        }
        prune(today: DayMath.key(Date()))
    }

    func plan(for day: String) -> DayPlan? { plans.first { $0.day == day } }

    /// One plan per day; a plan with neither a frog nor a note clears it.
    func set(_ plan: DayPlan) {
        var p = plans.filter { $0.day != plan.day }
        if plan.frogId != nil || plan.note != nil { p.append(plan) }
        plans = Array(p.sorted { $0.day < $1.day }.prefix(7))
        save()
    }

    func prune(today: String) {
        let kept = plans.filter { $0.day >= today }
        if kept.count != plans.count {
            plans = kept
            save()
        }
    }

    func setDone(until: Date?) {
        doneUntil = until
        save()
    }

    func isDoneForToday(_ now: Date) -> Bool { doneUntil.map { now < $0 } ?? false }

    private func save() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(plans) { defaults.set(data, forKey: "dayPlans") }
        defaults.set(doneUntil, forKey: "doneUntil")
    }
}
