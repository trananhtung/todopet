import AppKit
import SwiftUI

/// `--selftest` runs the logic checks; `--snapshot <dir>` renders the pet, board and bubble to PNG files.
@MainActor
enum DevTools {
    // MARK: Self test

    static func selfTest() -> Bool {
        var fails = 0
        func check(_ ok: Bool, _ name: String) {
            print((ok ? "✅ " : "❌ ") + name)
            if !ok { fails += 1 }
        }
        let cal = Calendar.current

        // Dates.
        check(DateParse.parse("2026-10-25") != nil, "parse all-day date")
        let a = DateParse.parse("2026-10-25T02:00:00Z")
        check(a != nil && a == DateParse.parse("2026-10-25T02:00:00.000000Z"), "parse UTC with and without microseconds")
        let floating = DateParse.parse("2026-10-25T09:30:00")
        check(floating.map { cal.component(.hour, from: $0) == 9 && cal.component(.minute, from: $0) == 30 } ?? false,
              "floating time is local time")

        // API v1 payload.
        let json = """
        {"results":[{"id":"6X7rM8997g3RQmvh","user_id":"1","project_id":"6Jf8VQXxpwv56VQ7","section_id":null,"parent_id":null,
        "added_by_uid":"1","assigned_by_uid":null,"responsible_uid":null,"labels":["work"],"deadline":null,"duration":null,
        "checked":false,"is_deleted":false,"added_at":"2026-10-20T08:00:00.000000Z","completed_at":null,
        "updated_at":"2026-10-20T08:00:00.000000Z","due":{"date":"2026-10-25T15:00:00","timezone":null,"string":"today at 3pm",
        "lang":"en","is_recurring":false},"priority":4,"child_order":1,"content":"**Viết** [báo cáo](https://example.com)",
        "description":"","note_count":0,"day_order":-1,"is_collapsed":false}],"next_cursor":null}
        """
        struct Page: Decodable { var results: [TodoTask] }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        if let page = try? dec.decode(Page.self, from: Data(json.utf8)), let t = page.results.first {
            check(t.title == "Viết báo cáo", "markdown stripped from title")
            check(t.uiPriority == 1, "API priority 4 is P1")
            check(t.dueTime.map { cal.component(.hour, from: $0) == 15 } ?? false, "due time parsed")
            check(t.labels == ["work"] && t.isRecurring == false, "labels and recurrence decoded")
        } else {
            check(false, "decode API v1 task page")
        }

        // Day snapshot.
        let now = DayMath.at(hour: 11, on: DateParse.parse("2026-10-25")!)
        let tasks = [
            TodoTask(id: "o", content: "old", priority: 1, due: TodoDue(date: "2026-10-24")),
            TodoTask(id: "a", content: "all day", priority: 1, due: TodoDue(date: "2026-10-25")),
            TodoTask(id: "l", content: "late", priority: 1, due: TodoDue(date: "2026-10-25T09:00:00")),
            TodoTask(id: "u", content: "urgent", priority: 4, due: TodoDue(date: "2026-10-25")),
            TodoTask(id: "f", content: "future", priority: 4, due: TodoDue(date: "2026-10-26")),
        ]
        let done = [TodoTask(id: "d", content: "done", completedAt: "2026-10-25T01:00:00Z")]
        let day = DaySnapshot.build(active: tasks, completed: done, now: now)
        check(day.overdue.map(\.id) == ["o"], "overdue bucket")
        check(day.today.count == 3 && day.late.map(\.id) == ["l"], "today and late buckets")
        check(day.planned == 4 && day.remaining == 3, "planned counts completed + today")
        check(day.next?.id == "u", "next task is the highest priority (eat the frog)")

        // Moods.
        var i = MoodInputs()
        i.hoursAfterPlanDeadline = -1.5
        check(MoodEngine.evaluate(i).mood == .normal, "before plan deadline with nothing planned: chill")
        i.hoursAfterPlanDeadline = 2
        check(MoodEngine.evaluate(i).mood == .annoyed, "2h after plan deadline, nothing planned: worried (only distractions make it grumpy)")
        i = MoodInputs()
        i.planned = 3; i.completed = 2; i.remaining = 1; i.minutesSinceCelebration = 3
        check(MoodEngine.evaluate(i).mood == .happy, "2/3 done and just finished one: happy")
        i = MoodInputs()
        i.planned = 3; i.completed = 3; i.remaining = 0
        let allDone = MoodEngine.evaluate(i)
        check(allDone.mood == .happy && allDone.score >= 99, "all done: happiest")
        i = MoodInputs()
        i.planned = 3; i.remaining = 3; i.overdue = 3; i.minutesSinceProgress = 240
        check(MoodEngine.evaluate(i).mood == .annoyed, "overdue + 4h without progress: worried, not grumpy")
        i = MoodInputs()
        i.planned = 3; i.remaining = 3; i.minutesSinceProgress = 30; i.distractedMinutes = 5; i.distractionApp = "TikTok"
        let distracted = MoodEngine.evaluate(i).mood
        check(distracted == .annoyed || distracted == .angry, "distraction app: worried or grumpy")
        i.overdue = 3; i.distractedMinutes = 10
        check(MoodEngine.evaluate(i).mood == .angry, "grumpy only while on a distraction")
        i = MoodInputs()
        i.planned = 1; i.hoursAfterPlanDeadline = 3; i.overdue = 5
        i.doneForToday = true
        check(MoodEngine.evaluate(i).mood == .sleeping, "done for today: the pet sleeps")
        i = MoodInputs()
        i.night = true
        check(MoodEngine.evaluate(i).mood == .sleeping, "night: sleeping")
        i = MoodInputs()
        i.inWorkHours = false; i.overdue = 5; i.planned = 0
        check(MoodEngine.evaluate(i).mood == .normal, "outside work hours: relaxed")
        i = MoodInputs()
        i.focusing = true
        check(MoodEngine.evaluate(i).mood == .focus, "focus session")

        i = MoodInputs()
        i.planned = 3; i.remaining = 3; i.minutesSinceProgress = 300; i.inMeeting = true
        check(MoodEngine.evaluate(i).mood == .normal, "no grumpiness during meetings")

        // Browser distraction rules.
        let rules = ["youtube.com", "facebook.com", "reddit.com/r/funny"]
        check(BrowserWatcher.match(host: "m.youtube.com", url: "https://m.youtube.com/watch?v=1", rules: rules) == "youtube.com",
              "site rule matches subdomains")
        check(BrowserWatcher.match(host: "notyoutube.com", url: "https://notyoutube.com/", rules: rules) == nil,
              "site rule ignores look-alike domains")
        check(BrowserWatcher.match(host: "reddit.com", url: "https://www.reddit.com/r/funny/top", rules: rules) == "reddit.com/r/funny",
              "path rule matches")
        check(BrowserWatcher.match(host: "reddit.com", url: "https://www.reddit.com/r/swift", rules: rules) == nil,
              "path rule only matches that path")
        check(BrowserWatcher.host(of: "https://www.Facebook.com/home") == "facebook.com", "host normalized")

        // Calendar math (now = 2026-10-25 11:00).
        let base = DayMath.at(hour: 8, on: now)
        let dayEnd = DayMath.at(hour: 18, on: now)
        func meeting(_ h: Double, _ hours: Double) -> CalEvent {
            CalEvent(id: "\(h)", title: "m", start: base.addingTimeInterval(h * 3600),
                     end: base.addingTimeInterval((h + hours) * 3600), joinURL: nil)
        }
        let events = [meeting(1, 1), meeting(1.5, 1), meeting(5, 0.5)]  // 9:00–10:30 (overlapping) and 13:00–13:30
        check(CalendarMath.busy(events, from: base, to: dayEnd).count == 2, "overlapping meetings merge")
        check(abs(CalendarMath.freeMinutes(events, from: base, to: dayEnd) - 480) < 0.1, "free minutes")
        check(CalendarMath.freeSlots(events, from: base, to: dayEnd).count == 3, "free slots between meetings")
        check(CalendarMath.target(freeMinutes: 480, maxTarget: 3) == 3 && CalendarMath.target(freeMinutes: 200, maxTarget: 3) == 2
              && CalendarMath.target(freeMinutes: 60, maxTarget: 3) == 1, "target follows free time")
        let slotTasks = [TodoTask(id: "a", content: "A", priority: 4, due: TodoDue(date: "2026-10-25")),
                         TodoTask(id: "b", content: "B", priority: 1, due: TodoDue(date: "2026-10-25"),
                                  duration: TodoDuration(amount: 30, unit: "minute"))]
        let sug = CalendarMath.suggest(tasks: slotTasks, events: events, now: base.addingTimeInterval(50 * 60), dayEnd: dayEnd)
        check(sug.first.map { cal.component(.hour, from: $0.start) == 10 && cal.component(.minute, from: $0.start) == 30 } ?? false,
              "first suggestion starts after the meeting")
        check(sug.count == 2 && sug[1].end.timeIntervalSince(sug[1].start) == 1800, "task duration respected")
        check(CalendarMath.joinURL(url: nil, texts: ["Join: https://us02web.zoom.us/j/123?pwd=x thanks"])?.host == "us02web.zoom.us",
              "meeting link found in notes")

        // Postponed tasks.
        check(StuckTracker.days(seen: 1, dueDay: "2026-10-22", today: "2026-10-25") == 4, "overdue 3 days = 4 days on the list")
        let tracker = StuckTracker(persist: false)
        let s = TodoTask(id: "s", content: "S", due: TodoDue(date: "2026-10-25"))
        for d in [-2.0, -1, 0, 0] { tracker.record([s], now: now.addingTimeInterval(d * 86_400)) }
        check(tracker.stuck([s], minDays: 3, now: now).first?.days == 3, "tracker counts distinct days")
        let parent = TodoTask(id: "p", content: "Big", priority: 4, due: TodoDue(date: "2026-10-25"))
        let child = TodoTask(id: "c", content: "Small", priority: 4, due: TodoDue(date: "2026-10-25"), parentId: "p")
        check(DaySnapshot.build(active: [parent, child], completed: [], now: now).next?.id == "c", "first step comes before the big task")

        // Claude answers.
        let answer = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"steps\":[\"Mở file\",\" Viết dàn ý \",\"\"]}"}],"stop_reason":"end_turn"}"#
        check((try? ClaudeClient.parseSteps(Data(answer.utf8))) == ["Mở file", "Viết dàn ý"], "Claude steps parsed")
        var refused = false
        do { _ = try ClaudeClient.parseSteps(Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)) } catch ClaudeError.refused { refused = true } catch {}
        check(refused, "Claude refusal detected")

        // Pet life: feeding, combos, golden treats, unlocks.
        check(Stage.of(xp: 0) == .baby && Stage.of(xp: 99) == .baby && Stage.of(xp: 100) == .kid && Stage.of(xp: 5000) == .master,
              "growth stages from XP")
        var life = LifeState()
        let t0 = now
        let f1 = LifeRules.feed(&life, now: t0, roll: 0.5, pick: 0)
        check(f1.combo == 1 && life.xp == 10 && life.satiety == 95 && f1.food == "🍙" && f1.kind == .jump, "first feed")
        check(f1.unlocked == [.bow] && life.wearing == ["bow"], "first task unlocks and wears the bow")
        _ = LifeRules.feed(&life, now: t0.addingTimeInterval(600), roll: 0.5, pick: 0.3)
        let f3 = LifeRules.feed(&life, now: t0.addingTimeInterval(1200), roll: 0.5, pick: 0.3)
        check(f3.combo == 3 && f3.kind == .fireworks && life.xp == 10 + 15 + 20, "combo grows within 30 minutes and pays more XP")
        check(f3.unlocked.contains(.sunglasses) && life.wearing.contains("sunglasses"), "combo ×3 unlocks sunglasses")
        let f4 = LifeRules.feed(&life, now: t0.addingTimeInterval(1200 + 2400), roll: 0.05, pick: 0.9)
        check(f4.combo == 1 && f4.golden && f4.food == "🍰" && life.goldens == 1, "combo resets after a gap; 10% golden treat")

        // Hunger and day settlement.
        var hungry = LifeState()
        hungry.satiety = 50
        hungry.lastDecayAt = t0
        LifeRules.decay(&hungry, now: t0.addingTimeInterval(1800), working: true)
        check(abs(hungry.satiety - 46.5) < 0.01, "hunger: −7 per work hour")
        LifeRules.decay(&hungry, now: t0.addingTimeInterval(1800 + 3 * 3600), working: true)
        check(abs(hungry.satiety - 39.5) < 0.01, "hunger capped at one hour per step (sleep, lunch)")
        LifeRules.decay(&hungry, now: t0.addingTimeInterval(1800 + 5 * 3600), working: false)
        check(abs(hungry.satiety - 39.5) < 0.01, "no hunger outside work")

        var days = LifeState()
        days.dayKey = "2026-10-20"
        LifeRules.syncDay(&days, completed: 3, planned: 3, target: 3, workday: true)
        var closed = LifeRules.closeDay(&days, today: "2026-10-21") { _ in true }
        check(days.streak == 1 && days.perfectDays == ["2026-10-20"] && days.xp == 30 && days.snacks == 2 && closed.outcome == .kept,
              "target met: streak +1, sticker and a 🍪")
        LifeRules.syncDay(&days, completed: 0, planned: 2, target: 3, workday: true)
        closed = LifeRules.closeDay(&days, today: "2026-10-24") { _ in true }
        check(closed.outcome == .frozen && days.streak == 1 && days.snacks == 1 && days.dirt == 0,
              "a missed workday eats a 🍪 instead of the streak; days the Mac was off don't count")
        var one = LifeState()
        one.dayKey = "2026-10-20"
        LifeRules.syncDay(&one, completed: 1, planned: 3, target: 3, workday: true)
        _ = LifeRules.closeDay(&one, today: "2026-10-21") { _ in true }
        check(one.streak == 1 && one.snacks == 1, "one finished task keeps the streak")
        var busy = LifeState()
        busy.dayKey = "2026-10-20"; busy.streak = 3; busy.snacks = 0
        LifeRules.syncDay(&busy, completed: 0, planned: 3, target: 3, workday: true, busy: true)
        closed = LifeRules.closeDay(&busy, today: "2026-10-21") { _ in true }
        check(closed.outcome == .excused && busy.streak == 3 && busy.dirt == 0, "a packed calendar day is excused")
        var broken = LifeState()
        broken.dayKey = "2026-10-20"; broken.streak = 5; broken.snacks = 0
        LifeRules.syncDay(&broken, completed: 0, planned: 3, target: 3, workday: true)
        closed = LifeRules.closeDay(&broken, today: "2026-10-21") { _ in true }
        check(closed.outcome == .broken && closed.lost == 5 && broken.streak == 0 && broken.dirt == 1 && broken.repair?.streak == 5,
              "no 🍪: the streak breaks, with a repair quest")
        LifeRules.syncDay(&broken, completed: 2, planned: 3, target: 3, workday: true)
        check(LifeRules.checkRepair(&broken) && broken.streak == 5, "2 tasks the next day bring the streak back")
        LifeRules.syncDay(&broken, completed: 1, planned: 3, target: 3, workday: true)
        _ = LifeRules.checkRepair(&broken)
        check(broken.streak == 0, "an Undo takes the mended streak back")
        LifeRules.syncDay(&broken, completed: 2, planned: 3, target: 3, workday: true)
        _ = LifeRules.checkRepair(&broken)
        _ = LifeRules.closeDay(&broken, today: "2026-10-22") { _ in true }
        check(broken.streak == 6 && broken.repair == nil, "the mended streak counts the repair day too")
        _ = LifeRules.feed(&broken, now: t0, roll: 0.5, pick: 0)
        check(broken.dirt == 0, "a finished task washes one layer off")
        var budget = LifeState()
        budget.dayKey = "2026-10-20"; budget.dayNudges = 8; budget.dayBackoff = ["nudge": 4]; budget.dismissedInRow = 2
        _ = LifeRules.closeDay(&budget, today: "2026-10-21") { _ in true }
        check(budget.dayNudges == 0 && budget.dayBackoff.isEmpty && budget.dismissedInRow == 0, "the reminder budget resets every day")
        var weekend = LifeState()
        weekend.dayKey = "2026-10-24"
        weekend.streak = 4
        LifeRules.syncDay(&weekend, completed: 0, planned: 0, target: 3, workday: false)
        _ = LifeRules.closeDay(&weekend, today: "2026-10-25") { _ in false }
        check(weekend.streak == 4 && weekend.dirt == 0, "days off don't break the streak")

        let wardrobe = PetLife(persist: false, initial: {
            var s = LifeState()
            s.unlocked = ["bow", "crown"]
            s.wearing = ["bow"]
            return s
        }())
        wardrobe.toggle(.crown)
        check(wardrobe.state.wearing == ["crown"], "one item per slot")
        let old = try? JSONDecoder().decode(LifeState.self, from: Data(#"{"xp":120}"#.utf8))
        check(old?.xp == 120 && old?.satiety == 70, "saved state with missing fields still loads")

        i = MoodInputs()
        i.satiety = 0
        i.dirt = 3
        check(MoodEngine.evaluate(i).mood == .annoyed, "starving and dirty pet is worried")

        // Calm: interruptions wait for a pause and never break deep work.
        check(CalmRules.engaged(secondsSinceKey: 5, idleSeconds: 5, distracted: false), "typing in a work app = engaged")
        check(!CalmRules.engaged(secondsSinceKey: 5, idleSeconds: 5, distracted: true), "typing on a distracting site isn't work")
        let start = CalmRules.engagedSince(nil, engaged: true, secondsSinceKey: 3, now: t0)
        check(start == t0 && CalmRules.engagedSince(start, engaged: false, secondsSinceKey: 60, now: t0) == t0,
              "a short pause keeps the streak of work")
        check(CalmRules.engagedSince(start, engaged: false, secondsSinceKey: 200, now: t0) == nil, "two minutes without typing ends it")
        check(!CalmRules.inFlow(engagedSince: t0, now: t0.addingTimeInterval(9 * 60))
              && CalmRules.inFlow(engagedSince: t0, now: t0.addingTimeInterval(10 * 60)), "10 minutes of steady work = in the zone")
        check(!CalmRules.atBreakpoint(secondsSinceKey: 2, secondsSinceAppSwitch: 300), "mid-typing is not a good moment")
        check(CalmRules.atBreakpoint(secondsSinceKey: 12, secondsSinceAppSwitch: 300)
              && CalmRules.atBreakpoint(secondsSinceKey: 2, secondsSinceAppSwitch: 3), "a typing pause or an app switch is")
        check(!CalmRules.withinBudget(lastBubbleAt: t0, now: t0.addingTimeInterval(10 * 60), minGap: 15)
              && CalmRules.withinBudget(lastBubbleAt: t0, now: t0.addingTimeInterval(16 * 60), minGap: 15), "bubbles spaced out")
        check(CalmRules.secondsSinceKey() >= 0, "typing pause readable without permissions")

        // Pet diary.
        let memo = PetLog(folder: nil, now: t0)
        memo.add(.bubble, "a", now: t0)
        memo.add(.response, "b", tag: "ignored", now: t0)
        memo.add(.hold, "c", throttle: "h", every: 10, now: t0)
        memo.add(.hold, "c", throttle: "h", every: 10, now: t0.addingTimeInterval(120))
        memo.add(.flow, "d", tag: "flowEnd", minutes: 30, now: t0)
        let sum = LogSummary(memo.today)
        check(memo.today.count == 4 && sum.bubbles == 1 && sum.ignored == 1 && sum.holds == 1 && sum.flowMinutes == 30,
              "diary entries, throttling and summary")
        memo.add(.system, "next day", now: t0.addingTimeInterval(86_400))
        check(memo.today.count == 1, "diary starts fresh on a new day")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("todopet-log-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let oldDay = DayMath.key(t0.addingTimeInterval(-20 * 86_400))
        try? Data("{}\n".utf8).write(to: dir.appendingPathComponent("\(oldDay).jsonl"))
        let disk = PetLog(folder: dir, now: t0)
        disk.add(.bubble, "“Viết báo cáo” — vì 45 phút", now: t0)
        disk.add(.response, "Bạn bấm “Để sau”", tag: "picked", now: t0.addingTimeInterval(30))
        let reread = PetLog(folder: dir, now: t0)
        check(reread.today.map(\.text) == ["“Viết báo cáo” — vì 45 phút", "Bạn bấm “Để sau”"], "diary saved to disk and read back")
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(oldDay).jsonl").path), "diary files older than 14 days removed")
        let exported = PetLog.export(reread.today, day: DayMath.key(t0))
        check(exported.hasPrefix("TodoPet") && exported.contains("💬 “Viết báo cáo”"), "diary export for copying")

        // Xin vía.
        var wa = Wish(title: "A")
        var wb = Wish(title: "B")
        var wc = Wish(title: "C")
        wa.lastShown = t0.addingTimeInterval(-3600)
        wb.lastShown = t0.addingTimeInterval(-7200)
        wc.lastShown = nil
        check(WishRules.next([wa, wb, wc])?.title == "C" && WishRules.next([wa, wb])?.title == "B", "never-shown wish first, then the oldest")
        check(WishRules.spacingMinutes(workStart: 8, workEnd: 18, perDay: 2) == 200
              && WishRules.spacingMinutes(workStart: 8, workEnd: 10, perDay: 2) == 60, "wish reminders spread over the day")
        let wishStore = WishStore(persist: false, initial: [wa])
        wishStore.linkStep("task-1", to: wa.id)
        check(wishStore.completeStep(taskId: "task-1")?.steps == 1 && wishStore.completeStep(taskId: "task-1") == nil,
              "a finished step counts once")
        check(WishRules.stepContent("  Học 10 từ ") == "✨ Học 10 từ", "small step marked with ✨")
        let oldWish = try? JSONDecoder().decode(Wish.self, from: Data(#"{"title":"X"}"#.utf8))
        check(oldWish?.title == "X" && oldWish?.emoji == "🌟" && oldWish?.steps == 0, "saved wishes with missing fields still load")

        // Where was I?
        check(ResumeRules.workURL("https://u:p@docs.google.com/d/1?usp=sharing&access_token=abc&code=x#heading")
              == "https://docs.google.com/d/1?usp=sharing", "resume link: no credentials, secrets or fragment")
        check(ResumeRules.workURL("file:///etc/hosts") == nil && ResumeRules.workURL("javascript:alert(1)") == nil, "resume link: http(s) only")
        check(ResumeRules.isSecretParam("X-Amz-Signature") && ResumeRules.isSecretParam("apiKey") && ResumeRules.isSecretParam("sessionid")
              && !ResumeRules.isSecretParam("keyword") && !ResumeRules.isSecretParam("author"), "secret-looking query parameters")
        let wctx = WorkContext(taskId: "1", taskTitle: "Report", app: "Google Chrome", bundle: "com.google.Chrome",
                               pageTitle: "Q4 budget - Google Chrome", url: "https://docs.google.com/x", at: t0)
        check(ResumeRules.whereText(wctx) == "Google Chrome — Q4 budget" && ResumeRules.host(wctx) == "docs.google.com",
              "resume card: app — page title, and the host to reopen")
        check(ResumeRules.shouldOffer(awayMinutes: 6) && !ResumeRules.shouldOffer(awayMinutes: 3)
              && ResumeRules.shouldOffer(afterMeeting: true) && ResumeRules.shouldOffer(leftDistractionMinutes: 2.5),
              "resume after 5+ min away, a meeting, or a 2+ min detour")
        check(!ResumeRules.isWorkApp(bundle: "us.zoom.xos") && !ResumeRules.isWorkApp(bundle: "com.todopet.mochi")
              && ResumeRules.isWorkApp(bundle: "com.microsoft.VSCode"), "calls and the pet itself are never where you were")

        // Wrap up.
        let at = { (h: Int, m: Int) in DayMath.at(hour: h, minute: m, on: t0) }
        check(!WrapRules.canWrapUp(at(14, 59), workEnd: 18) && WrapRules.canWrapUp(at(15, 0), workEnd: 18)
              && WrapRules.canWrapUp(at(13, 30), workEnd: 14), "wrap up from 15:00, or 30 min before work ends")
        let friday = DateParse.parse("2026-10-30T17:00:00")!
        check(DayMath.key(WrapRules.nextWorkday(after: friday) { cal.component(.weekday, from: $0) != 1 && cal.component(.weekday, from: $0) != 7 })
              == "2026-11-02", "after Friday the next workday is Monday")
        check(WrapRules.tidyNote("  open   the\nreport ") == "open the report" && WrapRules.tidyNote("   ") == nil, "tidy one-line note")
        var frogDay = DaySnapshot()
        frogDay.today = [TodoTask(id: "a", content: "Urgent", priority: 4), TodoTask(id: "b", content: "Frog", priority: 1)]
        frogDay.frogId = "b"
        check(frogDay.next?.id == "b", "tomorrow's frog goes first")

        // Day load and strip.
        let noon2 = DayMath.at(hour: 14, on: t0)
        let meet = CalEvent(id: "m", title: "Họp ngân sách Q4", start: noon2.addingTimeInterval(3600), end: noon2.addingTimeInterval(7200), joinURL: nil)
        var long = TodoTask(id: "t1", content: "Write report")
        long.duration = TodoDuration(amount: 180, unit: "minute")
        let short = TodoTask(id: "t2", content: "Reply to Lan")
        let load = DayLoadRules.load(tasks: [long, short], events: [meet], now: noon2, workStart: 8, workEnd: 18, defaultMinutes: 30)
        check(load.taskMinutes == 210 && load.meetingMinutes == 60 && load.capacity == 240 && load.overBy == 30
              && DayLoadRules.level(load) == .tight, "load: 3h30 of tasks + 1h meeting in 4h left is tight")
        let heavy = DayLoadRules.load(tasks: [long, short, TodoTask(id: "t3", content: "x")], events: [meet], now: noon2,
                                      workStart: 8, workEnd: 18, defaultMinutes: 30)
        check(DayLoadRules.isOverbooked(heavy) && DayLoadRules.level(heavy) == .over, "an hour past the time left is overbooked")
        var timed = TodoTask(id: "t4", content: "Call", due: TodoDue(date: "x", datetime: DateParse.utcString(noon2.addingTimeInterval(3600))))
        timed.duration = TodoDuration(amount: 30, unit: "minute")
        let strip = DayLoadRules.strip(tasks: [timed], events: [meet], now: noon2, workStart: 8, workEnd: 18, defaultMinutes: 30)
        check(strip.segments.count == 2 && strip.segments[0].kind == .meeting && strip.segments[1].lane == 1 && abs(strip.now - 0.6) < 0.001,
              "day strip: overlapping blocks get their own row")
        check(DayLoadRules.text(90) == "1h30" && DayLoadRules.text(45) == "45'", "durations read nicely")

        // Meeting bookends.
        let rel = RelatedTasks.related(to: "Họp: Đề xuất ngân sách Q4",
                                       in: [TodoTask(id: "1", content: "Gửi email"), TodoTask(id: "2", content: "Sửa bảng ngân sách"),
                                            TodoTask(id: "3", content: "Đề xuất ngân sách cho sếp")])
        check(rel.map(\.id) == ["3", "2"], "related tasks: shared words, ignoring Vietnamese accents")
        check(RelatedTasks.related(to: "Weekly team sync", in: [TodoTask(id: "1", content: "Team lunch")]).isEmpty,
              "common meeting words don't link tasks")

        // If-then starts.
        let plan = { (tr: StartTrigger) in TaskTrigger(taskId: "1", taskTitle: "x", day: "2026-10-20", trigger: tr, setAt: t0) }
        check(TriggerRules.due([plan(.afterMeeting(id: "m", title: "Standup"))], today: "2026-10-20", now: t0, endedMeetings: ["m"], front: nil).count == 1
              && TriggerRules.due([plan(.afterMeeting(id: "m", title: "Standup"))], today: "2026-10-20", now: t0, endedMeetings: [], front: nil).isEmpty,
              "start after a meeting: when it ends")
        let figma = plan(.appOpens(name: "Figma", bundle: "com.figma.Desktop"))
        check(TriggerRules.due([figma], today: "2026-10-20", now: t0, endedMeetings: [], front: ("com.figma.Desktop", t0.addingTimeInterval(-5))).isEmpty
              && TriggerRules.due([figma], today: "2026-10-20", now: t0, endedMeetings: [], front: ("com.figma.Desktop", t0.addingTimeInterval(5))).count == 1,
              "start when an app opens: only once it comes to the front after the plan")
        var lunch = plan(.afterLunch)
        check(TriggerRules.due([lunch], today: "2026-10-20", now: at(12, 0), endedMeetings: [], front: nil).isEmpty
              && TriggerRules.due([lunch], today: "2026-10-20", now: at(13, 5), endedMeetings: [], front: nil).count == 1, "after lunch: from 13:00")
        lunch.fired = true
        check(TriggerRules.due([lunch], today: "2026-10-20", now: at(13, 5), endedMeetings: [], front: nil).isEmpty, "a plan fires once")
        let choices = TriggerRules.choices(events: [meet], now: at(11, 0), recentApps: [("Xcode", "com.apple.dt.Xcode"), ("Figma", "com.figma.Desktop")],
                                           frontBundle: "com.apple.dt.Xcode")
        let wanted: [StartTrigger] = [.afterMeeting(id: "m", title: "Họp ngân sách Q4"), .appOpens(name: "Figma", bundle: "com.figma.Desktop"), .afterLunch]
        check(choices == wanted,
              "start-when menu: meetings ahead, recent apps (not the one in front), lunch")
        var anyLife = LifeState()
        check(LifeRules.feed(&anyLife, now: t0, roll: 0.5, pick: 0.99).kind != .blessing, "finishing a task never plays the blessing")

        // Seasons.
        let onDay = { (k: String) in DateParse.parse(k + "T12:00:00")! }
        check(SeasonRules.active(on: onDay("2026-10-30")) == ActiveSeason(season: .halloween, start: "2026-10-20", end: "2026-11-01", daysLeft: 2),
              "Halloween: Oct 20 – Nov 1")
        check(SeasonRules.active(on: onDay("2026-02-20"))?.season == .tet && SeasonRules.active(on: onDay("2026-02-10"))?.season == .tet
              && SeasonRules.active(on: onDay("2026-02-25")) == nil, "Tết: a week either side of the lunar new year (Feb 17, 2026)")
        check(SeasonRules.active(on: onDay("2026-09-27"))?.season == .trungthu && SeasonRules.active(on: onDay("2027-01-01"))?.season == .christmas
              && SeasonRules.active(on: onDay("2026-07-01")) == nil, "Mid-Autumn, Christmas across New Year, nothing in July")

        // Chests.
        var game = LifeState()
        check(!ChestRules.addWork(&game, seconds: 1790) && ChestRules.addWork(&game, seconds: 15) && game.chests == 1 && game.workSec == 5,
              "a chest for every 30 minutes of work")
        game.chestsToday = ChestRules.maxPerDay
        check(!ChestRules.addWork(&game, seconds: 4000), "at most 3 chests a day")
        game.chests = 1
        let common = ChestRules.open(&game, roll: 0.1, pick: 0.9, season: nil)
        check(common?.reward == .xp(20) && game.chests == 0 && game.xp == 20, "common chest: +20 XP")
        check(ChestRules.open(&game, roll: 0.1, pick: 0.9, season: nil) == nil, "no chest, nothing to open")
        game.chests = 1
        let rare = ChestRules.open(&game, roll: 0.8, pick: 0, season: nil)
        check(rare?.reward == .accessory(.beanie) && game.unlocked.contains("beanie") && game.wearing.contains("beanie"),
              "rare chest: a new outfit, put on if the slot is free")
        game.chests = 1
        let legendary = ChestRules.open(&game, roll: 0.97, pick: 0, season: .halloween)
        check(legendary?.reward == .accessory(.witchhat) && Accessory.witchhat.season == .halloween, "legendary chest in season: its outfit")
        game.chests = 1
        let golden = ChestRules.open(&game, roll: 0.97, pick: 0, season: nil)
        check(golden?.reward == .golden && game.goldens == 1, "legendary chest out of season: a golden treat")
        let xpBefore = game.xp
        ChestRules.undo(&game, golden!)
        check(game.chests == 1 && game.xp == xpBefore - 50 && game.goldens == 0, "Todoist failed: the chest goes back")
        check(!Accessory.beanie.isEarned(LifeState()) && Accessory.chestPool.allSatisfy { $0.season == nil },
              "chest outfits never unlock on their own")

        // Knitting.
        var knit = LifeState()
        check(CraftRules.knit(&knit, seconds: 600, sessionMinutes: 25, pick: 0, today: "2026-10-20") == nil && abs(knit.craft - 0.4) < 1e-9,
              "knitting: 10 of 25 minutes is 40%")
        check(CraftRules.dropStitches(&knit) && abs(knit.craft - 0.3) < 1e-9, "a distraction drops a few stitches")
        let made = CraftRules.knit(&knit, seconds: 1050, sessionMinutes: 25, pick: 0, today: "2026-10-20")
        check(made?.decor == .rug && knit.decor == ["rug"] && knit.craft == 0, "a whole session makes a decoration")
        knit.craft = 0
        _ = CraftRules.knit(&knit, seconds: 120, sessionMinutes: 2, pick: 0, today: "2026-10-20")
        check(abs(knit.craft - 120.0 / 1500) < 1e-9, "a 2-minute starter knits only its share")
        var allDecor = LifeState()
        allDecor.decor = Decor.allCases.map(\.rawValue)
        var xps: [Int] = []
        for _ in 0..<4 { xps.append(CraftRules.knit(&allDecor, seconds: 1500, sessionMinutes: 25, pick: 0, today: "2026-10-20")?.xp ?? -1) }
        check(xps == [30, 30, 30, 0], "with every decoration owned: +30 XP, at most 90 a day")

        // Trips.
        check(TripRules.shouldOffer(planDone: true, inWork: true, minutesToEnd: 90, today: "d", tripDay: nil, declined: nil, away: false)
              && !TripRules.shouldOffer(planDone: true, inWork: true, minutesToEnd: 45, today: "d", tripDay: nil, declined: nil, away: false)
              && !TripRules.shouldOffer(planDone: true, inWork: true, minutesToEnd: 90, today: "d", tripDay: nil, declined: "d", away: false),
              "trip offer: plan done, an hour left, not declined today")
        var trip = LifeState()
        let leave = DayMath.at(hour: 15, on: t0)
        let started = TripRules.start(&trip, now: leave, workEnd: DayMath.at(hour: 16, on: t0), pick: 0)
        check(started.back == DayMath.at(hour: 16, on: t0) && started.place == "hoian", "back by the end of work at the latest")
        let early = TripRules.finish(&trip, now: leave.addingTimeInterval(600))
        check(early?.early == true && trip.trip == nil && trip.tripDay == nil && trip.souvenirs.isEmpty, "called back early: no souvenir, trip not used up")
        _ = TripRules.start(&trip, now: leave, workEnd: DayMath.at(hour: 18, on: t0), pick: 0)
        let home = TripRules.finish(&trip, now: leave.addingTimeInterval(3600))
        check(home?.isNew == true && trip.souvenirs == ["hoian"] && trip.week.trips == 1, "back with a souvenir")
        trip.souvenirs = TripRules.souvenirs.map(\.id)
        _ = TripRules.start(&trip, now: leave, workEnd: DayMath.at(hour: 18, on: t0), pick: 0)
        check(TripRules.finish(&trip, now: leave.addingTimeInterval(3600))?.xp == 20, "a souvenir already on the shelf: +20 XP")

        // Sticker book and weekly chapters.
        var book = LifeState()
        book.pageFilled = 9
        check(StickerRules.add(&book) && book.stickerPage == 2 && book.pageFilled == 2 && book.xp == 50 && book.snacks == 2,
              "a full sticker page: +50 XP, a snack, and a new page with 2 gifts")
        check(WeekRules.key(onDay("2026-11-01")) == "2026-10-26" && WeekRules.key(onDay("2026-10-26")) == "2026-10-26", "weeks start on Monday")
        var weeks = LifeState()
        weeks.week = WeekStats(key: "2026-10-19", done: 9, stickers: 2, trips: 1)
        WeekRules.roll(&weeks, today: onDay("2026-10-27"))
        check(weeks.lastWeek?.done == 9 && weeks.week == WeekStats(key: "2026-10-26"), "a new week keeps last week's recap")
        let oldBook = try? JSONDecoder().decode(LifeState.self, from: Data(#"{"perfectDays":["a","b","c","d","e","f","g","h","i","j"]}"#.utf8))
        check(oldBook?.stickerPage == 2 && oldBook?.pageFilled == 4, "older saves pick up the sticker book where it would be")

        // Language switch.
        let saved = currentLang
        currentLang = .en
        check(L("Xin chào", "Hello") == "Hello", "English strings")
        currentLang = .vi
        check(L("Xin chào", "Hello") == "Xin chào", "Vietnamese strings")
        currentLang = saved

        check(Brain.idleSeconds() >= 0, "idle time readable without permissions")
        print(fails == 0 ? "All good 🎉" : "\(fails) failure(s)")
        return fails == 0
    }

    // MARK: Snapshots

    static func snapshot(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Default settings in a throwaway suite: snapshots never read or change your real settings.
        let suite = "com.todopet.snapshot"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let prefs = Prefs(defaults: defaults)
        if let l = ProcessInfo.processInfo.environment["TODOPET_LANG"].flatMap(Lang.init(rawValue:)) { prefs.lang = l }
        savePNG(MoodSheet(), url.appendingPathComponent("moods.png"), scale: 2)
        savePNG(LifeSheet(), url.appendingPathComponent("life.png"), scale: 2)
        savePNG(OutfitSheet(), url.appendingPathComponent("outfits.png"), scale: 2)
        savePNG(IconArt(), url.appendingPathComponent("icon-1024.png"), scale: 1)

        let brain = Brain(prefs: prefs, demo: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                saveView(BoardView(brain: brain, prefs: prefs, state: BoardState())
                    .background(Color(nsColor: .windowBackgroundColor)), appearance,
                         url.appendingPathComponent("board-\(name).png"))
                let model = BubbleModel()
                model.mood = .annoyed
                model.bubble = Bubble(text: Lines.plan(mood: .annoyed, planned: 1, target: 3), actions: [
                    BubbleAction(title: L("＋ Thêm việc", "＋ Add tasks"), primary: true) {},
                    BubbleAction(title: L("Để sau", "Later")) {},
                ])
                saveView(BubbleView(model: model), appearance, url.appendingPathComponent("bubble-\(name).png"))
            }
            if let stuck = brain.stuck.first {
                let model = BubbleModel()
                model.mood = .annoyed
                model.bubble = Bubble(text: Lines.stuck(stuck, mood: .annoyed), actions: [
                    BubbleAction(title: L("✂️ Chia nhỏ", "✂️ Split it"), primary: true) {},
                    BubbleAction(title: L("Bỏ khỏi kế hoạch", "Drop from plan")) {},
                    BubbleAction(title: L("Để sau", "Later")) {},
                ])
                saveView(BubbleView(model: model), .aqua, url.appendingPathComponent("bubble-stuck.png"))
                let steps = [L("Mở hộp thư, lọc email của sếp", "Open the inbox and find the boss's email"),
                             L("Ghi 3 ý chính cần trả lời", "Jot down the 3 points to answer"),
                             L("Viết và gửi bản trả lời ngắn", "Write and send a short reply")]
                saveView(BreakdownView(task: stuck.task, brain: brain, state: BoardState(), steps: steps)
                    .frame(width: 370).background(Color(nsColor: .windowBackgroundColor)), .aqua,
                         url.appendingPathComponent("split.png"))
                saveView(TaskRow(task: stuck.task, brain: brain, state: BoardState(), overdue: true, confirming: true)
                    .padding(14).frame(width: 370).background(Color(nsColor: .windowBackgroundColor)), .aqua,
                         url.appendingPathComponent("delete-confirm.png"))
            }
            let state = BoardState()
            state.wardrobe = true
            saveView(BoardView(brain: brain, prefs: prefs, state: state).background(Color(nsColor: .windowBackgroundColor)), .aqua,
                     url.appendingPathComponent("wardrobe.png"))
            let sign = SignModel()
            sign.text = brain.day.next?.title ?? "Report"
            saveView(SignView(model: sign), .aqua, url.appendingPathComponent("sign.png"))
            let model = BubbleModel()
            model.mood = .angry
            model.bubble = Bubble(text: Lines.block(app: "youtube.com", next: brain.day.next), actions: [
                BubbleAction(title: "▶︎ " + L("Tập trung 25'", "Focus 25'"), primary: true) {},
                BubbleAction(title: L("Tha cho tôi 15'", "Spare me 15'")) {},
            ])
            saveView(BubbleView(model: model), .aqua, url.appendingPathComponent("bubble-block.png"))

            let wishState = BoardState()
            wishState.showWishes = true
            saveView(BoardView(brain: brain, prefs: prefs, state: wishState).background(Color(nsColor: .windowBackgroundColor)), .aqua,
                     url.appendingPathComponent("wishes.png"))
            if let w = brain.wishes.wishes.first {
                let model = BubbleModel()
                model.mood = .happy
                model.bubble = Bubble(text: Lines.wishReminder(w), actions: [
                    BubbleAction(title: L("🙏 Xin vía", "🙏 Bless it"), primary: true) {},
                    BubbleAction(title: L("＋ Bước nhỏ", "＋ Small step")) {},
                    BubbleAction(title: L("Để sau", "Later")) {},
                ])
                saveView(BubbleView(model: model), .aqua, url.appendingPathComponent("bubble-wish.png"))
            }

            // Wrap up, lightening an overbooked day, "where was I?" and the meeting bookend.
            for (sheet, file) in [(WrapSheet.wrapUp, "wrapup.png"), (.lighten, "lighten.png")] {
                let st = BoardState()
                st.wrapUp = sheet
                saveView(BoardView(brain: brain, prefs: prefs, state: st).background(Color(nsColor: .windowBackgroundColor)), .aqua,
                         url.appendingPathComponent(file))
            }
            let resume = WorkContext(taskId: brain.day.next?.id, taskTitle: brain.day.next?.title, app: "Google Chrome",
                                     bundle: "com.google.Chrome", pageTitle: L("Báo cáo quý 4 - Google Docs", "Q4 report - Google Docs"),
                                     url: "https://docs.google.com/document/d/1", note: L("viết phần kết luận", "write the conclusion"), at: Date())
            let rm = BubbleModel()
            rm.mood = .normal
            rm.bubble = Bubble(text: Lines.resume(resume, why: Lines.resumeWhyAway(12)), actions: [
                BubbleAction(title: L("Mở lại ↗", "Reopen ↗"), primary: true) {},
                BubbleAction(title: "▶︎ " + L("Tập trung", "Focus")) {},
                BubbleAction(title: L("Việc khác", "Something else")) {},
            ])
            saveView(BubbleView(model: rm), .aqua, url.appendingPathComponent("bubble-resume.png"))
            let mm = BubbleModel()
            mm.mood = .normal
            let ev = CalEvent(id: "x", title: L("Họp team", "Team sync"), start: Date().addingTimeInterval(600), end: Date().addingTimeInterval(3600), joinURL: nil)
            mm.bubble = Bubble(text: Lines.afterMeeting(ev) + "\n" + Lines.breather(minutes: 10, next: ev), actions: [
                BubbleAction(title: L("＋ Việc tiếp theo", "＋ Next step"), primary: true) {},
                BubbleAction(title: L("↩︎ Quay lại việc", "↩︎ Back to work")) {},
                BubbleAction(title: L("Không có gì", "Nothing")) {},
            ])
            saveView(BubbleView(model: mm), .aqua, url.appendingPathComponent("bubble-meeting.png"))

            // A sample diary for the docs.
            let base = DayMath.at(hour: 9, on: Date())
            func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
            let next = brain.day.next?.title ?? "Report"
            let sample: [(Double, LogEntry.Kind, String, String?, Int?)] = [
                (0, .bubble, L("“Chào buổi sáng! ☀️ Hôm nay mình làm 3 việc gì nào?” — vì lời chào đầu ngày làm việc, mới có 2/3 việc",
                               "“Good morning! ☀️ What are our 3 things today?” — because first greeting of the workday, only 2/3 planned"), nil, nil),
                (1, .response, L("Bạn bấm “＋ Thêm việc”", "You tapped “＋ Add tasks”"), "picked", nil),
                (12, .flow, L("Bạn vào guồng (gõ phím đều 10 phút) — pet giữ im lặng", "You're in the zone (10 minutes of steady typing) — the pet stays quiet"), "flowStart", nil),
                (40, .hold, L("Có lời nhắc đến hạn nhưng bạn đang vào guồng — để sau", "A reminder is due but you're in the zone — later"), nil, nil),
                (64, .flow, L("Hết guồng sau 52 phút", "Left the zone after 52 minutes"), "flowEnd", 52),
                (65, .life, L("Xong “\(next)” → no 95%, 345 XP, combo ×2", "Done “\(next)” → 95% full, 345 XP, combo ×2"), nil, nil),
                (90, .distraction, L("Đang ở youtube.com hơn 2 phút", "On youtube.com for 2+ minutes"), nil, nil),
                (91, .bubble, L("“Ê! Đang youtube.com đó hả? 👀” — vì ở youtube.com 2 phút trong giờ làm",
                                "“Hey! On youtube.com? 👀” — because on youtube.com for 2 min during work hours"), nil, nil),
                (91.8, .response, L("Bạn không phản hồi (tự ẩn)", "No response (faded away)"), "ignored", nil),
                (98, .distraction, L("Rời youtube.com sau 8 phút", "Left youtube.com after 8 minutes"), "end", 8),
                (99, .mood, L("Tâm trạng: bình thường → đang lo lắng (điểm 41) — −21 đang xao nhãng với youtube.com",
                              "Mood: chill → worried (score 41) — −21 distracted by youtube.com"), nil, nil),
            ]
            for (m, kind, text, tag, minutes) in sample { brain.log.add(kind, text, tag: tag, minutes: minutes, now: at(m)) }
            let logState = BoardState()
            logState.showLog = true
            saveView(BoardView(brain: brain, prefs: prefs, state: logState).background(Color(nsColor: .windowBackgroundColor)), .aqua,
                     url.appendingPathComponent("diary.png"))

            defaults.removePersistentDomain(forName: suite)
            print("Snapshots written to \(url.path)")
            exit(0)
        }
    }

    private static func savePNG<V: View>(_ view: V, _ url: URL, scale: CGFloat) {
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let cg = r.cgImage else { print("render failed: \(url.lastPathComponent)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func saveView<V: View>(_ view: V, _ appearance: NSAppearance.Name, _ url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .aqua ? .windowBackgroundColor : NSColor(white: 0.16, alpha: 1)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Every mood, standing and walking, for docs and visual checks.
struct MoodSheet: View {
    let moods: [Mood] = [.happy, .normal, .annoyed, .angry, .sleeping, .focus, .celebrating]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(moods, id: \.self) { m in
                    VStack(spacing: 0) {
                        pet(PetPose(mood: m, t: 0.4))
                        pet(PetPose(mood: m, t: 1.25, facing: 1, walking: true, walkPhase: 1.2))
                        Text("\(m.emoji) \(m.rawValue)").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
                VStack(spacing: 0) {
                    pet(PetPose(mood: .normal, t: 0.6, held: true))
                    pet(PetPose(mood: .normal, t: 0.6, hovered: true))
                    Text("held / petted").font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(gestures.enumerated()), id: \.offset) { _, g in
                    VStack(spacing: 0) {
                        pet(gesturePose(g.0, g.1))
                        Text(g.2).font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
                VStack(spacing: 0) {
                    pet({ var p = PetPose(mood: .normal, t: 0.6, hovered: true); p.hoverFor = 1.7; return p }())
                    Text("slow blink").font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
        }
        .padding(10)
        .background(Color.white)
        .foregroundColor(.black)
    }

    private let gestures: [(PetGesture.Kind, Double, String)] = [
        (.wave, 0.3, "wave"), (.yawn, 0.5, "yawn"), (.shake, 0.2, "shake"), (.giggle, 0.4, "giggle"), (.dizzy, 0.4, "dizzy"),
    ]

    private func gesturePose(_ g: PetGesture.Kind, _ progress: Double) -> PetPose {
        var p = PetPose(mood: .normal, t: 0.9)
        p.gesture = g
        p.gestureP = progress
        return p
    }

    private func pet(_ pose: PetPose) -> some View {
        Canvas { ctx, size in PetArt.draw(&ctx, size: size, pose: pose) }
            .frame(width: 120, height: 120)
    }
}

/// Every outfit, the knitting pet during focus, and the signpost left behind on a trip.
struct OutfitSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<3) { row in
                HStack(spacing: 2) {
                    ForEach(Array(Accessory.allCases.dropFirst(row * 8).prefix(8))) { a in
                        VStack(spacing: 0) {
                            Canvas { ctx, size in
                                var pose = PetPose(mood: .happy, t: 0.3)
                                pose.wearing = [a]
                                PetArt.draw(&ctx, size: size, pose: pose)
                            }
                            .frame(width: 110, height: 110)
                            Text(a.rawValue).font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                    if row == 2 {
                        VStack(spacing: 0) {
                            Canvas { ctx, size in
                                var pose = PetPose(mood: .focus, t: 0.3)
                                pose.craft = 0.6
                                PetArt.draw(&ctx, size: size, pose: pose)
                            }
                            .frame(width: 110, height: 110)
                            Text("knitting").font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        VStack(spacing: 0) {
                            Canvas { ctx, size in
                                PetArt.drawTripSign(&ctx, size: size, emoji: "🏮", place: "Hội An", back: "16:30", t: 0)
                            }
                            .frame(width: 110, height: 110)
                            Text("on a trip").font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
            HomeView(items: [.plant, .lamp, .fishbowl]).padding(.leading, 20)
        }
        .padding(10)
        .background(Color.white)
        .foregroundColor(.black)
    }
}

/// Growth stages, hunger, dirt, accessories and the celebration dances.
struct LifeSheet: View {
    private func pet(_ pose: PetPose, _ label: String) -> some View {
        VStack(spacing: 0) {
            Canvas { ctx, size in PetArt.draw(&ctx, size: size, pose: pose) }
                .frame(width: 120, height: 120)
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func life(_ change: (inout LifeState) -> Void) -> LifeState {
        var s = LifeState()
        change(&s)
        return s
    }

    private func decorated(_ mood: Mood, t: Double = 0.4, _ s: LifeState) -> PetPose {
        var p = PetPose(mood: mood, t: t)
        p.decorate(s)
        return p
    }

    private func celebrating(_ kind: CelebrationKind, t: Double, golden: Bool = false, foodT: Double? = nil) -> PetPose {
        var p = PetPose(mood: .celebrating, t: t)
        p.celebration = kind
        p.golden = golden
        if let foodT { p.food = "🍙"; p.foodT = foodT }
        return p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Stage.allCases, id: \.rawValue) { st in
                    pet(decorated(.happy, life { $0.xp = Stage.thresholds[st.rawValue] }), st.name)
                }
                pet(decorated(.annoyed, life { $0.satiety = 12; $0.xp = 300 }), L("đói", "hungry"))
                pet(decorated(.annoyed, life { $0.dirt = 3; $0.xp = 300 }), L("bẩn 3 ngày", "dirty ×3"))
            }
            HStack(spacing: 4) {
                ForEach(Accessory.allCases) { a in
                    pet(decorated(.normal, life { $0.xp = 700; $0.unlocked = [a.rawValue]; $0.wearing = [a.rawValue] }), a.emoji + " " + a.name)
                }
                pet(decorated(.happy, life { $0.xp = 1500; $0.wearing = ["crown", "sunglasses", "scarf"] }), "👑🕶️🧣")
            }
            HStack(spacing: 4) {
                pet(celebrating(.jump, t: 0.2, foodT: 0.45), L("món ăn rơi", "treat falls"))
                pet(celebrating(.spin, t: 0.28), "spin")
                pet(celebrating(.flip, t: 0.27), "flip")
                pet(celebrating(.dance, t: 0.1), "dance")
                pet(celebrating(.fireworks, t: 0.3), "fireworks")
                pet(celebrating(.fireworks, t: 0.35, golden: true), L("vàng hiếm", "rare golden"))
                pet(celebrating(.blessing, t: 0.6), L("xin vía", "blessing"))
            }
        }
        .padding(10)
        .background(Color.white)
        .foregroundColor(.black)
    }
}

/// App icon: the happy pet on a warm rounded square.
struct IconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.80), Color(red: 1, green: 0.70, blue: 0.56)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            Canvas { ctx, size in PetArt.draw(&ctx, size: size, pose: PetPose(mood: .happy, t: 0.5)) }
                .frame(width: 760, height: 760)
                .offset(y: -40)
        }
        .frame(width: 1024, height: 1024)
    }
}
