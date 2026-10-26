import AppKit
import EventKit

/// A busy block from the macOS Calendar (all calendars the Calendar app shows, incl. Google/Exchange accounts).
struct CalEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL?

    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// A suggested time block for a task, inside a free slot of today's calendar.
struct SlotSuggestion: Identifiable, Hashable {
    let task: TodoTask
    let start: Date
    let end: Date
    var id: String { task.id }
}

enum CalendarAccess {
    case notDetermined, granted, denied
}

@MainActor
final class CalendarWatcher {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    /// Sample meetings used by `--demo` and snapshots.
    var demoEvents: [CalEvent]?

    var access: CalendarAccess {
        if demoEvents != nil { return .granted }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func onChange(_ handler: @escaping () -> Void) {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            handler()
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Today's timed, busy, non-declined events.
    func events(on day: Date) -> [CalEvent] {
        if let demoEvents { return demoEvents }
        guard access == .granted else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { e -> CalEvent? in
            guard !e.isAllDay, e.status != .canceled, e.availability != .free else { return nil }
            if let me = e.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined { return nil }
            return CalEvent(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)", title: e.title ?? "",
                            start: e.startDate, end: e.endDate, joinURL: CalendarMath.joinURL(url: e.url, texts: [e.location, e.notes]))
        }
        .sorted { $0.start < $1.start }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Pure calendar arithmetic, covered by `--selftest`.
enum CalendarMath {
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com"]

    /// Finds a video-call link in the event URL, location or notes.
    static func joinURL(url: URL?, texts: [String?]) -> URL? {
        if let url, let host = url.host?.lowercased(), meetingHosts.contains(where: { host.hasSuffix($0) }) { return url }
        let pattern = #"https?://[^\s<>"']+"#
        for text in texts.compactMap({ $0 }) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { break }
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text), let u = URL(string: String(text[r])),
                      let host = u.host?.lowercased(), meetingHosts.contains(where: { host.hasSuffix($0) }) else { continue }
                return u
            }
        }
        return url
    }

    /// Busy intervals clipped to [from, to] and merged when they overlap.
    static func busy(_ events: [CalEvent], from: Date, to: Date) -> [DateInterval] {
        let clipped = events.compactMap { e -> DateInterval? in
            let s = max(e.start, from), t = min(e.end, to)
            return s < t ? DateInterval(start: s, end: t) : nil
        }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for i in clipped {
            if let last = merged.last, i.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, i.end))
            } else {
                merged.append(i)
            }
        }
        return merged
    }

    static func freeSlots(_ events: [CalEvent], from: Date, to: Date, minMinutes: Double = 30) -> [DateInterval] {
        guard from < to else { return [] }
        var slots: [DateInterval] = []
        var cursor = from
        for b in busy(events, from: from, to: to) {
            if b.start.timeIntervalSince(cursor) >= minMinutes * 60 { slots.append(DateInterval(start: cursor, end: b.start)) }
            cursor = max(cursor, b.end)
        }
        if to.timeIntervalSince(cursor) >= minMinutes * 60 { slots.append(DateInterval(start: cursor, end: to)) }
        return slots
    }

    static func freeMinutes(_ events: [CalEvent], from: Date, to: Date) -> Double {
        guard from < to else { return 0 }
        let busyMinutes = busy(events, from: from, to: to).reduce(0) { $0 + $1.duration / 60 }
        return to.timeIntervalSince(from) / 60 - busyMinutes
    }

    /// About one meaningful task per 2 free hours, capped by the user's daily target.
    static func target(freeMinutes: Double, maxTarget: Int) -> Int {
        max(1, min(maxTarget, Int((freeMinutes / 120).rounded(.up))))
    }

    static func current(_ events: [CalEvent], at now: Date) -> CalEvent? {
        events.first { $0.start <= now && now < $0.end }
    }

    static func next(_ events: [CalEvent], after now: Date) -> CalEvent? {
        events.first { $0.start > now }
    }

    /// Places the top tasks (without a time yet) into today's next free slots.
    static func suggest(tasks: [TodoTask], events: [CalEvent], now: Date, dayEnd: Date, limit: Int = 3) -> [SlotSuggestion] {
        let quarter: TimeInterval = 15 * 60
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
        var slots = freeSlots(events, from: start, to: dayEnd, minMinutes: 30)
        var out: [SlotSuggestion] = []
        for task in tasks where task.dueTime == nil && !task.isRecurring {
            guard out.count < limit else { break }
            let wanted = Double(task.duration?.minutes ?? 60) * 60
            guard let i = slots.firstIndex(where: { $0.duration >= min(wanted, 30 * 60) }) else { break }
            let slot = slots[i]
            let end = slot.start.addingTimeInterval(min(wanted, slot.duration))
            out.append(SlotSuggestion(task: task, start: slot.start, end: end))
            let rest = end.addingTimeInterval(10 * 60)
            if rest < slot.end { slots[i] = DateInterval(start: rest, end: slot.end) } else { slots.remove(at: i) }
        }
        return out
    }

    static func hoursText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(String(format: "%02d", m % 60))"
    }
}
