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
        check(MoodEngine.evaluate(i).mood == .angry, "2h after plan deadline, nothing planned: grumpy")
        i = MoodInputs()
        i.planned = 3; i.completed = 2; i.remaining = 1; i.minutesSinceCelebration = 3
        check(MoodEngine.evaluate(i).mood == .happy, "2/3 done and just finished one: happy")
        i = MoodInputs()
        i.planned = 3; i.completed = 3; i.remaining = 0
        let allDone = MoodEngine.evaluate(i)
        check(allDone.mood == .happy && allDone.score >= 99, "all done: happiest")
        i = MoodInputs()
        i.planned = 3; i.remaining = 3; i.overdue = 3; i.minutesSinceProgress = 240
        check(MoodEngine.evaluate(i).mood == .angry, "overdue + 4h without progress: grumpy")
        i = MoodInputs()
        i.planned = 3; i.remaining = 3; i.minutesSinceProgress = 30; i.distractedMinutes = 5; i.distractionApp = "TikTok"
        let distracted = MoodEngine.evaluate(i).mood
        check(distracted == .annoyed || distracted == .angry, "distraction app: annoyed")
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
        }
        .padding(10)
        .background(Color.white)
        .foregroundColor(.black)
    }

    private func pet(_ pose: PetPose) -> some View {
        Canvas { ctx, size in PetArt.draw(&ctx, size: size, pose: pose) }
            .frame(width: 120, height: 120)
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
