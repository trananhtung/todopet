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
        _ = Prefs.shared
        if let l = ProcessInfo.processInfo.environment["TODOPET_LANG"].flatMap(Lang.init(rawValue:)) { currentLang = l }
        savePNG(MoodSheet(), url.appendingPathComponent("moods.png"), scale: 2)
        savePNG(IconArt(), url.appendingPathComponent("icon-1024.png"), scale: 1)

        let brain = Brain(prefs: Prefs.shared, demo: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                saveView(BoardView(brain: brain, prefs: Prefs.shared, state: BoardState())
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
