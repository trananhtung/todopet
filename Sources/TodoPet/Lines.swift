import Foundation

/// Everything the pet says, in both languages. Tone follows the mood.
enum Lines {
    static func q(_ t: TodoTask) -> String { "“\(TextClean.short(t.title))”" }

    static func greeting(_ now: Date) -> String {
        switch DayMath.hour(now) {
        case ..<11: L("Chào buổi sáng! ☀️", "Good morning! ☀️")
        case ..<13: L("Chào buổi trưa! 🌤", "Good day! 🌤")
        case ..<18: L("Chào buổi chiều! 🌇", "Good afternoon! 🌇")
        default: L("Chào buổi tối! 🌙", "Good evening! 🌙")
        }
    }

    static func hello(name: String) -> String {
        L("Xin chào! Mình là \(name) 🐾 Cho mình API token Todoist để mình giữ nhịp làm việc cho bạn nhé.",
          "Hi! I'm \(name) 🐾 Give me your Todoist API token and I'll keep you on track.")
    }

    static func morning(_ now: Date, day: DaySnapshot, target: Int) -> String {
        let g = greeting(now)
        if day.planned < target {
            return g + " " + L("Hôm nay mình làm \(target) việc gì nào? Mới có \(day.planned)/\(target) việc thôi 📝",
                               "What are our \(target) things today? Only \(day.planned)/\(target) planned so far 📝")
        }
        if let next = day.next {
            return g + " " + L("Hôm nay có \(day.open.count) việc. Ăn con ếch trước: \(q(next)) 🐸",
                               "\(day.open.count) tasks today. Eat the frog first: \(q(next)) 🐸")
        }
        return g
    }

    static func plan(mood: Mood, planned: Int, target: Int) -> String {
        let k = target - planned
        switch mood {
        case .angry:
            return pick([("Muộn thế này rồi mà chưa có kế hoạch?! Đặt ngay \(k) việc nữa đi 😤",
                          "It's this late and still no plan?! Add \(k) more tasks now 😤"),
                         ("Không có kế hoạch = không có tiến độ! Thêm \(k) việc NGAY 💢",
                          "No plan = no progress! Add \(k) tasks NOW 💢")])
        case .annoyed:
            return pick([("Này… hôm nay vẫn chưa đủ \(target) việc đâu nha 😒 (\(planned)/\(target))",
                          "Hey… still not \(target) tasks for today 😒 (\(planned)/\(target))"),
                         ("Hôm nay làm gì vậy? Mình vẫn chờ \(k) việc nữa đó 😑",
                          "So what are we doing today? Still waiting for \(k) more 😑")])
        default:
            return pick([("Hôm nay mình làm \(target) việc gì nào? Mới có \(planned)/\(target) việc 📝",
                          "What are our \(target) things today? \(planned)/\(target) planned 📝"),
                         ("Chọn \(k) việc quan trọng nhất cho hôm nay nhé ✍️",
                          "Pick the \(k) most important tasks for today ✍️")])
        }
    }

    static func nudge(mood: Mood, next: TodoTask, hoursIdle: Double) -> String {
        switch mood {
        case .happy:
            return pick([("Đang ngon trớn! Tiếp theo là \(q(next)) nha ✨", "On a roll! Next up: \(q(next)) ✨"),
                         ("Mình thích nhịp này! Làm luôn \(q(next)) nhé 💪", "Love this pace! Let's do \(q(next)) 💪")])
        case .annoyed:
            return pick([("Ừm… \(q(next)) vẫn nằm đó. Làm 10 phút thôi cũng được mà 😑",
                          "Ahem… \(q(next)) is still waiting. Even 10 minutes helps 😑"),
                         ("Mình hơi buồn đó… bắt đầu \(q(next)) đi 😒", "I'm a bit sad… start \(q(next)) 😒")])
        case .angry:
            let h = max(1, Int(hoursIdle.rounded()))
            return pick([("\(h) tiếng rồi chưa xong việc nào! Làm \(q(next)) NGAY 😠",
                          "\(h)h and nothing done! Do \(q(next)) NOW 😠"),
                         ("Mình giận thật rồi đó 💢 \(q(next)) — bắt đầu đi!", "I'm really mad 💢 \(q(next)) — start it!")])
        default:
            return pick([("Việc tiếp theo: \(q(next)). Làm một phiên tập trung không?",
                          "Next: \(q(next)). Want a focus session?"),
                         ("Nhắc nhẹ: \(q(next)) đang chờ bạn 🙂", "Gentle nudge: \(q(next)) is waiting 🙂")])
        }
    }

