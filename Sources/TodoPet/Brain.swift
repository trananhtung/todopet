import AppKit
import Combine

struct BubbleAction: Identifiable {
    let id = UUID()
    let title: String
    var primary = false
    /// "Later", "Spare me", "Enough": not an answer to the reminder, so it neither resets nor stretches its back-off.
    var neutral = false
    let run: () -> Void
}

struct Bubble: Identifiable {
    let id = UUID()
    let text: String
    var actions: [BubbleAction] = []
    var seconds: Double = 12
    /// Bubbles with `urgent` may replace a bubble that is still on screen.
    var urgent = false
    /// An unsolicited reminder (not a reply to something you did); your response goes into the diary.
    var reminder = false
    /// The reminder kind counted against today's budget (nil for check-ins like the greeting or the resume card).
    var kind: String?
}

struct FocusSession {
    let task: TodoTask?
    let start: Date
    let end: Date
    let isBreak: Bool
    let minutes: Int
    /// A 2-minute "just open it" starter.
    var starter = false
}

enum DueChoice: String, CaseIterable, Identifiable {
    case today, tomorrow, none, smart
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: L("Hôm nay", "Today")
        case .tomorrow: L("Ngày mai", "Tomorrow")
        case .none: L("Không hạn", "No date")
        case .smart: L("✨ Cú pháp Todoist", "✨ Todoist syntax")
        }
    }
}

/// The pet's brain: syncs Todoist, computes the mood and decides when to talk.
@MainActor
final class Brain: ObservableObject {
    let prefs: Prefs

    @Published private(set) var hasToken = false
    @Published private(set) var isDemo = false
    @Published private(set) var day = DaySnapshot()
    @Published private(set) var stats: ProductivityStats?
    @Published private(set) var mood: Mood = .normal
    @Published private(set) var score: Double = 60
    @Published private(set) var reasons: [MoodReason] = []
    @Published private(set) var loading = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var focus: FocusSession?
    @Published var errorText: String?
    @Published var bubble: Bubble?
    @Published private(set) var quietUntil: Date?
    /// Today's target: the daily target, lowered on meeting-heavy days.
    @Published private(set) var target = 3
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var calendarAccess: CalendarAccess = .notDetermined
    @Published private(set) var suggestions: [SlotSuggestion] = []
    @Published private(set) var stuck: [StuckTask] = []
    @Published private(set) var browserDenied: [String] = []
    @Published private(set) var hasClaudeKey = false
    /// The dance and treat after the last finished task (drawn for a few seconds).
    @Published private(set) var celebration: CelebrationEvent?
    /// Current mischief, performed by the pet window.
    @Published private(set) var antic: AnticEvent?
    /// You've been typing steadily in work apps for a while: the pet holds everything non-urgent.
    @Published private(set) var flow = false
    /// Hunger, dirt, growth, accessories: what the pet remembers across days.
    let life: PetLife
    /// Why the pet did (or didn't) say something, kept on this Mac for tuning.
    let log: PetLog
    /// Things you want to achieve ("xin vía"), brought up now and then with a small step.
    let wishes: WishStore
    /// Tomorrow's frog and note from the wrap-up, and "done for today".
    let plans: DayPlanStore
    /// Today's if-then starts ("start X after the standup").
    let triggers: TriggerStore
    /// Where you were (task, app, page), in memory only; `pinned` is the spot you pinned with a next step.
    @Published private(set) var workContext: WorkContext?
    @Published private(set) var pinned: WorkContext?
    /// Today's load against the time left, and the board's day strip.
    @Published private(set) var load = DayLoad()
    @Published private(set) var strip: [StripSegment] = []
    @Published private(set) var stripNow: Double = 0
    @Published private(set) var doneForToday = false
    /// A little gesture the pet plays (a wave when you come back…).
    @Published private(set) var gesture: PetGesture?

    /// Set by the app: open the task board (optionally focusing the "add task" field), the split view, and settings.
    var openBoard: ((_ focusAdd: Bool) -> Void)?
    var openBreakdown: ((TodoTask) -> Void)?
    /// Opens the "xin vía" view, optionally ready to add a small step for one wish.
    var openWishes: ((UUID?) -> Void)?
    var openSettings: (() -> Void)?
    /// Opens the add field with some text in it (a meeting's next step).
    var openAdd: ((String) -> Void)?
    /// Opens the wrap-up sheet; `lighten` opens it to move tasks off an overbooked day.
    var openWrapUp: ((_ lighten: Bool) -> Void)?

    private let calendar = CalendarWatcher()
    private lazy var browser = BrowserWatcher { [weak self] in self?.frontApp?.bundle }
    private var tracker = StuckTracker()
    private var service: TodoService?
    private var active: [TodoTask] = []
    private var completed: [TodoTask] = []
    private var fired: [String: Date] = [:]
    private var dayKey = DayMath.key(Date())
    private var knownCompleted: Set<String> = []
    private var completedViaPet: Set<String> = []
    private var didLoadOnce = false
    private var celebrateUntil = Date.distantPast
    private var lastCelebration = Date.distantPast
    private var lastPlanAction = Date.distantPast
    private var lastBubbleAt = Date.distantPast
    private var awaySince: Date?
    private var frontApp: (name: String, bundle: String, since: Date)?
    private var distractionSnoozedUntil = Date.distantPast
    private var anticSnoozedUntil = Date.distantPast
    private var angrySince: Date?
    private var engagedSince: Date?
    private var flowStartedAt = Date()
    private var distractionSession: (label: String, start: Date, logged: Bool)?
    private var lastFlowEnd = Date.distantPast
    private var lastAppSwitch = Date.distantPast
    /// Work apps recently in front, most recent first (for "start when I open…").
    private(set) var recentApps: [(name: String, bundle: String)] = []
    private var currentMeeting: CalEvent?
    private var endedMeetings: Set<String> = []
    private var pendingAfterMeeting: (event: CalEvent, at: Date)?
    private var leftDetour: (label: String, minutes: Double, at: Date)?
    private var lastResumeAt = Date.distantPast
    private var lastActedTask: TodoTask?
    /// The streak came back during the last recompute (shown with the celebration).
    private var repairNote = false
    /// How yesterday was settled, told in the morning greeting.
    private var dayNote: String?
    // The game.
    private var lastTickAt = Date()
    /// A chest was earned and not announced yet (it waits for a calm moment, or joins the end of focus).
    private var pendingChest = false
    /// Something the pet knitted during focus, told at the end of the session.
    private var craftNote: String?
    /// The distraction that already cost some stitches this session.
    private var stitchesDropped: String?
    private var tripOfferId: UUID?
    /// The chest opened by the last finished task, given back if Todoist can't close it.
    private var lastChest: (taskId: String, result: ChestResult)?

