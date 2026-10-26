import Foundation

enum Mood: String, CaseIterable {
    case happy, normal, annoyed, angry, sleeping, focus, celebrating

    var emoji: String {
        switch self {
        case .happy: "😊"
        case .normal: "🙂"
        case .annoyed: "😒"
        case .angry: "😤"
        case .sleeping: "😴"
        case .focus: "🎯"
        case .celebrating: "🥳"
        }
    }

    var label: String {
        switch self {
        case .happy: L("đang vui", "happy")
        case .normal: L("bình thường", "chill")
        case .annoyed: L("đang nhăn nhó", "annoyed")
        case .angry: L("nổi cáu rồi", "grumpy")
        case .sleeping: L("đang ngủ", "sleeping")
        case .focus: L("đang canh bạn tập trung", "guarding your focus")
        case .celebrating: L("đang ăn mừng", "celebrating")
        }
    }
}

struct MoodInputs {
    var hasToken = true
    var workday = true
    var inWorkHours = true
    var night = false
    var hoursAfterPlanDeadline: Double = -1   // < 0 means the deadline hasn't passed yet
    var target = 3
    var planned = 0
    var completed = 0
    var remaining = 0
    var overdue = 0
    var late = 0
    var minutesSinceProgress: Double = 0
    var minutesSinceCelebration: Double = .infinity
    var distractedMinutes: Double = 0
    var distractionApp = ""
    var idleMinutes: Double = 0
    var focusing = false
    var celebratingNow = false
    var inMeeting = false
    var stuck = 0
    var satiety: Double = 70
    var dirt = 0
}

struct MoodReason: Identifiable, Hashable {
    let id = UUID()
    let delta: Int
    let text: String
}

/// Turns "how is my day going" into a 0–100 happiness score and a mood. Pure, so it's unit-tested.
enum MoodEngine {
    static func evaluate(_ i: MoodInputs) -> (score: Double, mood: Mood, reasons: [MoodReason]) {
        var reasons: [MoodReason] = []
        var s = 60.0
        func add(_ d: Double, _ text: String) {
            guard abs(d) >= 1 else { return }
            s += d
            reasons.append(MoodReason(delta: Int(d.rounded()), text: text))
        }

        if i.completed > 0 {
            add(Double(min(i.completed, 5)) * 8, L("đã xong \(i.completed) việc hôm nay", "\(i.completed) task(s) done today"))
        }
        if i.completed > 0 && i.remaining == 0 && i.overdue == 0 && i.planned >= i.target {
            add(30, L("xong hết kế hoạch hôm nay", "today's plan is complete"))
        }
        if i.minutesSinceCelebration < 30 {
            add(15 * (1 - i.minutesSinceCelebration / 30), L("vừa hoàn thành một việc", "just finished something"))
        }
        if i.overdue > 0 {
            add(-Double(min(i.overdue, 5)) * 7, L("\(i.overdue) việc quá hạn", "\(i.overdue) overdue task(s)"))
        }
        if i.late > 0 {
            add(-Double(min(i.late, 3)) * 4, L("\(i.late) việc đã trễ giờ", "\(i.late) task(s) past their time"))
        }
        if i.satiety < 30 {
            add(-(30 - i.satiety) / 2, L("đang đói (no \(Int(i.satiety))%)", "hungry (\(Int(i.satiety))% full)"))
        }
        if i.dirt > 0 {
            add(-Double(i.dirt) * 5, L("bẩn vì \(i.dirt) ngày lười", "dirty after \(i.dirt) lazy day(s)"))
        }
        if i.stuck > 0 {
            add(-Double(min(i.stuck, 3)) * 3, L("\(i.stuck) việc bị dời mãi", "\(i.stuck) task(s) keep getting postponed"))
        }
        if i.workday && i.inWorkHours && !i.inMeeting {
            if i.hoursAfterPlanDeadline >= 0 && i.planned < i.target {
                let gap = Double(i.target - i.planned)
                add(-(12 + gap * 6 + min(20, i.hoursAfterPlanDeadline * 8)),
                    L("mới lên kế hoạch \(i.planned)/\(i.target) việc", "only \(i.planned)/\(i.target) tasks planned"))
            }
            if i.remaining + i.overdue > 0 && i.minutesSinceProgress > 90 {
                let hours = i.minutesSinceProgress / 60
                add(-min(30, (i.minutesSinceProgress - 90) / 60 * 10),
                    L("\(String(format: "%.1f", hours)) giờ chưa có tiến triển", "no progress for \(String(format: "%.1f", hours))h"))
            }
            if i.distractedMinutes >= 2 {
                add(-min(35, 15 + i.distractedMinutes * 2), L("đang xao nhãng với \(i.distractionApp)", "distracted by \(i.distractionApp)"))
            }
        }
        if i.focusing { add(10, L("đang tập trung", "focusing")) }

        if !(i.workday && i.inWorkHours) && s < 55 {
            // Outside work hours the pet relaxes, it only remembers the bad stuff a little.
            s = 55
        }
        s = min(100, max(0, s))

        let mood: Mood
        if i.celebratingNow { mood = .celebrating }
        else if !i.hasToken { mood = .normal }
        else if i.focusing { mood = .focus }
        else if i.night || i.idleMinutes > 10 { mood = .sleeping }
        else if s >= 75 { mood = .happy }
        else if s >= 50 { mood = .normal }
        else if s >= 30 { mood = .annoyed }
        else { mood = .angry }

        return (s, mood, reasons.sorted { abs($0.delta) > abs($1.delta) })
    }
}