    static func overdue(mood: Mood, count: Int) -> String {
        if mood == .angry {
            return L("\(count) việc QUÁ HẠN kìa!! 💢 Làm hoặc dời đi chứ!", "\(count) OVERDUE tasks!! 💢 Do them or move them!")
        }
        return L("Có \(count) việc quá hạn 😬 Làm luôn hay dời vào hôm nay?", "\(count) overdue task(s) 😬 Do them or move to today?")
    }

    static func distraction(mood: Mood, app: String, left: Int, next: TodoTask?) -> String {
        if mood == .angry, let next {
            return L("\(app) nữa hả?!! Đóng lại đi, \(q(next)) đang chờ 😤", "\(app) AGAIN?! Close it, \(q(next)) is waiting 😤")
        }
        return pick([("Ê! Đang \(app) đó hả? 👀 Còn \(left) việc kìa.", "Hey! On \(app)? 👀 \(left) task(s) left."),
                     ("Mình thấy bạn mở \(app) nha 👀 Quay lại làm việc chứ?", "I see \(app) 👀 Back to work?")])
    }

    static func done(_ t: TodoTask, completed: Int, target: Int) -> String {
        if completed == target {
            return L("Đủ \(target) việc rồi!!! Bạn là nhất 🏆", "That's \(target)!!! You're the best 🏆")
        }
        return pick([("Xong \(q(t))! 🎉 (\(completed)/\(target))", "Done: \(q(t))! 🎉 (\(completed)/\(target))"),
                     ("Tuyệt vời! ✔︎ \(q(t))", "Awesome! ✔︎ \(q(t))"),
                     ("Yay! Mình vui quá 🥳 (\(completed)/\(target))", "Yay! So happy 🥳 (\(completed)/\(target))"),
                     ("Giỏi quá! Tiếp tục giữ nhịp nhé 💪", "Nice! Keep the rhythm 💪")])
    }

    static func allDone() -> String {
        L("Xong hết việc hôm nay rồi! 🎉 Nghỉ ngơi, hoặc chọn sẵn 3 việc cho mai nhé.",
          "Everything's done for today! 🎉 Rest, or pick tomorrow's 3 tasks.")
    }

    static func review(completed: Int, planned: Int, remaining: Int) -> String {
        L("Sắp hết giờ làm. Hôm nay xong \(completed)/\(planned) việc. Còn \(remaining) việc — dời sang mai?",
          "Almost end of day: \(completed)/\(planned) done. Move the remaining \(remaining) to tomorrow?")
    }

    static func welcomeBack(_ t: TodoTask) -> String {
        L("Bạn về rồi! 👋 Tiếp tục với \(q(t)) nhé?", "Welcome back! 👋 Continue with \(q(t))?")
    }

    static func soon(_ t: TodoTask, minutes: Int) -> String {
        L("⏰ \(minutes) phút nữa: \(q(t))", "⏰ In \(minutes) min: \(q(t))")
    }

    static func dueNow(_ t: TodoTask) -> String {
        L("⏰ Đến giờ rồi: \(q(t))!", "⏰ It's time: \(q(t))!")
    }

    static func focusStart(_ t: TodoTask?, minutes: Int) -> String {
        if let t { return L("Bắt đầu \(minutes) phút cho \(q(t)). Mình sẽ ngồi im canh bạn 🤫", "\(minutes) minutes on \(q(t)). I'll sit quietly and guard 🤫") }
        return L("Bắt đầu \(minutes) phút tập trung. Mình ngồi im canh nhé 🤫", "\(minutes) minutes of focus. I'll stay quiet 🤫")
    }

    static func focusEnd(_ t: TodoTask?, minutes: Int) -> String {
        if let t { return L("Hết \(minutes) phút rồi! \(q(t)) xong chưa?", "\(minutes) minutes up! Is \(q(t)) done?") }
        return L("Hết \(minutes) phút rồi! Nghỉ chút nhé?", "\(minutes) minutes up! Take a break?")
    }

    static func breakEnd() -> String {
        L("Hết giờ nghỉ! Quay lại thôi 💪", "Break's over! Let's go 💪")
    }

    static func added(_ title: String) -> String {
        L("Đã thêm “\(TextClean.short(title))” ✔︎", "Added “\(TextClean.short(title))” ✔︎")
    }

    static func planComplete(target: Int, next: TodoTask?) -> String {
        if let next {
            return L("Đủ \(target) việc cho hôm nay rồi! Bắt đầu với \(q(next)) nhé 🐸", "\(target) tasks planned! Start with \(q(next)) 🐸")
        }
        return L("Đủ \(target) việc cho hôm nay rồi! 🐸", "\(target) tasks planned for today! 🐸")
    }

    static func lateNight() -> String {
        L("Khuya rồi đó… đi ngủ để mai làm tốt hơn nha 😴", "It's late… sleep now, crush it tomorrow 😴")
    }

    static func error(_ e: String) -> String {
        L("Mình không kết nối được Todoist 😵 \(e)", "I can't reach Todoist 😵 \(e)")
    }