    /// The pet should keep still: you're typing, in the zone, or in a meeting.
    var calmMotion: Bool {
        prefs.stillWhileTyping && (flow || CalmRules.secondsSinceKey() < 20 || CalendarMath.current(events, at: Date()) != nil)
    }
    private var lastStatsAt = Date.distantPast
    /// Wish reminders shown today.
    private var wishShows = 0
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Prefs, demo: Bool) {
        self.prefs = prefs
        life = demo ? PetLife(persist: false, initial: .demo) : PetLife()
        log = PetLog(folder: demo ? nil : PetLog.defaultFolder)
        log.enabled = prefs.keepLog
        wishes = demo ? WishStore(persist: false, initial: WishStore.demo) : WishStore()
        plans = DayPlanStore(persist: !demo)
        triggers = TriggerStore(persist: !demo)
        if demo {
            useDemo()
            return
        }
        hasClaudeKey = Keychain.read(.anthropic) != nil
        if let token = Keychain.read() ?? ProcessInfo.processInfo.environment["TODOIST_API_TOKEN"] {
            service = TodoistClient(token: token)
            hasToken = true
        }
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.frontApp = (app?.localizedName ?? "", app?.bundleIdentifier ?? "", Date())
                self?.lastAppSwitch = Date()
                self?.noteRecentApp()
                self?.browser.poll()
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            frontApp = (app.localizedName ?? "", app.bundleIdentifier ?? "", Date())
        }
        prefs.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshCalendar()
                self?.recompute()
            }
        }.store(in: &cancellables)

        browser.onDeniedChange = { [weak self] in
            guard let self else { return }
            browserDenied = BrowserWatcher.browsers.filter { self.browser.denied.contains($0.bundleID) }.map(\.name)
        }
        browser.start()
        calendar.onChange { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshCalendar()
                self?.recompute()
            }
        }
        if prefs.useCalendar && calendar.access == .notDetermined {
            requestCalendarAccess()
        }
        refreshCalendar()

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        recompute()
        // Dev hook: `TODOPET_ANTIC=parade|block TodoPet --demo` plays the mischief right away.
        if isDemo, let kind = ProcessInfo.processInfo.environment["TODOPET_ANTIC"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.antic = AnticEvent(kind: kind == "block" ? .block : .parade(self.day.next?.title ?? "Demo"), start: Date())
                }
            }
        }
        if hasToken {
            refreshSoon()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.askForToken() }
            }
        }
    }

    // MARK: - Token / demo

    func setToken(_ raw: String) async -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        let client = TodoistClient(token: token)
        do {
            _ = try await client.activeTasks(filter: "today")
        } catch {
            errorText = error.localizedDescription
            return false
        }
        Keychain.save(token)
        service = client
        hasToken = true
        isDemo = false
        resetDay()
        errorText = nil
        await refresh()
        say(Bubble(text: L("Kết nối Todoist thành công! 🎉", "Connected to Todoist! 🎉"), seconds: 6))
        return true
    }

    func removeToken() {
        Keychain.delete()
        service = nil
        hasToken = false
        isDemo = false
        active = []
        completed = []
        recompute()
    }

    func useDemo() {
        service = DemoService()
        hasToken = true
        isDemo = true
        tracker = StuckTracker(persist: false)
        let now = Date()
        let soon = DayMath.at(hour: DayMath.hour(now) + 1, on: now)
        let later = DayMath.at(hour: DayMath.hour(now) + 4, on: now)
        calendar.demoEvents = [
            CalEvent(id: "demo-1", title: L("Họp team", "Team sync"), start: soon, end: soon.addingTimeInterval(3600),
                     joinURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalEvent(id: "demo-2", title: L("Gặp khách hàng", "Client meeting"), start: later, end: later.addingTimeInterval(2700), joinURL: nil),
        ]
        refreshCalendar()
        resetDay()
        refreshSoon()
        say(Bubble(text: L("Đang chạy demo với dữ liệu giả 🎭 Bấm vào mình để mở bảng việc nhé!",
                           "Demo mode with sample tasks 🎭 Click me to open the task board!"), seconds: 10, urgent: true))
    }

    private func askForToken() {
        guard !hasToken else { return }
        say(Bubble(text: Lines.hello(name: prefs.petName), actions: [
            BubbleAction(title: L("Kết nối Todoist", "Connect Todoist"), primary: true) { [weak self] in self?.openBoard?(false) },
            BubbleAction(title: L("Xem thử (demo)", "Try demo")) { [weak self] in self?.useDemo() },
        ], seconds: 60))
    }

    // MARK: - Sync

    func refreshSoon() {
        Task { await refresh() }
    }

    func refresh() async {
        guard let service, !loading else { return }
        loading = true
        defer { loading = false }
        let now = Date()
        do {
            let act = try await service.activeTasks(filter: prefs.effectiveFilter)
            let since = Calendar.current.startOfDay(for: now)
            // The completed-tasks endpoint can fail on some plans: then keep the completions we saw ourselves.
            let done = try? await service.completedTasks(since: since, until: now.addingTimeInterval(120))
            if now.timeIntervalSince(lastStatsAt) > 900 || stats == nil {
                if let s = try? await service.stats() { stats = s }
                lastStatsAt = now
            }
            apply(active: act, completedToday: done)
            errorText = nil
            lastSync = Date()
        } catch {
            errorText = error.localizedDescription
            log.add(.sync, L("Lỗi đồng bộ Todoist: ", "Todoist sync failed: ") + error.localizedDescription,
                    throttle: "sync-error", every: 30)
            if case TodoError.unauthorized = error {
                say(Bubble(text: Lines.error(error.localizedDescription), actions: [
                    BubbleAction(title: L("Nhập token mới", "Enter a new token"), primary: true) { [weak self] in self?.openSettings?() },
                ], seconds: 30))
            }
        }
    }

    private func apply(active act: [TodoTask], completedToday done: [TodoTask]?) {
        active = act
        if let done {
            completed = done
        } else {
            let today = DayMath.key(Date())
            completed = completed.filter { $0.completedDate.map(DayMath.key) == today }
        }
        // Celebrate (and feed the pet for) tasks you completed in the Todoist app since the last sync.
        let ids = Set(completed.map(\.id))
        let fresh = completed.filter { !knownCompleted.contains($0.id) && !completedViaPet.contains($0.id) }
        // Steps for your wishes count even when finished in Todoist (the celebrated one counts in `celebrate`).
        for t in didLoadOnce ? Array(fresh.dropFirst()) : fresh { wishes.completeStep(taskId: t.id) }
        if didLoadOnce, let first = fresh.first {
            recompute()
            celebrate(first, viaPet: false, feeds: fresh.count)
        }
        knownCompleted = ids.union(completedViaPet)
        didLoadOnce = true
        tracker.record(DaySnapshot.build(active: act, completed: completed, now: Date()).open, now: Date())
        recompute()
    }

    private func refreshCalendar() {
        calendarAccess = calendar.access
        events = prefs.useCalendar ? calendar.events(on: Date()) : []
    }

    func requestCalendarAccess() {
        Task {
            _ = await calendar.requestAccess()
            refreshCalendar()
            recompute()
        }
    }

    func retryBrowsers() { browser.resetDenied() }

    func setClaudeKey(_ key: String?) {
        let k = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if k.isEmpty { Keychain.delete(.anthropic) } else { Keychain.save(k, .anthropic) }
        hasClaudeKey = Keychain.read(.anthropic) != nil
    }

    private func resetDay() {
        dayKey = DayMath.key(Date())
        fired = [:]
        plans.prune(today: dayKey)
        triggers.prune(today: dayKey)
        endedMeetings = []
        pendingAfterMeeting = nil
        // "Where was I?" is forgotten at midnight.
        workContext = nil
        pinned = nil
        wishShows = 0
        knownCompleted = []
        completedViaPet = []
        didLoadOnce = false
        completed = []
    }

    // MARK: - Mood

    private struct Context {
        var workday: Bool
        var inWork: Bool
        var night: Bool
        var hoursAfterPlanDeadline: Double
        var reviewTime: Date
    }

    private func context(_ now: Date) -> Context {
        let h = Double(DayMath.hour(now)) + Double(Calendar.current.component(.minute, from: now)) / 60
        let workday = prefs.isWorkday(now)
        let inWork = workday && h >= Double(prefs.workStart) && h < Double(prefs.workEnd)
        let reviewTime = DayMath.at(hour: prefs.workEnd, on: now).addingTimeInterval(-30 * 60)
        return Context(workday: workday, inWork: inWork, night: h >= 23 || h < 6,
                       hoursAfterPlanDeadline: h - Double(prefs.planDeadline), reviewTime: reviewTime)
    }

    private var lastProgress: Date {
        let now = Date()
        let start = max(DayMath.at(hour: prefs.workStart, on: now), prefs.firstLaunch)
        var p = max(start, lastPlanAction, lastCelebration)
        if let latest = day.completed.compactMap(\.completedDate).max() { p = max(p, latest) }
        if let f = focus { p = max(p, min(now, f.start)) }
        // Deep work counts as progress, even before a task gets ticked off.
        p = max(p, flow ? now : lastFlowEnd)
        // Time in meetings counts as work.
        if let meetingEnd = events.filter({ $0.start <= now }).map({ min($0.end, now) }).max() { p = max(p, meetingEnd) }
        return p
    }

    private var distraction: (app: String, minutes: Double)? {
        Date() > distractionSnoozedUntil ? currentDistraction : nil
    }

    /// The distracting app or site in front right now, even while the pet was asked to let it go.
    private var currentDistraction: (app: String, minutes: Double)? {
        if prefs.watchBrowsers, let v = browser.visit,
           BrowserWatcher.match(host: v.host, url: v.url, rules: prefs.siteRules) != nil {
            return (v.host, Date().timeIntervalSince(v.since) / 60)
        }
        guard let f = frontApp else { return nil }
        let name = f.name.lowercased(), bundle = f.bundle.lowercased()
        guard prefs.distractionList.contains(where: { name.contains($0) || bundle.contains($0) }) else { return nil }
        return (f.name, Date().timeIntervalSince(f.since) / 60)
    }

    func recompute() {
        let now = Date()
        var snap = DaySnapshot.build(active: active, completed: completed, now: now)
        snap.frogId = plans.plan(for: DayMath.key(now))?.frogId
        day = snap
        let ctx = context(now)
        let done = plans.isDoneForToday(now)
        if doneForToday != done { doneForToday = done }
        browser.enabled = prefs.watchBrowsers

        let dayStart = DayMath.at(hour: prefs.workStart, on: now)
        let dayEnd = DayMath.at(hour: prefs.workEnd, on: now)
        let newTarget = prefs.adaptTarget && !events.isEmpty
            ? CalendarMath.target(freeMinutes: CalendarMath.freeMinutes(events, from: dayStart, to: dayEnd), maxTarget: prefs.dailyTarget)
            : prefs.dailyTarget
        if target != newTarget { target = newTarget }
        let newSuggestions = ctx.inWork ? CalendarMath.suggest(tasks: day.actionable, events: events, now: now, dayEnd: dayEnd) : []
        if suggestions != newSuggestions { suggestions = newSuggestions }
        let newStuck = tracker.stuck(day.open, minDays: prefs.stuckDays, now: now)
        if stuck != newStuck { stuck = newStuck }
        let newLoad = DayLoadRules.load(tasks: day.open, events: events, now: now, workStart: prefs.workStart,
                                        workEnd: prefs.workEnd, defaultMinutes: prefs.defaultEstimate)
        if load != newLoad { load = newLoad }
        let st = DayLoadRules.strip(tasks: day.open, events: events, now: now, workStart: prefs.workStart,
                                    workEnd: prefs.workEnd, defaultMinutes: prefs.defaultEstimate)
        if strip != st.segments { strip = st.segments }
        if abs(stripNow - st.now) > 0.002 { stripNow = st.now }
        settleLife(now)
        if life.state.week.key.isEmpty { life.mutate { WeekRules.roll(&$0, today: now) } }
        if hasToken && didLoadOnce {
            // A packed calendar (under an hour free) excuses a day with nothing done.
            let busy = prefs.useCalendar && !events.isEmpty && CalendarMath.freeMinutes(events, from: dayStart, to: dayEnd) < 60
            let s = life.state, done = day.completed.count, planned = day.planned, goal = target, workday = ctx.workday
            if s.dayCompleted != done || s.dayPlanned != planned || s.dayTarget != goal || s.dayWorkday != workday
                || !s.daySeen || (busy && !s.dayBusy) {
                let streakBefore = s.streak
                let restored = life.mutate { (x: inout LifeState) -> Bool in
                    LifeRules.syncDay(&x, completed: done, planned: planned, target: goal, workday: workday, busy: busy)
                    return LifeRules.checkRepair(&x)
                }
                if restored {
                    repairNote = true
                    log.add(.life, L("Nối lại chuỗi: \(streakBefore) → \(life.state.streak) ngày (xong \(LifeRules.repairTasks) việc)",
                                     "Streak mended: \(streakBefore) → \(life.state.streak) days (\(LifeRules.repairTasks) tasks done)"))
                }
            }
        }

        var i = MoodInputs()
        i.hasToken = hasToken
        i.workday = ctx.workday
        i.inWorkHours = ctx.inWork
        i.night = ctx.night
        i.hoursAfterPlanDeadline = ctx.hoursAfterPlanDeadline
        i.target = target
        i.inMeeting = CalendarMath.current(events, at: now) != nil
        i.stuck = stuck.count
        i.planned = day.planned
        i.completed = day.completed.count
        i.remaining = day.remaining
        i.overdue = day.overdue.count
        i.late = day.late.count
        i.minutesSinceProgress = now.timeIntervalSince(lastProgress) / 60
        i.minutesSinceCelebration = now.timeIntervalSince(lastCelebration) / 60
        if let d = distraction { i.distractedMinutes = d.minutes; i.distractionApp = d.app }
        i.idleMinutes = Brain.idleSeconds() / 60
        i.focusing = focus.map { !$0.isBreak } ?? false
        i.celebratingNow = now < celebrateUntil
        i.satiety = life.state.satiety
        i.dirt = life.state.dirt
        i.doneForToday = done
        let r = MoodEngine.evaluate(i)
        score = r.score
        reasons = r.reasons
        if mood != r.mood {
            // Celebrations are logged with the finished task; everything else gets its reasons.
            if mood != .celebrating && r.mood != .celebrating {
                let why = r.reasons.prefix(2).map { "\($0.delta > 0 ? "+" : "")\($0.delta) \($0.text)" }.joined(separator: "; ")
                log.add(.mood, L("Tâm trạng: \(mood.label) → \(r.mood.label) (điểm \(Int(r.score)))",
                                 "Mood: \(mood.label) → \(r.mood.label) (score \(Int(r.score)))") + (why.isEmpty ? "" : " — " + why),
                        throttle: "mood-\(mood.rawValue)-\(r.mood.rawValue)", every: 2)
            }
            mood = r.mood
        }
        log.enabled = prefs.keepLog
        if mood == .angry { angrySince = angrySince ?? now } else { angrySince = nil }
    }

    /// Settles a finished day (streak, snacks, sticker, dirt) once the date has changed, even after a restart.
    private func settleLife(_ now: Date) {
        let today = DayMath.key(now)
        guard life.state.dayKey != today else { return }
        let before = life.state
        let r = life.mutate { s in
            LifeRules.closeDay(&s, today: today) { [prefs] key in DateParse.parse(key).map(prefs.isWorkday) ?? false }
        }
        let after = life.state
        if !r.day.isEmpty {
            let outcome: String = switch r.outcome {
            case .kept: L("giữ chuỗi", "streak kept")
            case .excused: L("lịch kín, được miễn", "packed calendar, excused")
            case .frozen: L("lỡ ngày, dùng 1 🍪 để giữ chuỗi", "missed, a 🍪 saved the streak")
            case .broken: L("lỡ ngày, chuỗi \(r.lost) ngày bị đứt", "missed, the \(r.lost)-day streak broke")
            case .none: before.daySeen ? L("ngày nghỉ", "day off") : L("máy tắt hoặc chưa đồng bộ, không tính", "Mac off or never synced, doesn't count")
            }
            var text = L("Chốt ngày \(r.day): xong \(before.dayCompleted)/\(before.dayTarget) → \(outcome), chuỗi \(after.streak) ngày",
                         "Closed \(r.day): \(before.dayCompleted)/\(before.dayTarget) done → \(outcome), \(after.streak)-day streak")
            if r.sticker { text += L(", nhận sticker 🌟", ", earned a 🌟 sticker") }
            if r.snackEarned { text += L(", thêm 1 🍪 (có \(after.snacks))", ", +1 🍪 (\(after.snacks) in the stash)") }
            if after.dirt > before.dirt { text += L(", bẩn thêm 1 lớp", ", one more layer of dirt") }
            if r.pageDone { text += L(", đầy một trang sticker (+50 XP, +1 🍪)", ", filled a sticker page (+50 XP, +1 🍪)") }
            if r.repairOffered { text += L(", mở nhiệm vụ nối chuỗi tới \(after.repair?.until ?? "")", ", repair quest until \(after.repair?.until ?? "")") }
            if r.repairExpired { text += L(", hết hạn nối chuỗi", ", the repair quest ran out") }
            log.add(.life, text)
            dayNote = [Lines.dayClosed(r, streak: after.streak, snacks: after.snacks), r.pageDone ? Lines.stickerPage(after.stickerPage - 1) : nil]
                .compactMap { $0 }.joined(separator: "\n").nilIfEmpty
        }
        if !r.unlocked.isEmpty {
            say(Bubble(text: Lines.unlocked(r.unlocked), seconds: 12, urgent: true))
        }
    }

    private func speak(_ text: String) {
        if prefs.voiceOn { Voice.shared.say(text) }
    }

    func endAntic() {
        antic = nil
    }

    private func spareAction() -> BubbleAction {
        BubbleAction(title: L("Tha cho tôi 15'", "Spare me 15'"), neutral: true) { [weak self] in
            let until = Date().addingTimeInterval(15 * 60)
            self?.anticSnoozedUntil = until
            self?.distractionSnoozedUntil = until
            self?.antic = nil
        }
    }

    static func idleSeconds() -> Double {
        if let any = CGEventType(rawValue: ~0) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        }
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    // MARK: - Talking

    /// Shows a bubble. `why` marks it as an unsolicited reminder and records the reason in the diary;
    /// without it the bubble is a reply to something you did. `kind` counts it against today's reminder budget.
    func say(_ b: Bubble, chime: Chime = .chatter, why: String? = nil, antic: Bool = false, kind: String? = nil) {
        if let cur = bubble, !cur.actions.isEmpty, !b.urgent, b.actions.isEmpty { return }
        // On a trip only urgent bubbles and replies get through.
        if life.state.trip != nil, why != nil, !b.urgent { return }
        var b = b
        b.reminder = why != nil
        b.kind = kind
        bubble = b
        lastBubbleAt = Date()
        if kind != nil { life.mutate { $0.dayNudges += 1 } }
        play(chime)
        let quote = "“" + TextClean.short(b.text.replacingOccurrences(of: "\n", with: " "), 90) + "”"
        let left = kind != nil ? L(" (còn \(nudgesLeft) lượt nhắc hôm nay)", " (\(nudgesLeft) left today)") : ""
        if let why {
            log.add(antic ? .antic : .bubble, quote + " — " + L("vì ", "because ") + why + left)
        } else {
            log.add(.system, L("Pet nói ", "Pet said ") + quote)
        }
    }

    /// A reminder that never showed (the board was open, or the pet hidden) costs nothing from the budget.
    func dropUnseen() {
        if bubble?.kind != nil { life.mutate { $0.dayNudges = max(0, $0.dayNudges - 1) } }
        bubble = nil
    }

    /// Unsolicited reminders left in today's budget.
    var nudgesLeft: Int { max(0, prefs.nudgeBudget - life.state.dayNudges) }

    /// What you did with the last bubble: tapped a button, closed it, or let it fade away.
    enum BubbleResponse {
        case picked(String, neutral: Bool), closed, ignored
    }

    /// A real answer to a reminder resets its back-off; closing one (or ignoring one with buttons) is a "no": that
    /// kind comes half as often (up to ×8), and three in a row hold the rest for an hour (Fitz et al. 2019).
    func noteResponse(_ r: BubbleResponse) {
        let b = bubble
        let kind = b?.kind
        if case .closed = r, b?.id == tripOfferId { declineTrip() }
        switch r {
        case .picked(let title, let neutral):
            log.add(.response, L("Bạn bấm “\(title)”", "You tapped “\(title)”"), tag: "picked")
            if b?.reminder == true, !neutral, life.state.dismissedInRow > 0 || kind.map({ life.state.dayBackoff[$0] != nil }) == true {
                life.mutate { s in
                    if let kind { s.dayBackoff[kind] = nil }
                    s.dismissedInRow = 0
                }
            }
            return
        case .closed: log.add(.response, L("Bạn đóng bong bóng", "You closed the bubble"), tag: "closed")
        case .ignored: log.add(.response, L("Bạn không phản hồi (tự ẩn)", "No response (faded away)"), tag: "ignored")
        }
        let closed = if case .closed = r { true } else { false }
        guard let kind, closed || !(b?.actions.isEmpty ?? true) else { return }
        let m = Brain.everyKinds.contains(kind) ? min(LifeRules.maxBackoff, (life.state.dayBackoff[kind] ?? 1) * 2) : nil
        life.mutate { s in
            if let m { s.dayBackoff[kind] = m }
            s.dismissedInRow += 1
        }
        if let m { log.add(.hold, L("→ lời nhắc “\(kind)” thưa hơn (×\(m))", "→ “\(kind)” reminders back off (×\(m))")) }
        if life.state.dismissedInRow >= Brain.holdAfter {
            let until = Date().addingTimeInterval(60 * 60)
            life.mutate { s in
                s.dismissedInRow = 0
                s.nudgeHoldUntil = until
            }
            log.add(.hold, L("Bạn bỏ qua \(Brain.holdAfter) lời nhắc liên tiếp — mình tạm im tới \(DayMath.timeString(until)) (việc gấp vẫn nhắc)",
                             "You passed on \(Brain.holdAfter) reminders in a row — holding the rest until \(DayMath.timeString(until)) (urgent ones still come)"))
        }
    }

    /// Kinds with an interval, which closing or ignoring stretches.
    static let everyKinds: Set<String> = ["distract", "antic", "plan", "stuck", "hungry", "grumble", "overdue", "nudge", "tip"]
    static let holdAfter = 3

    /// May an unsolicited reminder speak now? Not once today's budget is spent, nor during a hold after three refusals.
    private func mayRemind(_ kind: String) -> Bool {
        if life.state.dayNudges >= prefs.nudgeBudget {
            if once("budget-\(dayKey)") {
                log.add(.hold, L("Hôm nay hết lượt nhắc (tối đa \(prefs.nudgeBudget)): mình im lặng tới mai, trừ việc gấp",
                                 "No reminders left today (budget \(prefs.nudgeBudget)): quiet until tomorrow, except urgent ones"))
            }
            return false
        }
        if let until = life.state.nudgeHoldUntil, Date() < until {
            log.add(.hold, L("Giữ lời nhắc “\(kind)” tới \(DayMath.timeString(until)): bạn vừa bỏ qua \(Brain.holdAfter) lời nhắc liên tiếp",
                             "Held a reminder (\(kind)) until \(DayMath.timeString(until)): you passed on \(Brain.holdAfter) in a row"),
                    throttle: "hold-dismissed-\(kind)", every: 15)
            return false
        }
        return true
    }

    enum Chime {
        /// An ordinary bubble.
        case chatter
        /// A meeting or task time, the end of a focus session.
        case important
        /// A finished task.
        case celebrate
        /// A golden treat or growing up.
        case big
        /// Mischief.
        case grumble
    }

    private var playing: NSSound?

    /// Plays a soft system sound, if the sound setting allows this kind.
    private func play(_ c: Chime) {
        switch (prefs.soundMode, c) {
        case (.off, _), (.important, .chatter), (.important, .grumble): return
        default: break
        }
        let (name, volume): (String, Float) = switch c {
        case .chatter: ("Pop", 0.2)
        case .important: ("Tink", 0.4)
        case .celebrate: ("Glass", 0.25)
        case .big: ("Hero", 0.3)
        case .grumble: ("Basso", 0.25)
        }
        guard let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
        playing = sound
    }

    private func once(_ key: String) -> Bool {
        if fired[key] != nil { return false }
        fired[key] = Date()
        return true
    }

    private func every(_ key: String, minutes: Double) -> Bool {
        guard isDue(key, minutes: minutes) else { return false }
        fired[key] = Date()
        return true
    }

    func quiet(minutes: Double?) {
        quietUntil = minutes.map { Date().addingTimeInterval($0 * 60) }
        if minutes != nil { bubble = nil }
        if let q = quietUntil {
            log.add(.hold, L("Bạn bật im lặng tới \(DayMath.timeString(q))", "You muted the pet until \(DayMath.timeString(q))"))
        } else {
            log.add(.system, L("Bạn bật lại nhắc nhở", "You turned reminders back on"))
        }
    }

    private func tick() {
        let now = Date()
        if DayMath.key(now) != dayKey {
            resetDay()
            refreshSoon()
        }
        if let f = focus, now >= f.end { finishFocus() }
        if hasToken, !loading, lastSync.map({ now.timeIntervalSince($0) > 180 }) ?? true { refreshSoon() }
        refreshCalendar()
        // Hunger grows during work hours (not during meetings or while you're away).
        let ctx = context(now)
        let working = hasToken && ctx.inWork && CalendarMath.current(events, at: now) == nil && Brain.idleSeconds() < 300
        life.mutate { LifeRules.decay(&$0, now: now, working: working) }
        if hasToken, ctx.inWork, let d = currentDistraction {
            life.mutate { LifeRules.addDistraction(&$0, label: d.app, seconds: 15) }
        }
        // Left the distracting app or site: the pet gets out of the way.
        if case .block? = antic?.kind, currentDistraction == nil { antic = nil }
        trackDistraction(now)
        trackMeeting(now)
        snapshotWork(now)
        updateFlow(now)
        playGame(now, ctx: ctx)
        recompute()
        runRules(now)
    }

    /// Chests for real work time, knitting during focus, and the trip coming home.
    private func playGame(_ now: Date, ctx: Context) {
        let elapsed = min(60, max(0, now.timeIntervalSince(lastTickAt)))
        lastTickAt = now
        guard hasToken else { return }
        if let t = life.state.trip, now >= t.back { comeHome(now) }
        let atMac = Brain.idleSeconds() < 60
        let inMeeting = CalendarMath.current(events, at: now) != nil
        if ctx.inWork, atMac, !inMeeting, currentDistraction == nil, life.state.trip == nil,
           life.mutate({ ChestRules.addWork(&$0, seconds: elapsed) }) {
            pendingChest = true
            log.add(.life, L("Được 1 rương 🎁 sau 30 phút làm việc (đang giữ \(life.state.chests))",
                             "Earned a chest 🎁 for 30 minutes of work (\(life.state.chests) held)"))
        }
        guard let f = focus, !f.isBreak else {
            stitchesDropped = nil
            return
        }
        if let d = currentDistraction {
            if d.minutes >= 0.5, stitchesDropped != d.app, life.mutate({ CraftRules.dropStitches(&$0) }) {
                stitchesDropped = d.app
                log.add(.life, L("Tuột vài mũi len vì \(d.app) giữa giờ tập trung", "Dropped a few stitches over \(d.app) during focus"))
            }
            return
        }
        guard atMac else { return }
        // The last seconds up to 0:00 count too.
        let seconds = min(elapsed, max(0, f.end.timeIntervalSince(now - elapsed)))
        if let done = life.mutate({ CraftRules.knit(&$0, seconds: seconds, sessionMinutes: f.minutes, pick: .random(in: 0..<1), today: dayKey) }) {
            craftNote = Lines.crafted(done)
            log.add(.life, done.decor.map { L("Đan xong \($0.emoji) \($0.name)", "Knitted \($0.emoji) \($0.name)") }
                ?? L("Đan xong một món nữa (+\(done.xp) XP)", "Knitted one more piece (+\(done.xp) XP)"))
        }
    }

    // MARK: - Trips

    /// The plan is done: the pet asks to go on a little trip (a check-in, never counted against the budget).
    private func offerTrip(_ now: Date) {
        let back = min(now.addingTimeInterval(TripRules.maxMinutes * 60), DayMath.at(hour: prefs.workEnd, on: now))
        var b = Bubble(text: Lines.tripOffer(back: back), actions: [
            BubbleAction(title: L("🧳 Đi đi!", "🧳 Go!"), primary: true) { [weak self] in self?.goOnTrip() },
            BubbleAction(title: L("Ở nhà", "Stay"), neutral: true) { [weak self] in self?.declineTrip() },
        ], seconds: 60)
        b.urgent = false
        tripOfferId = b.id
        say(b, why: L("xong hết kế hoạch hôm nay, còn hơn 1 giờ làm việc", "today's plan is done with an hour or more of work left"))
    }

    func goOnTrip() {
        let now = Date()
        let trip = life.mutate { TripRules.start(&$0, now: now, workEnd: DayMath.at(hour: prefs.workEnd, on: now), pick: .random(in: 0..<1)) }
        let place = TripRules.souvenir(trip.place)
        log.add(.life, L("Pet đi \(place.placeName), về lúc \(DayMath.timeString(trip.back))", "The pet went to \(place.placeName), back at \(DayMath.timeString(trip.back))"))
        bubble = Bubble(text: Lines.tripGone(place, back: trip.back), seconds: 6, urgent: true)
        lastBubbleAt = now
        recompute()
    }

    private func declineTrip() {
        life.mutate { $0.tripDeclined = dayKey }
    }

    /// Calls the pet back early (before 30 minutes there's no souvenir, and the trip isn't used up).
    func callBack() { comeHome(Date()) }

    private func comeHome(_ now: Date) {
        guard let r = life.mutate({ TripRules.finish(&$0, now: now) }) else { return }
        if r.early {
            log.add(.life, L("Bạn gọi pet về sớm, chưa kịp mua quà", "You called the pet back early, no souvenir yet"))
            bubble = Bubble(text: Lines.tripEarly(r.souvenir), seconds: 6, urgent: true)
        } else {
            log.add(.life, L("Bưu thiếp từ \(r.souvenir.placeName): “\(r.souvenir.postcardText)”", "Postcard from \(r.souvenir.placeName): “\(r.souvenir.postcardText)”"),
                    tag: "postcard")
            celebration = CelebrationEvent(kind: .jump, food: r.souvenir.emoji, golden: false, combo: 0, start: now)
            celebrateUntil = now.addingTimeInterval(4)
            play(.celebrate)
            bubble = Bubble(text: Lines.tripBack(r), seconds: 20, urgent: true)
        }
        lastBubbleAt = now
        recompute()
    }

    /// Notices a meeting ending: if-then plans waiting for it, and the "anything to capture?" bookend.
    private func trackMeeting(_ now: Date) {
        let m = CalendarMath.current(events, at: now)
        if let cur = currentMeeting, m?.id != cur.id {
            endedMeetings.insert(cur.id)
            // Only a meeting you were around for (not one that passed while you were away).
            if cur.minutes >= 15, Brain.idleSeconds() < 15 * 60 { pendingAfterMeeting = (cur, now) }
            log.add(.meeting, L("Họp “\(TextClean.short(cur.title, 40))” kết thúc", "“\(TextClean.short(cur.title, 40))” ended"))
        }
        currentMeeting = m
    }

    /// Remembers what you're working on (task, app, page) while you're at the Mac in a work app. Memory only.
    private func snapshotWork(_ now: Date) {
        guard hasToken, Brain.idleSeconds() < 120, let f = frontApp, ResumeRules.isWorkApp(bundle: f.bundle),
              currentDistraction == nil else { return }
        let visit = BrowserWatcher.isBrowser(f.bundle) ? browser.visit : nil
        if let v = visit, ResumeRules.isConferencing(bundle: nil, url: v.url) { return }
        let details = prefs.resumeDetails && !(visit?.isPrivate ?? false)
        let task = focus.flatMap { $0.isBreak ? nil : $0.task } ?? lastActedTask.flatMap { t in day.open.first { $0.id == t.id } }
        let next = task == nil ? day.next : nil
        workContext = WorkContext(taskId: (task ?? next)?.id, taskTitle: (task ?? next)?.title, taskIsNext: task == nil && next != nil,
                                  app: f.name.isEmpty ? nil : f.name, bundle: f.bundle,
                                  pageTitle: details ? visit.flatMap { $0.title.isEmpty ? nil : TextClean.short($0.title, 120) } : nil,
                                  url: details ? ResumeRules.workURL(visit?.url) : nil, note: nil, at: now)
    }

    private func noteRecentApp() {
        guard let f = frontApp, ResumeRules.isWorkApp(bundle: f.bundle), !f.name.isEmpty else { return }
        let lower = f.name.lowercased(), bundle = f.bundle.lowercased()
        if prefs.distractionList.contains(where: { lower.contains($0) || bundle.contains($0) }) { return }
        recentApps.removeAll { $0.bundle == f.bundle }
        recentApps.insert((f.name, f.bundle), at: 0)
        recentApps = Array(recentApps.prefix(6))
    }

    /// Tracks steady typing in work apps; ten minutes of it is "the zone".
    private func updateFlow(_ now: Date) {
        let sinceKey = CalmRules.secondsSinceKey()
        let engaged = CalmRules.engaged(secondsSinceKey: sinceKey, idleSeconds: Brain.idleSeconds(), distracted: currentDistraction != nil)
        engagedSince = CalmRules.engagedSince(engagedSince, engaged: engaged, secondsSinceKey: sinceKey, now: now)
        let inFlow = prefs.protectFlow && hasToken && CalmRules.inFlow(engagedSince: engagedSince, now: now)
        if flow != inFlow {
            flow = inFlow
            if inFlow {
                flowStartedAt = engagedSince ?? now
                log.add(.flow, L("Bạn vào guồng (gõ phím đều 10 phút) — pet giữ im lặng",
                                 "You're in the zone (10 minutes of steady typing) — the pet stays quiet"), tag: "flowStart")
            } else {
                lastFlowEnd = now
                let minutes = Int(now.timeIntervalSince(flowStartedAt) / 60)
                log.add(.flow, L("Hết guồng sau \(minutes) phút", "Left the zone after \(minutes) minutes"), tag: "flowEnd", minutes: minutes)
            }
        }
    }

    /// Logs how long you stay in each distracting app or site.
    private func trackDistraction(_ now: Date) {
        let current = currentDistraction?.app
        if let s = distractionSession, s.label != current {
            let minutes = Int(now.timeIntervalSince(s.start) / 60)
            if minutes >= 1 {
                log.add(.distraction, L("Rời \(s.label) sau \(minutes) phút", "Left \(s.label) after \(minutes) minutes"),
                        tag: "end", minutes: minutes)
            }
            leftDetour = (s.label, now.timeIntervalSince(s.start) / 60, now)
            distractionSession = nil
        }
        guard let label = current else { return }
        if distractionSession == nil { distractionSession = (label, now, false) }
        if let s = distractionSession, !s.logged, now.timeIntervalSince(s.start) >= 120 {
            log.add(.distraction, L("Đang ở \(label) hơn 2 phút", "On \(label) for 2+ minutes"))
            distractionSession?.logged = true
        }
    }

    private func focusAction(_ task: TodoTask?) -> BubbleAction {
        BubbleAction(title: "▶︎ " + L("Tập trung \(prefs.focusMinutes)'", "Focus \(prefs.focusMinutes)'"), primary: true) { [weak self] in
            self?.startFocus(task)
        }
    }

    private func laterAction(_ minutes: Double = 30) -> BubbleAction {
        BubbleAction(title: L("Để sau", "Later"), neutral: true) { [weak self] in
            self?.fired["nudge"] = Date().addingTimeInterval(minutes * 60 - Double(self?.prefs.remindEvery ?? 45) * 60)
        }
    }

    private func runRules(_ now: Date) {
        if let q = quietUntil, now < q { return }
        quietUntil = nil

        let idle = Brain.idleSeconds()
        if idle > 300 {
            if awaySince == nil {
                awaySince = now.addingTimeInterval(-idle)
                log.add(.system, L("Bạn rời máy từ \(DayMath.timeString(awaySince!)) — pet không nhắc gì",
                                   "You stepped away at \(DayMath.timeString(awaySince!)) — no reminders"))
            }
            return
        }

        // Meetings come first, even during a focus session; during a meeting the pet stays quiet.
        if let e = CalendarMath.next(events, after: now) {
            let mins = e.start.timeIntervalSince(now) / 60
            if mins <= Double(prefs.meetingLead), once("meeting-\(e.id)") {
                var text = Lines.meetingSoon(e, minutes: max(1, Int(mins.rounded(.up))))
                let related = RelatedTasks.related(to: e.title, in: day.actionable)
                if !related.isEmpty { text += "\n" + Lines.related(related) }
                var actions: [BubbleAction] = []
                if let url = e.joinURL {
                    actions.append(BubbleAction(title: L("Vào họp ↗", "Join ↗"), primary: true) { NSWorkspace.shared.open(url) })
                }
                actions.append(BubbleAction(title: "OK") {})
                say(Bubble(text: text, actions: actions, seconds: 90, urgent: true),
                    chime: .important, why: L("họp lúc \(DayMath.timeString(e.start))", "meeting at \(DayMath.timeString(e.start))"))
                return
            }
        }
        if let m = CalendarMath.current(events, at: now) {
            if once("in-meeting-\(m.id)") {
                log.add(.meeting, L("Đang họp “\(m.title)” tới \(DayMath.timeString(m.end)) — pet giữ im lặng",
                                    "In “\(m.title)” until \(DayMath.timeString(m.end)) — the pet stays quiet"))
            }
            return
        }
        if focus != nil { return }

        guard hasToken else {
            if every("token", minutes: 60) { askForToken() }
            return
        }
        let ctx = context(now)
        let target = self.target

        if let away = awaySince {
            awaySince = nil
            let minutes = Int(now.timeIntervalSince(away) / 60)
            log.add(.system, L("Bạn quay lại sau \(minutes) phút", "You came back after \(minutes) minutes"))
            if ctx.inWork, !doneForToday {
                gesture = PetGesture(kind: .wave, start: now)
                let why = L("bạn vừa quay lại sau \(minutes) phút", "you just came back after \(minutes) minutes")
                if ResumeRules.shouldOffer(awayMinutes: Double(minutes)), offerResume(why: Lines.resumeWhyAway(minutes), reason: why) { return }
                if minutes > 15, let next = day.next, mayRemind("welcome") {
                    say(Bubble(text: Lines.welcomeBack(next), actions: [focusAction(next), laterAction()], seconds: 30), why: why, kind: "welcome")
                    return
                }
            }
        }

        // 1. Tasks with an exact time: 10 minutes before, and when due.
        for t in day.open {
            guard let time = t.dueTime else { continue }
            let mins = time.timeIntervalSince(now) / 60
            if mins > 0, mins <= 10, once("soon-\(t.id)") {
                say(Bubble(text: Lines.soon(t, minutes: Int(mins.rounded(.up))),
                           actions: [focusAction(t), completeAction(t)], seconds: 40, urgent: true), chime: .important,
                    why: L("việc hẹn lúc \(DayMath.timeString(time))", "task due at \(DayMath.timeString(time))"))
                return
            }
            if mins <= 0, mins > -5, once("now-\(t.id)") {
                say(Bubble(text: Lines.dueNow(t), actions: [focusAction(t), completeAction(t)], seconds: 60, urgent: true),
                    chime: .important, why: L("tới giờ hẹn \(DayMath.timeString(time))", "due now (\(DayMath.timeString(time)))"))
                return
            }
        }
        if bubble != nil { return }

        // Meeting bookends: after a meeting of 15+ minutes, "anything to capture?", and a breather before the next one.
        if let pm = pendingAfterMeeting {
            pendingAfterMeeting = nil
            if now.timeIntervalSince(pm.at) < 10 * 60, ctx.inWork {
                var text = Lines.afterMeeting(pm.event)
                if let n = CalendarMath.next(events, after: now) {
                    let left = Int(n.start.timeIntervalSince(now) / 60)
                    if left >= 3, left <= 15 { text += "\n" + Lines.breather(minutes: left, next: n) }
                }
                var actions = [BubbleAction(title: L("＋ Việc tiếp theo", "＋ Next step"), primary: true) { [weak self] in
                    self?.openAdd?(TextClean.short(pm.event.title, 40) + ": ")
                }]
                if prefs.resumeCard, let c = pinned ?? workContext, c.url != nil || c.bundle != nil {
                    actions.append(BubbleAction(title: L("↩︎ Quay lại việc", "↩︎ Back to work")) { [weak self] in self?.reopen(c) })
                    lastResumeAt = now
                }
                actions.append(BubbleAction(title: L("Không có gì", "Nothing"), neutral: true) {})
                say(Bubble(text: text, actions: actions, seconds: 60),
                    why: L("họp “\(TextClean.short(pm.event.title, 30))” vừa xong", "“\(TextClean.short(pm.event.title, 30))” just ended"))
                return
            }
        }

        // If-then starts: the moment you planned has come.
        if !doneForToday, let t = TriggerRules.due(triggers.list, today: dayKey, now: now, endedMeetings: endedMeetings,
                                                   front: frontApp.map { ($0.bundle, $0.since) }).first {
            triggers.markFired(t.taskId, day: dayKey)
            if let task = day.open.first(where: { $0.id == t.taskId }) {
                say(Bubble(text: Lines.triggerFired(task, t.trigger), actions: [
                    focusAction(task),
                    BubbleAction(title: L("⏱ Thử 2'", "⏱ Try 2'")) { [weak self] in self?.startStarter(task) },
                    BubbleAction(title: L("Để sau 30'", "Later 30'"), neutral: true) { [weak self] in
                        guard let self else { return }
                        triggers.rearm(task.id, day: dayKey, notBefore: Date().addingTimeInterval(30 * 60))
                    },
                ], seconds: 60, urgent: true), chime: .important,
                    why: L("bạn hẹn bắt đầu \(t.trigger.label)", "you planned to start \(t.trigger.label)"))
                return
            }
        }

        // On a trip: nothing below gets through.
        if life.state.trip != nil { return }

        // A chest was earned: a small reply-style note at a calm moment (never counted).
        if pendingChest, !flow, CalmRules.atBreakpoint(secondsSinceKey: CalmRules.secondsSinceKey(), secondsSinceAppSwitch: now.timeIntervalSince(lastAppSwitch)) {
            pendingChest = false
            say(Bubble(text: Lines.chestFound(held: life.state.chests), seconds: 8))
            return
        }

        // Done for today: only meetings and timed tasks get through.
        if doneForToday { return }

        // Distraction apps and sites come first: there's no concentration to protect right then.
        // Grumpy and stuck on one for 5+ minutes: the pet jumps in the way.
        if prefs.antics, ctx.inWork, mood == .angry, now > anticSnoozedUntil, day.open.count > 0, let d = distraction,
           d.minutes >= 5, mayRemind("antic"), every("antic", minutes: 20) {
            antic = AnticEvent(kind: .block, start: now)
            say(Bubble(text: Lines.block(app: d.app, next: day.next), actions: [focusAction(day.next), spareAction()],
                       seconds: 25, urgent: true), chime: .grumble,
                why: L("đang cáu và ở \(d.app) \(Int(d.minutes)) phút → nhảy lên chắn màn hình",
                       "grumpy and on \(d.app) for \(Int(d.minutes)) min → jumped in the way"), antic: true, kind: "antic")
            speak(Lines.voiceBlock(app: d.app))
            return
        }
        if ctx.inWork, day.open.count > 0, let d = distraction, d.minutes >= 2, mayRemind("distract"), every("distract", minutes: 10) {
            say(Bubble(text: Lines.distraction(mood: mood, app: d.app, left: day.open.count, next: day.next), actions: [
                focusAction(day.next),
                BubbleAction(title: L("Nghỉ xíu thôi (10')", "Just a quick break (10')"), neutral: true) { [weak self] in
                    self?.distractionSnoozedUntil = Date().addingTimeInterval(600)
                },
            ], seconds: 30), why: L("ở \(d.app) \(Int(d.minutes)) phút trong giờ làm", "on \(d.app) for \(Int(d.minutes)) min during work hours"),
                kind: "distract")
            return
        }

        // Back from a detour on a distracting app or site: here's where you were.
        if let d = leftDetour {
            leftDetour = nil
            if ctx.inWork, now.timeIntervalSince(d.at) < 10 * 60, currentDistraction == nil,
               ResumeRules.shouldOffer(leftDistractionMinutes: d.minutes),
               offerResume(why: Lines.resumeWhyDetour(d.label),
                           reason: L("vừa rời \(d.label) sau \(Int(d.minutes)) phút", "just left \(d.label) after \(Int(d.minutes)) min")) {
                return
            }
        }

        if ctx.night, DayMath.hour(now) >= 23, mayRemind("night"), once("night-\(dayKey)") {
            say(Bubble(text: Lines.lateNight(), seconds: 10), why: L("đã quá 23 giờ mà bạn vẫn dùng máy", "past 11pm and you're still at it"),
                kind: "night")
            return
        }

        // 2. Everything finished.
        if !day.completed.isEmpty, day.remaining == 0, day.overdue.isEmpty, once("alldone-\(dayKey)") {
            celebrateUntil = now.addingTimeInterval(4)
            recompute()
            say(Bubble(text: Lines.allDone(), actions: [
                BubbleAction(title: L("＋ Việc cho mai", "＋ Plan tomorrow")) { [weak self] in self?.openBoard?(true) },
            ], seconds: 20), why: L("xong hết việc hôm nay", "everything for today is done"))
            return
        }

        // Calm: everything below can wait. Never during deep work, only at a natural pause
        // (a typing break or an app switch), and at most one unsolicited bubble per `bubbleGap` minutes.
        // Held reminders are written to the diary so the thresholds can be tuned.
        let somethingDue = ctx.inWork && (
            (day.planned < target && ctx.hoursAfterPlanDeadline >= 0 && isDue("plan", minutes: 30))
                || (day.next != nil && now.timeIntervalSince(lastBubbleAt) > Double(prefs.remindEvery) * 60
                    && isDue("nudge", minutes: Double(prefs.remindEvery)))
                || stuck.contains { fired["stuck-\($0.task.id)-\(dayKey)"] == nil }
                || (life.state.hungry && isDue("hungry", minutes: 60)))
        if flow {
            if somethingDue {
                log.add(.hold, L("Có lời nhắc đến hạn nhưng bạn đang vào guồng — để sau", "A reminder is due but you're in the zone — later"),
                        throttle: "hold-flow", every: 15)
            }
            return
        }
        if !CalmRules.atBreakpoint(secondsSinceKey: CalmRules.secondsSinceKey(), secondsSinceAppSwitch: now.timeIntervalSince(lastAppSwitch)) {
            if somethingDue {
                log.add(.hold, L("Hoãn nhắc vì bạn đang gõ phím — chờ bạn ngừng tay", "Held a reminder: you're typing — waiting for a pause"),
                        throttle: "hold-typing", every: 10)
            }
            return
        }
        if !CalmRules.withinBudget(lastBubbleAt: lastBubbleAt, now: now, minGap: Double(prefs.bubbleGap)) {
            if somethingDue {
                log.add(.hold, L("Hoãn nhắc: lần nhắc trước lúc \(DayMath.timeString(lastBubbleAt)), cần cách ít nhất \(prefs.bubbleGap) phút",
                                 "Held a reminder: last one at \(DayMath.timeString(lastBubbleAt)), at least \(prefs.bubbleGap) min apart"),
                        throttle: "hold-gap", every: 10)
            }
            return
        }

        guard ctx.workday else { return }

        // 3. Morning greeting, with planning if today has fewer than `target` tasks.
        if ctx.inWork, once("morning-\(dayKey)") {
            let needsPlan = day.planned < target
            if needsPlan { fired["plan"] = now }
            var text = Lines.morning(now, day: day, target: target)
            if !events.isEmpty {
                let start = DayMath.at(hour: prefs.workStart, on: now), end = DayMath.at(hour: prefs.workEnd, on: now)
                let free = CalendarMath.freeMinutes(events, from: start, to: end)
                text += "\n" + Lines.calendarDay(meetings: events.count, busyMinutes: end.timeIntervalSince(start) / 60 - free,
                                                 freeMinutes: free, target: target, reduced: target < prefs.dailyTarget)
            }
            if life.state.dirt > 0 { text += "\n" + Lines.dirty(life.state.dirt) }
            if let p = plans.plan(for: dayKey),
               let m = Lines.morningPlan(frog: p.frogId.flatMap { id in day.open.first { $0.id == id } }, note: p.note) {
                text += "\n" + m
            }
            if let n = dayNote {
                text += "\n" + n
                dayNote = nil
            } else if life.state.streak > 0 {
                text += "\n" + Lines.streak(life.state.streak)
            }
            if prefs.wishPerDay > 0, let w = WishRules.next(wishes.wishes) {
                text += "\n" + Lines.wishOfDay(w)
                fired["wish"] = now   // the first wish reminder comes later in the day
            }
            // The first greeting of a week opens a new chapter, with last week's recap.
            if let last = life.state.lastWeek, life.state.chapterShown != life.state.week.key {
                text += "\n" + Lines.weekRecap(last)
                life.mutate { $0.chapterShown = $0.week.key }
            }
            say(Bubble(text: text,
                       actions: needsPlan ? planActions() : (day.next.map { [focusAction($0), laterAction()] } ?? []),
                       seconds: 60),
                why: L("lời chào đầu ngày làm việc", "first greeting of the workday")
                    + (needsPlan ? L(", mới có \(day.planned)/\(target) việc", ", only \(day.planned)/\(target) planned") : ""))
            return
        }

        // 3a. The plan is done: a little trip, back with a souvenir.
        let minutesToEnd = DayMath.at(hour: prefs.workEnd, on: now).timeIntervalSince(now) / 60
        let planDone = day.completed.count >= target && day.remaining == 0
        if TripRules.shouldOffer(planDone: planDone, inWork: ctx.inWork, minutesToEnd: minutesToEnd, today: dayKey,
                                 tripDay: life.state.tripDay, declined: life.state.tripDeclined, away: life.state.trip != nil),
           once("trip-\(dayKey)") {
            offerTrip(now)
            return
        }

        // 3b. Overbooked: tasks plus the meetings ahead run an hour or more past the time left. Once a day.
        if ctx.inWork, day.planned >= target || ctx.hoursAfterPlanDeadline >= 0, DayLoadRules.isOverbooked(load), once("overbooked-\(dayKey)") {
            say(Bubble(text: Lines.overbooked(load), actions: [
                BubbleAction(title: L("Chọn việc để dời", "Pick tasks to move"), primary: true) { [weak self] in self?.openWrapUp?(true) },
                BubbleAction(title: L("Ổn mà", "It's fine"), neutral: true) {},
            ], seconds: 60), why: L("việc + họp vượt thời gian còn lại \(DayLoadRules.text(load.overBy))",
                                    "tasks + meetings run \(DayLoadRules.text(load.overBy)) past the time left"))
            return
        }

        // 4. Not planned enough: a reminder every 30 minutes once the planning deadline passed.
        if ctx.inWork, day.planned < target, ctx.hoursAfterPlanDeadline >= 0, mayRemind("plan"), every("plan", minutes: 30) {
            say(Bubble(text: Lines.plan(mood: mood, planned: day.planned, target: target), actions: planActions(), seconds: 60),
                why: L("đã qua \(prefs.planDeadline)h mà mới có \(day.planned)/\(target) việc", "past \(prefs.planDeadline):00 with only \(day.planned)/\(target) planned"),
                kind: "plan")
            return
        }

        // 6. A task that keeps getting postponed: offer to split it (or drop it). Once per task per day.
        if ctx.inWork, let s = stuck.first(where: { fired["stuck-\($0.task.id)-\(dayKey)"] == nil }), mayRemind("stuck"), every("stuck", minutes: 120) {
            fired["stuck-\(s.task.id)-\(dayKey)"] = now
            say(Bubble(text: Lines.stuck(s, mood: mood), actions: [
                BubbleAction(title: L("✂️ Chia nhỏ", "✂️ Split it"), primary: true) { [weak self] in self?.openBreakdown?(s.task) },
                BubbleAction(title: L("⏱ Thử 2'", "⏱ Try 2'")) { [weak self] in self?.startStarter(s.task) },
                BubbleAction(title: L("Bỏ khỏi kế hoạch", "Drop from plan")) { [weak self] in self?.unplan(s.task) },
            ], seconds: 60), why: L("“\(TextClean.short(s.task.title, 30))” nằm trong danh sách \(s.days) ngày",
                                    "“\(TextClean.short(s.task.title, 30))” has been on your list \(s.days) days"), kind: "stuck")
            return
        }

        // 6b. A hungry pet begs for a finished task.
        if ctx.inWork, life.state.hungry, mayRemind("hungry"), every("hungry", minutes: 60) {
            say(Bubble(text: Lines.hungry(life.state.satiety, next: day.next),
                       actions: day.next.map { [focusAction($0), laterAction()] } ?? [], seconds: 30),
                why: L("độ no còn \(Int(life.state.satiety))%", "only \(Int(life.state.satiety))% full"), kind: "hungry")
            speak(Lines.voiceHungry())
            return
        }

        // 6c. Mischief, only while you're on a distracting app or site (never after a bad day: that only makes it worse).
        // Grumbling, then a parade with the task on a sign. Never while you're typing.
        if prefs.antics, ctx.inWork, now > anticSnoozedUntil, CalmRules.secondsSinceKey() > 60, let next = day.next, let d = distraction {
            if let a = angrySince, now.timeIntervalSince(a) >= 10 * 60, mayRemind("antic"), every("antic", minutes: 20) {
                antic = AnticEvent(kind: .parade(next.title), start: now)
                say(Bubble(text: Lines.parade(next), actions: [focusAction(next), spareAction()], seconds: 25, urgent: true),
                    chime: .grumble, why: L("đã cáu \(Int(now.timeIntervalSince(a) / 60)) phút vì \(d.app), không gõ phím → diễu hành với biển",
                                            "grumpy for \(Int(now.timeIntervalSince(a) / 60)) min over \(d.app), not typing → sign parade") + reasonSuffix(),
                    antic: true, kind: "antic")
                speak(Lines.voiceAngry(next))
                return
            }
            if d.minutes >= 3, mayRemind("grumble"), every("grumble", minutes: 30) {
                antic = AnticEvent(kind: .grumble, start: now)
                say(Bubble(text: Lines.grumble(next, app: d.app), actions: [focusAction(next), spareAction()], seconds: 15), chime: .grumble,
                    why: L("ở \(d.app) \(Int(d.minutes)) phút", "on \(d.app) for \(Int(d.minutes)) min") + reasonSuffix(),
                    antic: true, kind: "grumble")
                speak(Lines.voiceGrumble())
                return
            }
        }

        // 6d. Xin vía: bring up a wish now and then (spread over the day), with a blessing and a small step.
        if ctx.inWork, prefs.wishPerDay > 0, wishShows < prefs.wishPerDay, let w = WishRules.next(wishes.wishes),
           every("wish", minutes: WishRules.spacingMinutes(workStart: prefs.workStart, workEnd: prefs.workEnd, perDay: prefs.wishPerDay)) {
            wishShows += 1
            wishes.markShown(w.id)
            say(Bubble(text: Lines.wishReminder(w), actions: wishActions(w), seconds: 45),
                why: L("nhắc vía lần \(wishShows)/\(prefs.wishPerDay) hôm nay", "wish reminder \(wishShows)/\(prefs.wishPerDay) today"))
            return
        }

        // 7. Overdue tasks.
        if ctx.inWork, !day.overdue.isEmpty, mayRemind("overdue"), every("overdue", minutes: 90) {
            var actions = [BubbleAction(title: L("Kéo vào hôm nay", "Pull into today"), primary: true) { [weak self] in self?.pullOverdueToToday() }]
            if day.overdue.contains(where: { !$0.isRecurring }) {
                actions.append(BubbleAction(title: L("🌱 Bắt đầu lại", "🌱 Fresh start")) { [weak self] in self?.freshStart() })
            }
            actions.append(BubbleAction(title: L("Xem", "Show")) { [weak self] in self?.openBoard?(false) })
            say(Bubble(text: Lines.overdue(mood: mood, count: day.overdue.count), actions: actions, seconds: 45),
                why: L("\(day.overdue.count) việc quá hạn (nhắc tối đa 90 phút/lần)", "\(day.overdue.count) overdue task(s) (at most every 90 min)"),
                kind: "overdue")
            return
        }

        // 8. Give the next task a concrete time slot (implementation intention), once a day.
        if ctx.inWork, day.planned >= target, let s = suggestions.first, s.start.timeIntervalSince(now) < 3 * 3600,
           mayRemind("timeblock"), once("timeblock-\(dayKey)") {
            say(Bubble(text: Lines.timeBlock(s), actions: [
                BubbleAction(title: L("⏰ Đặt giờ", "⏰ Set time"), primary: true) { [weak self] in self?.schedule(s) },
                laterAction(),
            ], seconds: 60), why: L("gợi ý khung giờ trống (mỗi ngày một lần)", "a free time slot (once a day)"), kind: "timeblock")
            return
        }

        // 9. Wrap up (shutdown ritual): move what's left, pick tomorrow's frog, leave a note, and rest.
        if ctx.inWork, now >= ctx.reviewTime, once("review-\(dayKey)") {
            say(Bubble(text: Lines.review(completed: day.completed.count, remaining: day.remaining), actions: [
                BubbleAction(title: L("🌙 Đóng ngày", "🌙 Wrap up"), primary: true) { [weak self] in self?.openWrapUp?(false) },
                BubbleAction(title: L("Làm tiếp", "Keep going"), neutral: true) {},
            ], seconds: 90), why: L("30 phút trước giờ tan làm, còn \(day.remaining) việc", "30 min before work ends, \(day.remaining) left"))
            return
        }

        // 9b. A sulky end-of-day report on time spent in distracting apps and sites.
        if ctx.inWork, now >= ctx.reviewTime, life.state.distractionTotal >= 10 * 60, mayRemind("distractsum"), once("distractsum-\(dayKey)") {
            say(Bubble(text: Lines.distractionSummary(life.state.distraction), seconds: 25),
                why: L("cuối ngày, xao nhãng \(Int(life.state.distractionTotal / 60)) phút", "end of day, \(Int(life.state.distractionTotal / 60)) min of distractions"),
                kind: "distractsum")
            speak(Lines.voiceSummary(minutes: Int(life.state.distractionTotal / 60)))
            return
        }

        // 10. Regular nudge with the next task.
        let minutes = Double(prefs.remindEvery)
        if ctx.inWork, let next = day.next, now.timeIntervalSince(lastBubbleAt) > minutes * 60, mayRemind("nudge"), every("nudge", minutes: minutes) {
            let idleHours = now.timeIntervalSince(lastProgress) / 3600
            say(Bubble(text: Lines.nudge(mood: mood, next: next, hoursIdle: idleHours),
                       actions: [focusAction(next), completeAction(next), laterAction()], seconds: 45),
                why: L("\(prefs.remindEvery) phút chưa nhắc; \(String(format: "%.1f", idleHours)) giờ chưa có tiến triển",
                       "\(prefs.remindEvery) min since the last reminder; no progress for \(String(format: "%.1f", idleHours))h"), kind: "nudge")
            return
        }

        // 11. A tip now and then, only when the mood is good.
        if ctx.inWork, mood == .happy || mood == .normal, now.timeIntervalSince(lastBubbleAt) > 40 * 60,
           mayRemind("tip"), every("tip", minutes: 150) {
            say(Bubble(text: Lines.tip(), seconds: 14), why: L("pet đang vui và đã im lặng 40 phút", "the pet is in a good mood and quiet for 40 min"),
                kind: "tip")
        }
    }

    /// Without setting it: has `key` not fired for `minutes` (times its back-off, for a repeating reminder kind)?
    private func isDue(_ key: String, minutes: Double) -> Bool {
        let backoff = Brain.everyKinds.contains(key) ? Double(life.state.dayBackoff[key] ?? 1) : 1
        return fired[key].map { Date().timeIntervalSince($0) >= minutes * 60 * backoff } ?? true
    }

    /// " (−30 only 1/3 planned; −10 no progress…)" — the top reasons behind the current mood.
    private func reasonSuffix() -> String {
        let r = reasons.filter { $0.delta < 0 }.prefix(2).map { "\($0.delta) \($0.text)" }.joined(separator: "; ")
        return r.isEmpty ? "" : " (\(r))"
    }

    private func planActions() -> [BubbleAction] {
        var a = [BubbleAction(title: L("＋ Thêm việc", "＋ Add tasks"), primary: true) { [weak self] in self?.openBoard?(true) }]
        let movable = day.overdue.filter { !$0.isRecurring }
        if !movable.isEmpty {
            a.append(BubbleAction(title: L("Kéo \(movable.count) việc quá hạn vào", "Pull \(movable.count) overdue in")) { [weak self] in
                self?.pullOverdueToToday()
            })
        }
        a.append(laterAction())
        return a
    }

    private func completeAction(_ t: TodoTask) -> BubbleAction {
        BubbleAction(title: L("✓ Xong rồi", "✓ Done")) { [weak self] in self?.complete(t) }
    }

    // MARK: - Actions

    /// Feeds the pet once per finished task, then dances with a random (sometimes rare golden) celebration.
    private func celebrate(_ task: TodoTask?, viaPet: Bool, feeds: Int = 1) {
        let now = Date()
        lastCelebration = now
        antic = nil
        var result: FeedResult?
        var unlocked: [Accessory] = []
        var levelUp: Stage?
        for _ in 0..<max(1, feeds) {
            let r = life.mutate { LifeRules.feed(&$0, now: now, roll: .random(in: 0..<1), pick: .random(in: 0..<1)) }
            unlocked += r.unlocked
            levelUp = r.levelUp ?? levelUp
            result = r
        }
        guard let r = result else { return }
        celebration = CelebrationEvent(kind: r.kind, food: r.food, golden: r.golden, combo: r.combo, start: now)
        var fed = L("Xong “\(TextClean.short(task?.title ?? "", 40))”\(viaPet ? "" : " (trong Todoist)") → no \(Int(life.state.satiety))%, \(life.state.xp) XP",
                    "Done “\(TextClean.short(task?.title ?? "", 40))”\(viaPet ? "" : " (in Todoist)") → \(Int(life.state.satiety))% full, \(life.state.xp) XP")
        if feeds > 1 { fed += L(" (\(feeds) việc)", " (\(feeds) tasks)") }
        if r.combo >= 2 { fed += ", combo ×\(r.combo)" }
        if r.golden { fed += L(", bánh vàng hiếm", ", rare golden treat") }
        if let levelUp { fed += L(", lớn lên thành \(levelUp.name)", ", grew up: \(levelUp.name)") }
        if !unlocked.isEmpty { fed += L(", mở khoá ", ", unlocked ") + unlocked.map(\.emoji).joined() }
        let wishDone = task.flatMap { wishes.completeStep(taskId: $0.id, at: now) }
        if let w = wishDone { fed += L(", +1 bước cho “\(w.title)” (\(w.steps))", ", +1 step towards “\(w.title)” (\(w.steps))") }
        // A finished task opens a held chest.
        let season = SeasonRules.active(on: now)?.season
        let chest = life.mutate { ChestRules.open(&$0, roll: .random(in: 0..<1), pick: .random(in: 0..<1), season: season) }
        if let chest {
            if let id = task?.id { lastChest = (id, chest) }
            fed += L(", mở rương \(chest.tier.rawValue)", ", opened a \(chest.tier.rawValue) chest")
        }
        log.add(.life, fed)
        celebrateUntil = now.addingTimeInterval(r.golden || levelUp != nil ? 5 : 4)
        recompute()
        play(r.golden || levelUp != nil ? .big : .celebrate)
        var actions: [BubbleAction] = []
        if viaPet, let task {
            actions.append(BubbleAction(title: L("Hoàn tác", "Undo")) { [weak self] in self?.undoComplete(task) })
        }
        if let task {
            var lines = [Lines.done(task, completed: day.completed.count, target: target)]
            if r.golden { lines.append(Lines.golden()) }
            if r.combo >= 2 { lines.append(Lines.combo(r.combo)) }
            if r.cleaned { lines.append(Lines.cleaned(life.state.dirt)) }
            if let levelUp { lines.append(Lines.levelUp(levelUp)) }
            if !unlocked.isEmpty { lines.append(Lines.unlocked(unlocked)) }
            if let w = wishDone { lines.append(Lines.wishStepDone(w)) }
            if let chest { lines.append(Lines.chestOpened(chest)) }
            if repairNote {
                lines.append(Lines.streakRepaired(life.state.streak))
                repairNote = false
            }
            bubble = Bubble(text: lines.joined(separator: "\n"), actions: actions,
                            seconds: unlocked.isEmpty && levelUp == nil && wishDone == nil ? 8 : 14, urgent: true)
            lastBubbleAt = now
            if levelUp != nil || r.golden { speak(Lines.voiceCheer()) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
            MainActor.assumeIsolated { self?.recompute() }
        }
    }

    func complete(_ task: TodoTask) {
        guard let service else { return }
        active.removeAll { $0.id == task.id }
        var done = task
        done.checked = true
        done.completedAt = DateParse.utcString(Date())
        completed.insert(done, at: 0)
        completedViaPet.insert(task.id)
        knownCompleted.insert(task.id)
        if focus?.task?.id == task.id, focus?.isBreak == false { focus = nil }
        celebrate(done, viaPet: true)
        Task {
            do {
                try await service.close(id: task.id)
            } catch {
                errorText = error.localizedDescription
                completed.removeAll { $0.id == task.id }
                active.append(task)
                life.mutate { LifeRules.unfeed(&$0) }
                if let c = lastChest, c.taskId == task.id {
                    life.mutate { ChestRules.undo(&$0, c.result) }
                    lastChest = nil
                }
                recompute()
                say(Bubble(text: Lines.error(error.localizedDescription), seconds: 10, urgent: true))
            }
        }
    }

    func undoComplete(_ task: TodoTask) {
        guard let service else { return }
        life.mutate { LifeRules.unfeed(&$0) }
        completed.removeAll { $0.id == task.id }
        var t = task
        t.checked = false
        t.completedAt = nil
        active.append(t)
        lastCelebration = .distantPast
        recompute()
        Task {
            try? await service.reopen(id: task.id)
            await refresh()
        }
    }

    func add(_ text: String, due: DueChoice, priority: Int) async -> Bool {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let service, !content.isEmpty else { return false }
        let plannedBefore = day.planned
        do {
            switch due {
            case .smart: try await service.quickAdd(text: content)
            case .today: try await service.addTask(content: content, dueString: "today", priority: priority, parentId: nil)
            case .tomorrow: try await service.addTask(content: content, dueString: "tomorrow", priority: priority, parentId: nil)
            case .none: try await service.addTask(content: content, dueString: nil, priority: priority, parentId: nil)
            }
        } catch {
            errorText = error.localizedDescription
            return false
        }
        lastPlanAction = Date()
        await refresh()
        let target = self.target
        if plannedBefore < target, day.planned >= target {
            lastCelebration = Date()
            recompute()
            say(Bubble(text: Lines.planComplete(target: target, next: day.next),
                       actions: day.next.map { [focusAction($0)] } ?? [], seconds: 20, urgent: true))
        } else {
            say(Bubble(text: Lines.added(content), seconds: 4, urgent: true))
        }
        return true
    }

    func reschedule(_ task: TodoTask, to dueString: String) {
        guard let service else { return }
        Task {
            do { try await service.reschedule(id: task.id, dueString: dueString) } catch { errorText = error.localizedDescription }
            await refresh()
        }
    }

    func pullOverdueToToday() {
        guard let service else { return }
        let tasks = day.overdue.filter { !$0.isRecurring }
        lastPlanAction = Date()
        Task {
            for t in tasks { try? await service.reschedule(id: t.id, dueString: "today") }
            await refresh()
        }
    }

    func moveTodayToTomorrow() {
        guard let service else { return }
        let tasks = day.today.filter { !$0.isRecurring }
        Task {
            for t in tasks { try? await service.reschedule(id: t.id, dueString: "tomorrow") }
            await refresh()
            say(Bubble(text: L("Đã dời \(tasks.count) việc sang mai. Nghỉ ngơi nhé 🌙", "Moved \(tasks.count) task(s) to tomorrow. Rest well 🌙"), seconds: 8))
        }
    }

    /// Gives a task the suggested time today, so the pet can remind you right on time.
    func schedule(_ s: SlotSuggestion) {
        guard let service else { return }
        lastPlanAction = Date()
        Task {
            do {
                try await service.reschedule(id: s.task.id, dueString: "today at " + DayMath.timeString(s.start))
            } catch {
                errorText = error.localizedDescription
                return
            }
            await refresh()
            say(Bubble(text: Lines.timeSet(s.task, at: s.start), seconds: 6, urgent: true))
        }
    }

    /// Takes a task off today's plan without deleting it (it stays in Todoist with no date).
    /// Deletes a task (and its sub-tasks) from Todoist for good. The UI asks for confirmation first.
    func delete(_ task: TodoTask) {
        guard let service else { return }
        active.removeAll { $0.id == task.id || $0.parentId == task.id }
        if focus?.task?.id == task.id, focus?.isBreak == false { focus = nil }
        lastPlanAction = Date()
        recompute()
        Task {
            do {
                try await service.delete(id: task.id)
            } catch {
                errorText = error.localizedDescription
                say(Bubble(text: Lines.error(error.localizedDescription), seconds: 10, urgent: true))
                await refresh()
                return
            }
            say(Bubble(text: Lines.deleted(task), seconds: 5, urgent: true))
            await refresh()
        }
    }

    func unplan(_ task: TodoTask) {
        guard let service else { return }
        lastPlanAction = Date()
        Task {
            do {
                try await service.reschedule(id: task.id, dueString: "no date")
            } catch {
                errorText = error.localizedDescription
                return
            }
            await refresh()
            say(Bubble(text: Lines.unplanned(task), seconds: 6, urgent: true))
        }
    }

    func suggestSteps(for task: TodoTask) async throws -> [String] {
        guard let key = Keychain.read(.anthropic) else { throw ClaudeError.noKey }
        return try await ClaudeClient(apiKey: key, model: prefs.effectiveClaudeModel).breakdown(title: task.title, notes: task.description)
    }

    /// Adds the steps as Todoist sub-tasks; the first one goes on today's plan.
    func split(_ task: TodoTask, into steps: [String], firstToday: Bool) async -> Bool {
        let clean = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let service, let firstTitle = clean.first else { return false }
        var first: TodoTask?
        do {
            for (i, step) in clean.enumerated() {
                let created = try await service.addTask(content: step, dueString: i == 0 && firstToday ? "today" : nil,
                                                        priority: task.apiPriority, parentId: task.id)
                if i == 0 { first = created }
            }
        } catch {
            errorText = error.localizedDescription
            return false
        }
        lastPlanAction = Date()
        await refresh()
        let start = first.flatMap { f in day.open.first { $0.id == f.id } }
        say(Bubble(text: Lines.splitDone(count: clean.count, first: firstTitle),
                   actions: start.map { [focusAction($0)] } ?? [], seconds: 30, urgent: true))
        return true
    }

    /// "Fresh start": every overdue task that doesn't repeat moves to tomorrow, so today starts clean.
    func freshStart() {
        guard let service else { return }
        let tasks = day.overdue.filter { !$0.isRecurring }
        let repeating = day.overdue.count - tasks.count
        lastPlanAction = Date()
        log.add(.system, L("Bắt đầu lại: dời \(tasks.count) việc quá hạn sang mai", "Fresh start: moved \(tasks.count) overdue task(s) to tomorrow"))
        Task {
            for t in tasks { try? await service.reschedule(id: t.id, dueString: "tomorrow") }
            await refresh()
            say(Bubble(text: Lines.freshStart(moved: tasks.count, repeating: repeating), seconds: 10, urgent: true))
        }
    }

    // MARK: - Where was I?

    /// Shows the "where was I?" card (the pinned spot first). Not counted against the budget; at most every 30 minutes.
    @discardableResult
    private func offerResume(why: String, reason: String) -> Bool {
        let now = Date()
        guard prefs.resumeCard, let c = pinned ?? workContext, now.timeIntervalSince(c.at) < 4 * 3600,
              now.timeIntervalSince(lastResumeAt) >= ResumeRules.cooldownMinutes * 60 else { return false }
        lastResumeAt = now
        var actions: [BubbleAction] = []
        if c.url != nil || c.bundle != nil {
            actions.append(BubbleAction(title: L("Mở lại ↗", "Reopen ↗"), primary: true) { [weak self] in self?.reopen(c) })
        }
        if let task = c.taskId.flatMap({ id in day.open.first { $0.id == id } }) {
            actions.append(BubbleAction(title: "▶︎ " + L("Tập trung", "Focus"), primary: actions.isEmpty) { [weak self] in self?.startFocus(task) })
        }
        actions.append(BubbleAction(title: L("Việc khác", "Something else"), neutral: true) { [weak self] in
            self?.pinned = nil
            self?.openBoard?(false)
        })
        say(Bubble(text: Lines.resume(c, why: why), actions: actions, seconds: 45), why: reason)
        return true
    }

    /// Brings back the page (in the same browser) or the app you were in.
    func reopen(_ c: WorkContext) {
        let ws = NSWorkspace.shared
        if let s = ResumeRules.workURL(c.url), let url = URL(string: s) {
            if let b = c.bundle, BrowserWatcher.isBrowser(b), let app = ws.urlForApplication(withBundleIdentifier: b) {
                ws.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                ws.open(url)
            }
        } else if let b = c.bundle, let app = ws.urlForApplication(withBundleIdentifier: b) {
            ws.openApplication(at: app, configuration: .init())
        }
        log.add(.system, L("Bạn mở lại chỗ đang làm", "You reopened where you were") + (ResumeRules.host(c) ?? c.app).map { " (\($0))" }.orEmpty)
    }

    /// 📌 Keeps your current spot (the last work app and page, and the task) with a one-line next step.
    func pinPlace(note: String) {
        let base = workContext ?? WorkContext(taskId: day.next?.id, taskTitle: day.next?.title, taskIsNext: true, at: Date())
        var c = base
        c.note = WrapRules.tidyNote(note)
        c.at = Date()
        pinned = c
        log.add(.system, L("Bạn ghim chỗ đang làm", "You pinned your place") + (c.note == nil ? "" : L(" kèm bước tiếp theo", " with a next step")))
    }

    func clearPin() { pinned = nil }

    // MARK: - Wrap up

    /// Applies the wrap-up: moves tasks, saves tomorrow's frog and note, and (with `done`) puts the pet to sleep
    /// until the next workday (meetings and timed tasks still get through).
    func applyWrapUp(moves: [String: WrapMove], frogId: String?, note: String, done: Bool) {
        let now = Date()
        let tomorrow = WrapRules.nextWorkday(after: now, isWorkday: prefs.isWorkday)
        let note = WrapRules.tidyNote(note)
        plans.set(DayPlan(day: DayMath.key(tomorrow), frogId: frogId, note: note))
        let toMove = moves.filter { $0.value != .keep }
        let frog = frogId.flatMap { id in day.open.first { $0.id == id } }
        if done { plans.setDone(until: WrapRules.nextWorkdayStart(after: now, workStart: prefs.workStart, isWorkday: prefs.isWorkday)) }
        log.add(.system, L("Đóng ngày: dời \(toMove.values.filter { $0 == .tomorrow }.count) việc sang mai, bỏ hạn \(toMove.values.filter { $0 == .none }.count) việc",
                           "Wrapped up: \(toMove.values.filter { $0 == .tomorrow }.count) to tomorrow, \(toMove.values.filter { $0 == .none }.count) off the plan")
                    + (frog.map { L(", ếch mai: “\(TextClean.short($0.title, 30))”", ", tomorrow's frog: “\(TextClean.short($0.title, 30))”") } ?? "")
                    + (done ? L(", xong ngày", ", done for today") : ""))
        lastPlanAction = now
        recompute()
        if done {
            bubble = Bubble(text: Lines.doneForToday(frog: frog?.title), seconds: 10, urgent: true)
            lastBubbleAt = now
        } else {
            say(Bubble(text: L("Đã lưu kế hoạch cho mai 👍", "Tomorrow's plan is saved 👍"), seconds: 5, urgent: true))
        }
        applyMoves(toMove, announce: false)
    }

    /// Moves tasks to tomorrow or off the plan (the wrap-up, or lightening an overbooked day).
    func applyMoves(_ moves: [String: WrapMove], announce: Bool = true) {
        let toMove = moves.filter { $0.value != .keep }
        guard let service, !toMove.isEmpty else { return }
        lastPlanAction = Date()
        Task {
            for (id, move) in toMove { try? await service.reschedule(id: id, dueString: move == .tomorrow ? "tomorrow" : "no date") }
            await refresh()
            if announce {
                say(Bubble(text: L("Đã dời \(toMove.count) việc, hôm nay nhẹ hơn rồi 🌿 (\(DayLoadRules.text(load.taskMinutes + load.meetingMinutes)) / \(DayLoadRules.text(load.capacity)))",
                                   "Moved \(toMove.count) task(s), today is lighter 🌿 (\(DayLoadRules.text(load.taskMinutes + load.meetingMinutes)) / \(DayLoadRules.text(load.capacity)))"),
                           seconds: 8, urgent: true))
            }
        }
    }

    /// Back from "done for today".
    func wakeUp() {
        plans.setDone(until: nil)
        log.add(.system, L("Bạn đánh thức pet", "You woke the pet up"))
        recompute()
    }

    // MARK: - If-then starts

    func triggerChoices() -> [StartTrigger] {
        TriggerRules.choices(events: events, now: Date(), recentApps: recentApps, frontBundle: recentApps.first?.bundle)
    }

    func trigger(for task: TodoTask) -> TaskTrigger? { triggers.trigger(for: task.id, day: dayKey) }

    func setTrigger(_ task: TodoTask, _ trigger: StartTrigger) {
        triggers.set(task, trigger, day: dayKey, now: Date())
        lastActedTask = task
        log.add(.system, L("Hẹn bắt đầu “\(TextClean.short(task.title, 30))” \(trigger.label)", "Planned to start “\(TextClean.short(task.title, 30))” \(trigger.label)"))
        say(Bubble(text: Lines.triggerSet(task, trigger), seconds: 5, urgent: true))
    }

    func clearTrigger(_ task: TodoTask) {
        triggers.clear(task.id, day: dayKey)
        objectWillChange.send()
    }

    /// A 2-minute "just open it" session: starting is the hard part.
    func startStarter(_ task: TodoTask) {
        startFocus(task, minutes: 2, starter: true)
    }

    // MARK: - Xin vía (wishes)

    private func wishActions(_ w: Wish) -> [BubbleAction] {
        [BubbleAction(title: L("🙏 Xin vía", "🙏 Bless it"), primary: true) { [weak self] in self?.bless(w) },
         BubbleAction(title: L("＋ Bước nhỏ", "＋ Small step")) { [weak self] in self?.openWishes?(w.id) },
         laterAction()]
    }

    /// The little ritual: the pet raises a glowing star, sends good vibes, and points at the next small step.
    func bless(_ w: Wish) {
        let now = Date()
        celebration = CelebrationEvent(kind: .blessing, food: "", golden: false, combo: 0, start: now)
        celebrateUntil = now.addingTimeInterval(3.5)
        recompute()
        play(.celebrate)
        bubble = Bubble(text: Lines.blessing(w), actions: [
            BubbleAction(title: L("＋ Bước nhỏ hôm nay", "＋ A small step today"), primary: true) { [weak self] in self?.openWishes?(w.id) },
        ], seconds: 25, urgent: true)
        lastBubbleAt = now
        log.add(.life, L("Xin vía cho “\(w.title)”", "Blessed “\(w.title)”"))
        speak(Lines.voiceBlessing())
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) { [weak self] in
            MainActor.assumeIsolated { self?.recompute() }
        }
    }

    /// Adds a small step for a wish to today's plan in Todoist, linked back to the wish.
    func addWishStep(_ w: Wish, step: String) async -> Bool {
        let text = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let service, !text.isEmpty else { return false }
        do {
            let task = try await service.addTask(content: WishRules.stepContent(text), dueString: "today", priority: 1,
                                                 parentId: nil, description: WishRules.stepDescription(w))
            if let id = task?.id { wishes.linkStep(id, to: w.id) }
        } catch {
            errorText = error.localizedDescription
            return false
        }
        lastPlanAction = Date()
        log.add(.life, L("Thêm bước nhỏ cho “\(w.title)”: \(text)", "Added a small step towards “\(w.title)”: \(text)"))
        await refresh()
        say(Bubble(text: Lines.wishStepAdded(w), seconds: 8, urgent: true))
        return true
    }

    // MARK: - Focus (Pomodoro)

    func startFocus(_ task: TodoTask?, minutes: Int? = nil, starter: Bool = false) {
        let m = minutes ?? prefs.focusMinutes
        let now = Date()
        if life.state.trip != nil { comeHome(now) }
        stitchesDropped = nil
        let t = task ?? day.next
        if let t { lastActedTask = t }
        focus = FocusSession(task: t, start: now, end: now.addingTimeInterval(Double(m) * 60), isBreak: false, minutes: m, starter: starter)
        recompute()
        bubble = Bubble(text: starter ? Lines.starterStart(t) : Lines.focusStart(t, minutes: m), seconds: 5)
        lastBubbleAt = now
        log.add(.focus, L("Bắt đầu tập trung \(m) phút", "Started a \(m)-minute focus session")
                    + (t.map { ": “\(TextClean.short($0.title, 40))”" } ?? ""))
    }

    func startBreak() {
        let now = Date()
        let m = prefs.breakMinutes
        focus = FocusSession(task: nil, start: now, end: now.addingTimeInterval(Double(m) * 60), isBreak: true, minutes: m)
        recompute()
        bubble = Bubble(text: L("Nghỉ \(m) phút nhé ☕ Uống nước, vươn vai đi!", "\(m)-minute break ☕ Water and stretch!"), seconds: 6)
        log.add(.focus, L("Nghỉ \(m) phút", "\(m)-minute break"))
    }

    func stopFocus() {
        if let f = focus {
            let minutes = Int(Date().timeIntervalSince(f.start) / 60)
            log.add(.focus, f.isBreak ? L("Bạn dừng giờ nghỉ sau \(minutes) phút", "You ended the break after \(minutes) min")
                                      : L("Bạn dừng tập trung sau \(minutes)/\(f.minutes) phút", "You stopped focusing after \(minutes)/\(f.minutes) min"))
        }
        focus = nil
        recompute()
    }

    private func finishFocus() {
        guard let f = focus else { return }
        log.add(.focus, f.isBreak ? L("Hết giờ nghỉ", "Break over") : L("Xong phiên tập trung \(f.minutes) phút", "Finished a \(f.minutes)-minute focus session"))
        focus = nil
        recompute()
        play(.important)
        if f.isBreak {
            bubble = Bubble(text: Lines.breakEnd(), actions: [focusAction(day.next), laterAction()], seconds: 60, urgent: true)
        } else if f.starter {
            bubble = Bubble(text: Lines.starterEnd(f.task), actions: [
                focusAction(f.task),
                BubbleAction(title: L("Thế là đủ 👍", "That's enough 👍"), neutral: true) {},
            ], seconds: 60, urgent: true)
        } else {
            var actions: [BubbleAction] = []
            if let t = f.task, day.open.contains(where: { $0.id == t.id }) {
                actions.append(BubbleAction(title: L("✓ Xong rồi", "✓ Done"), primary: true) { [weak self] in
                    self?.complete(t)
                    self?.startBreak()
                })
            }
            actions.append(BubbleAction(title: L("+\(f.minutes)' nữa", "+\(f.minutes)' more")) { [weak self] in
                self?.startFocus(f.task, minutes: f.minutes)
            })
            actions.append(BubbleAction(title: L("☕ Nghỉ \(prefs.breakMinutes)'", "☕ Break \(prefs.breakMinutes)'")) { [weak self] in
                self?.startBreak()
            })
            var text = Lines.focusEnd(f.task, minutes: f.minutes)
            if let c = craftNote { text += "\n" + c }
            if pendingChest { text += "\n" + Lines.chestFound(held: life.state.chests) }
            craftNote = nil
            pendingChest = false
            bubble = Bubble(text: text, actions: actions, seconds: 120, urgent: true)
        }
        lastBubbleAt = Date()
    }
}

extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
