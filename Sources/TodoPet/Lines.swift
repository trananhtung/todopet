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

    static func deleted(_ t: TodoTask) -> String {
        L("Đã xoá \(q(t)) 🗑 Danh sách gọn hơn rồi!", "Deleted \(q(t)) 🗑 One less thing on your list!")
    }

    /// Confirmation text shown before deleting; warns that sub-tasks and recurring series go too.
    static func confirmDelete(_ t: TodoTask) -> String {
        var s = L("Xoá hẳn khỏi Todoist (kèm việc con nếu có)", "Delete from Todoist for good (with any sub-tasks)")
        if t.isRecurring { s += L(", cả chuỗi lặp lại", ", including the whole recurring series") }
        return s + L("? Không khôi phục được.", "? This can't be undone.")
    }

    static func unplanned(_ t: TodoTask) -> String {
        L("Đã bỏ \(q(t)) khỏi kế hoạch (vẫn còn trong Todoist, không hạn). Nhẹ đầu hơn chưa? 🙂",
          "Took \(q(t)) off the plan (still in Todoist, no date). Feels lighter? 🙂")
    }

    // MARK: Pet life

    static func golden() -> String {
        L("✨ HIẾM! Bánh vàng cho bạn! ✨", "✨ RARE! A golden treat! ✨")
    }

    static func combo(_ n: Int) -> String {
        L("🔥 Combo ×\(n)! Đang cháy quá!", "🔥 Combo ×\(n)! You're on fire!")
    }

    static func cleaned(_ dirtLeft: Int) -> String {
        dirtLeft == 0 ? L("🛁 Mình sạch bong rồi!", "🛁 Squeaky clean again!") : L("🛁 Sạch hơn chút rồi…", "🛁 A bit cleaner…")
    }

    static func levelUp(_ s: Stage) -> String {
        L("⬆️ Mình lớn lên thành \(s.name)!", "⬆️ I grew up: \(s.name)!")
    }

    static func unlocked(_ items: [Accessory]) -> String {
        L("🎁 Mở khoá: ", "🎁 Unlocked: ") + items.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ")
    }

    static func streak(_ n: Int) -> String {
        L("🔥 Chuỗi \(n) ngày đạt mục tiêu — giữ nhé!", "🔥 \(n)-day streak — keep it going!")
    }

    static func dirty(_ dirt: Int) -> String {
        L("🪰 Mình bẩn quá… \(dirt) ngày rồi bạn không làm gì. Xong 1 việc để tắm cho mình nhé.",
          "🪰 I'm filthy… \(dirt) lazy day(s). Finish a task to give me a bath.")
    }

    static func hungry(_ satiety: Double, next: TodoTask?) -> String {
        let n = next.map { L(" Xong \(q($0)) cho mình ăn với 🥺", " Finish \(q($0)) and feed me 🥺") } ?? ""
        return satiety < 10 ? L("Đói lả rồi… 😵‍💫", "Starving… 😵‍💫") + n : L("Bụng mình réo rồi nè 🍙", "My tummy is rumbling 🍙") + n
    }

    static func grumble(_ next: TodoTask) -> String {
        pick([("Haizzz… 😮‍💨 \(q(next)) vẫn chưa ai đụng tới.", "Sigh… 😮‍💨 Nobody has touched \(q(next)) yet."),
              ("*giậm chân* Mình chờ \(q(next)) lâu lắm rồi đó 😤", "*stomps* I've been waiting for \(q(next)) forever 😤")])
    }

    static func parade(_ next: TodoTask) -> String {
        L("Mình sẽ diễu hành tới khi bạn làm \(q(next)) thì thôi! 📢", "I'm marching until you do \(q(next))! 📢")
    }

    static func block(app: String, next: TodoTask?) -> String {
        let n = next.map { L(" Làm \(q($0)) đi!", " Go do \(q($0))!") } ?? ""
        return L("(╯°□°)╯︵ ┻━┻ ĐỦ RỒI \(app.uppercased())!", "(╯°□°)╯︵ ┻━┻ ENOUGH \(app.uppercased())!") + n
    }

    static func distractionSummary(_ d: [String: Double]) -> String {
        let total = Int(d.values.reduce(0, +) / 60)
        let top = d.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \(Int($0.value / 60))'" }.joined(separator: ", ")
        return L("Hôm nay bạn ở mấy chỗ xao nhãng \(total) phút đó 😒 (\(top))",
                 "You spent \(total) minutes on distractions today 😒 (\(top))")
    }

    // Spoken lines (short, no emoji).
    static func voiceGrumble() -> String { pick([("Haizzz. Làm việc đi chứ.", "Sigh. Get to work."), ("Mình chán quá à.", "I'm so bored.")]) }
    static func voiceAngry(_ t: TodoTask) -> String { L("Ê! Làm \(TextClean.short(t.title, 30)) ngay!", "Hey! Do \(TextClean.short(t.title, 30)) now!") }
    static func voiceBlock(app: String) -> String { L("Tắt \(app) đi!", "Close \(app)!") }
    static func voiceHungry() -> String { L("Mình đói quá.", "I'm so hungry.") }
    static func voiceCheer() -> String { pick([("Tuyệt vời!", "Awesome!"), ("Hoan hô!", "Hooray!")]) }
    static func voiceSummary(minutes: Int) -> String { L("Hôm nay bạn lướt mạng \(minutes) phút đó.", "You goofed off for \(minutes) minutes today.") }

    // MARK: Xin vía

    static func wishOfDay(_ w: Wish) -> String {
        L("\(w.emoji) Vía hôm nay: “\(TextClean.short(w.title, 40))” — một bước nhỏ nào?",
          "\(w.emoji) Today's wish: “\(TextClean.short(w.title, 40))” — one small step?")
    }

    static func wishReminder(_ w: Wish) -> String {
        var s = L("✨ Nhắc vía: \(w.emoji) “\(w.title)”", "✨ Remember your wish: \(w.emoji) “\(w.title)”")
        if !w.why.isEmpty { s += "\n" + L("Vì: ", "Because: ") + w.why }
        if !w.plan.isEmpty {
            s += "\n" + L("Kế hoạch của bạn: ", "Your plan: ") + w.plan
        } else if !w.obstacle.isEmpty {
            s += "\n" + L("Nếu “\(TextClean.short(w.obstacle, 40))” xuất hiện, bạn sẽ làm gì?", "If “\(TextClean.short(w.obstacle, 40))” shows up, what will you do?")
        }
        if w.steps > 0 { s += "\n" + L("Đã đi được \(w.steps) bước rồi đó 💪", "\(w.steps) step(s) done so far 💪") }
        return s + "\n" + L("Hôm nay làm một bước nhỏ cho nó nhé?", "One small step for it today?")
    }

    static func blessing(_ w: Wish) -> String {
        let t = "“\(TextClean.short(w.title, 40))”"
        return pick([
            ("🙏 Đã truyền vía ✨ \(t) sẽ thành! Giờ làm một bước nhỏ để vía có chỗ bám nhé.",
             "🙏 Good vibes sent ✨ \(t) will happen! Now give them a small step to hold on to."),
            ("🍀 Vía may mắn đã gửi! Nhắm mắt 5 giây: thấy mình đạt \(t) chưa? Giờ nghĩ trở ngại lớn nhất… và bước đầu tiên.",
             "🍀 Lucky vibes sent! Close your eyes for 5 seconds: see yourself achieving \(t)? Now the biggest obstacle… and the first step."),
            ("✨ Xin vía thành công! Mà vía mạnh nhất là vía của người bắt tay vào làm 😉",
             "✨ Blessing granted! But the strongest luck belongs to whoever starts 😉"),
        ])
    }

    static func wishStepAdded(_ w: Wish) -> String {
        L("Đã thêm bước nhỏ cho “\(TextClean.short(w.title, 40))” vào hôm nay ✨", "Added a small step towards “\(TextClean.short(w.title, 40))” for today ✨")
    }

    static func wishStepDone(_ w: Wish) -> String {
        L("✨ Vía về rồi! \(w.steps) bước cho \(w.emoji) “\(TextClean.short(w.title, 40))”",
          "✨ The vibes worked! \(w.steps) step(s) towards \(w.emoji) “\(TextClean.short(w.title, 40))”")
    }

    static func voiceBlessing() -> String { L("Đã truyền vía. Cố lên nhé!", "Good vibes sent. You've got this!") }

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