    // MARK: Calendar

    static func meetingSoon(_ e: CalEvent, minutes: Int) -> String {
        L("📅 \(minutes) phút nữa họp: “\(TextClean.short(e.title))” (\(DayMath.timeString(e.start)))",
          "📅 Meeting in \(minutes) min: “\(TextClean.short(e.title))” (\(DayMath.timeString(e.start)))")
    }

    static func calendarDay(meetings: Int, busyMinutes: Double, freeMinutes: Double, target: Int, reduced: Bool) -> String {
        let busy = CalendarMath.hoursText(busyMinutes), free = CalendarMath.hoursText(freeMinutes)
        let base = L("📅 Hôm nay \(meetings) cuộc họp (\(busy)), còn \(free) trống",
                     "📅 \(meetings) meeting(s) today (\(busy)), \(free) free")
        return base + (reduced ? L(" → \(target) việc là vừa sức.", " → \(target) task(s) is realistic.") : ".")
    }

    static func timeBlock(_ s: SlotSuggestion) -> String {
        L("Gắn giờ cho dễ bắt đầu: \(DayMath.timeString(s.start))–\(DayMath.timeString(s.end)) làm \(q(s.task)) nhé?",
          "A set time makes it easier to start: \(DayMath.timeString(s.start))–\(DayMath.timeString(s.end)) for \(q(s.task))?")
    }

    static func timeSet(_ t: TodoTask, at: Date) -> String {
        L("Đã hẹn \(q(t)) lúc \(DayMath.timeString(at)). Mình sẽ nhắc đúng giờ ⏰", "Scheduled \(q(t)) at \(DayMath.timeString(at)). I'll remind you ⏰")
    }

    // MARK: Postponed tasks

    static func stuck(_ s: StuckTask, mood: Mood) -> String {
        if mood == .angry {
            return L("\(q(s.task)) nằm đó \(s.days) ngày rồi đấy!! 💢 Chia nhỏ hoặc bỏ đi.",
                     "\(q(s.task)) has been sitting there for \(s.days) days!! 💢 Split it or drop it.")
        }
        return pick([("\(q(s.task)) bị dời \(s.days) ngày rồi 😑 Chắc nó to quá? Chia thành bước nhỏ cho dễ bắt đầu nhé.",
                      "\(q(s.task)) has been pushed for \(s.days) days 😑 Too big? Let's split it into small steps."),
                     ("Mình thấy \(q(s.task)) cứ bị dời mãi (\(s.days) ngày). Bước nhỏ nhất để bắt đầu là gì?",
                      "\(q(s.task)) keeps getting postponed (\(s.days) days). What's the tiniest first step?")])
    }

    static func splitDone(count: Int, first: String) -> String {
        L("Đã chia thành \(count) bước ✂️ Bắt đầu với “\(TextClean.short(first))” nhé — chỉ 15–30 phút thôi!",
          "Split into \(count) steps ✂️ Start with “\(TextClean.short(first))” — just 15–30 minutes!")
    }

    static func unplanned(_ t: TodoTask) -> String {
        L("Đã bỏ \(q(t)) khỏi kế hoạch (vẫn còn trong Todoist, không hạn). Nhẹ đầu hơn chưa? 🙂",
          "Took \(q(t)) off the plan (still in Todoist, no date). Feels lighter? 🙂")
    }

    /// Short, evidence-based productivity tips the pet drops occasionally.
    static func tip() -> String {
        pick([
            ("Mẹo: làm việc khó nhất trước (Eat the frog 🐸) — năng lượng đầu ngày là tốt nhất.",
             "Tip: do the hardest task first (eat the frog 🐸) — early energy is your best."),
            ("Mẹo: việc to quá? Chia thành bước 15–30 phút rồi thêm vào Todoist.",
             "Tip: task too big? Split it into 15–30 minute steps in Todoist."),
            ("Mẹo: gắn giờ cụ thể (“14h làm X”) giúp bạn dễ bắt tay vào việc hơn hẳn.",
             "Tip: give tasks a concrete time (“2pm: do X”) — it makes starting much easier."),
            ("Mẹo: cuối ngày dành 5 phút chọn sẵn 3 việc cho mai — sáng mai vào việc ngay.",
             "Tip: spend 5 minutes at day's end picking tomorrow's 3 tasks."),
            ("Mẹo: mỗi lần bị gián đoạn cần khá lâu để tập trung lại — tắt thông báo khi tập trung nhé.",
             "Tip: every interruption costs a long refocus — mute notifications while focusing."),
            ("Mẹo: uống nước & đứng dậy vươn vai sau mỗi phiên tập trung 💧",
             "Tip: drink water and stretch after each focus session 💧"),
        ])
    }
}
