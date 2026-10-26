import AppKit
import Combine

struct BubbleAction: Identifiable {
    let id = UUID()
    let title: String
    var primary = false
    let run: () -> Void
}

struct Bubble: Identifiable {
    let id = UUID()
    let text: String
    var actions: [BubbleAction] = []
    var seconds: Double = 12
    /// Bubbles with `urgent` may replace a bubble that is still on screen.
    var urgent = false
}

struct FocusSession {
    let task: TodoTask?
    let start: Date
    let end: Date
    let isBreak: Bool
    let minutes: Int
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

    /// Set by the app: open the task board (optionally focusing the "add task" field), the split view, and settings.
    var openBoard: ((_ focusAdd: Bool) -> Void)?
    var openBreakdown: ((TodoTask) -> Void)?
    var openSettings: (() -> Void)?

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
    private var lastStatsAt = Date.distantPast
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Prefs, demo: Bool) {
        self.prefs = prefs
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
        // Celebrate tasks you completed in the Todoist app since the last sync.
        let ids = Set(completed.map(\.id))
        if didLoadOnce, let fresh = completed.first(where: { !knownCompleted.contains($0.id) && !completedViaPet.contains($0.id) }) {
            recompute()
            celebrate(fresh, viaPet: false)
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
        // Time in meetings counts as work.
        if let meetingEnd = events.filter({ $0.start <= now }).map({ min($0.end, now) }).max() { p = max(p, meetingEnd) }
        return p
    }

    private var distraction: (app: String, minutes: Double)? {
        guard Date() > distractionSnoozedUntil else { return nil }
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
        day = DaySnapshot.build(active: active, completed: completed, now: now)
        let ctx = context(now)
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
        let r = MoodEngine.evaluate(i)
        score = r.score
        reasons = r.reasons
        if mood != r.mood { mood = r.mood }
    }

    static func idleSeconds() -> Double {
        if let any = CGEventType(rawValue: ~0) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        }
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    // MARK: - Talking

    func say(_ b: Bubble) {
        if let cur = bubble, !cur.actions.isEmpty, !b.urgent, b.actions.isEmpty { return }
        bubble = b
        lastBubbleAt = Date()
        if prefs.soundOn { NSSound(named: "Pop")?.play() }
    }

    private func once(_ key: String) -> Bool {
        if fired[key] != nil { return false }
        fired[key] = Date()
        return true
    }

    private func every(_ key: String, minutes: Double) -> Bool {
        if let last = fired[key], Date().timeIntervalSince(last) < minutes * 60 { return false }
        fired[key] = Date()
        return true
    }

    func quiet(minutes: Double?) {
        quietUntil = minutes.map { Date().addingTimeInterval($0 * 60) }
        if minutes != nil { bubble = nil }
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
        recompute()
        runRules(now)
    }

    private func focusAction(_ task: TodoTask?) -> BubbleAction {
        BubbleAction(title: "▶︎ " + L("Tập trung \(prefs.focusMinutes)'", "Focus \(prefs.focusMinutes)'"), primary: true) { [weak self] in
            self?.startFocus(task)
        }
    }

    private func laterAction(_ minutes: Double = 30) -> BubbleAction {
        BubbleAction(title: L("Để sau", "Later")) { [weak self] in
            self?.fired["nudge"] = Date().addingTimeInterval(minutes * 60 - Double(self?.prefs.remindEvery ?? 45) * 60)
        }
    }

    private func runRules(_ now: Date) {
        if let q = quietUntil, now < q { return }
        quietUntil = nil

        let idle = Brain.idleSeconds()
        if idle > 300 {
            if awaySince == nil { awaySince = now.addingTimeInterval(-idle) }
            return
        }

        // Meetings come first, even during a focus session; during a meeting the pet stays quiet.
        if let e = CalendarMath.next(events, after: now) {
            let mins = e.start.timeIntervalSince(now) / 60
            if mins <= Double(prefs.meetingLead), once("meeting-\(e.id)") {
                var actions: [BubbleAction] = []
                if let url = e.joinURL {
                    actions.append(BubbleAction(title: L("Vào họp ↗", "Join ↗"), primary: true) { NSWorkspace.shared.open(url) })
                }
                actions.append(BubbleAction(title: "OK") {})
                say(Bubble(text: Lines.meetingSoon(e, minutes: max(1, Int(mins.rounded(.up)))), actions: actions, seconds: 90, urgent: true))
                return
            }
        }
        if CalendarMath.current(events, at: now) != nil { return }
        if focus != nil { return }

        guard hasToken else {
            if every("token", minutes: 60) { askForToken() }
            return
        }
        let ctx = context(now)
        let target = self.target

        if let away = awaySince {
            awaySince = nil
            if now.timeIntervalSince(away) > 15 * 60, ctx.inWork, let next = day.next {
                say(Bubble(text: Lines.welcomeBack(next), actions: [focusAction(next), laterAction()], seconds: 30))
                return
            }
        }

        // 1. Tasks with an exact time: 10 minutes before, and when due.
        for t in day.open {
            guard let time = t.dueTime else { continue }
            let mins = time.timeIntervalSince(now) / 60
            if mins > 0, mins <= 10, once("soon-\(t.id)") {
                say(Bubble(text: Lines.soon(t, minutes: Int(mins.rounded(.up))),
                           actions: [focusAction(t), completeAction(t)], seconds: 40, urgent: true))
                return
            }
            if mins <= 0, mins > -5, once("now-\(t.id)") {
                say(Bubble(text: Lines.dueNow(t), actions: [focusAction(t), completeAction(t)], seconds: 60, urgent: true))
                return
            }
        }
        if bubble != nil { return }

        if ctx.night, DayMath.hour(now) >= 23, once("night-\(dayKey)") {
            say(Bubble(text: Lines.lateNight(), seconds: 10))
            return
        }

        // 2. Everything finished.
        if !day.completed.isEmpty, day.remaining == 0, day.overdue.isEmpty, once("alldone-\(dayKey)") {
            celebrateUntil = now.addingTimeInterval(4)
            recompute()
            say(Bubble(text: Lines.allDone(), actions: [
                BubbleAction(title: L("＋ Việc cho mai", "＋ Plan tomorrow")) { [weak self] in self?.openBoard?(true) },
            ], seconds: 20))
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
            say(Bubble(text: text,
                       actions: needsPlan ? planActions() : (day.next.map { [focusAction($0), laterAction()] } ?? []),
                       seconds: 60))
            return
        }

        // 4. Not planned enough: nag every 30 minutes once the planning deadline passed.
        if ctx.inWork, day.planned < target, ctx.hoursAfterPlanDeadline >= 0, every("plan", minutes: 30) {
            say(Bubble(text: Lines.plan(mood: mood, planned: day.planned, target: target), actions: planActions(), seconds: 60))
            return
        }

        // 5. Distraction apps.
        if ctx.inWork, day.open.count > 0, let d = distraction, d.minutes >= 2, every("distract", minutes: 10) {
            say(Bubble(text: Lines.distraction(mood: mood, app: d.app, left: day.open.count, next: day.next), actions: [
                focusAction(day.next),
                BubbleAction(title: L("Nghỉ xíu thôi (10')", "Just a quick break (10')")) { [weak self] in
                    self?.distractionSnoozedUntil = Date().addingTimeInterval(600)
                },
            ], seconds: 30))
            return
        }

        // 6. A task that keeps getting postponed: offer to split it (or drop it). Once per task per day.
        if ctx.inWork, let s = stuck.first(where: { fired["stuck-\($0.task.id)-\(dayKey)"] == nil }), every("stuck", minutes: 120) {
            fired["stuck-\(s.task.id)-\(dayKey)"] = now
            say(Bubble(text: Lines.stuck(s, mood: mood), actions: [
                BubbleAction(title: L("✂️ Chia nhỏ", "✂️ Split it"), primary: true) { [weak self] in self?.openBreakdown?(s.task) },
                BubbleAction(title: L("Bỏ khỏi kế hoạch", "Drop from plan")) { [weak self] in self?.unplan(s.task) },
                laterAction(),
            ], seconds: 60))
            return
        }

        // 7. Overdue tasks.
        if ctx.inWork, !day.overdue.isEmpty, every("overdue", minutes: 90) {
            say(Bubble(text: Lines.overdue(mood: mood, count: day.overdue.count), actions: [
                BubbleAction(title: L("Dời vào hôm nay", "Move to today"), primary: true) { [weak self] in self?.pullOverdueToToday() },
                BubbleAction(title: L("Xem", "Show")) { [weak self] in self?.openBoard?(false) },
            ], seconds: 45))
            return
        }

        // 8. Give the next task a concrete time slot (implementation intention), once a day.
        if ctx.inWork, day.planned >= target, let s = suggestions.first, s.start.timeIntervalSince(now) < 3 * 3600,
           once("timeblock-\(dayKey)") {
            say(Bubble(text: Lines.timeBlock(s), actions: [
                BubbleAction(title: L("⏰ Đặt giờ", "⏰ Set time"), primary: true) { [weak self] in self?.schedule(s) },
                laterAction(),
            ], seconds: 60))
            return
        }

        // 9. End-of-day review (shutdown ritual).
        if ctx.inWork, now >= ctx.reviewTime, day.remaining > 0, once("review-\(dayKey)") {
            say(Bubble(text: Lines.review(completed: day.completed.count, planned: day.planned, remaining: day.remaining), actions: [
                BubbleAction(title: L("Dời sang mai", "Move to tomorrow"), primary: true) { [weak self] in self?.moveTodayToTomorrow() },
                BubbleAction(title: L("Làm tiếp", "Keep going")) {},
            ], seconds: 90))
            return
        }

        // 10. Regular nudge with the next task.
        let minutes = Double(prefs.remindEvery)
        if ctx.inWork, let next = day.next, now.timeIntervalSince(lastBubbleAt) > minutes * 60, every("nudge", minutes: minutes) {
            let idleHours = now.timeIntervalSince(lastProgress) / 3600
            say(Bubble(text: Lines.nudge(mood: mood, next: next, hoursIdle: idleHours),
                       actions: [focusAction(next), completeAction(next), laterAction()], seconds: 45))
            return
        }

        // 11. A tip now and then, only when the mood is good.
        if ctx.inWork, mood == .happy || mood == .normal, now.timeIntervalSince(lastBubbleAt) > 40 * 60,
           every("tip", minutes: 150) {
            say(Bubble(text: Lines.tip(), seconds: 14))
        }
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

    private func celebrate(_ task: TodoTask?, viaPet: Bool) {
        let now = Date()
        lastCelebration = now
        celebrateUntil = now.addingTimeInterval(4)
        recompute()
        if prefs.soundOn { NSSound(named: "Glass")?.play() }
        var actions: [BubbleAction] = []
        if viaPet, let task {
            actions.append(BubbleAction(title: L("Hoàn tác", "Undo")) { [weak self] in self?.undoComplete(task) })
        }
        if let task {
            bubble = Bubble(text: Lines.done(task, completed: day.completed.count, target: target),
                            actions: actions, seconds: 8, urgent: true)
            lastBubbleAt = now
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
                recompute()
                say(Bubble(text: Lines.error(error.localizedDescription), seconds: 10, urgent: true))
            }
        }
    }

    func undoComplete(_ task: TodoTask) {
        guard let service else { return }
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

    // MARK: - Focus (Pomodoro)

    func startFocus(_ task: TodoTask?, minutes: Int? = nil) {
        let m = minutes ?? prefs.focusMinutes
        let now = Date()
        let t = task ?? day.next
        focus = FocusSession(task: t, start: now, end: now.addingTimeInterval(Double(m) * 60), isBreak: false, minutes: m)
        recompute()
        bubble = Bubble(text: Lines.focusStart(t, minutes: m), seconds: 5)
        lastBubbleAt = now
    }

    func startBreak() {
        let now = Date()
        let m = prefs.breakMinutes
        focus = FocusSession(task: nil, start: now, end: now.addingTimeInterval(Double(m) * 60), isBreak: true, minutes: m)
        recompute()
        bubble = Bubble(text: L("Nghỉ \(m) phút nhé ☕ Uống nước, vươn vai đi!", "\(m)-minute break ☕ Water and stretch!"), seconds: 6)
    }

    func stopFocus() {
        focus = nil
        recompute()
    }

    private func finishFocus() {
        guard let f = focus else { return }
        focus = nil
        recompute()
        if prefs.soundOn { NSSound(named: "Hero")?.play() }
        if f.isBreak {
            bubble = Bubble(text: Lines.breakEnd(), actions: [focusAction(day.next), laterAction()], seconds: 60, urgent: true)
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
            bubble = Bubble(text: Lines.focusEnd(f.task, minutes: f.minutes), actions: actions, seconds: 120, urgent: true)
        }
        lastBubbleAt = Date()
    }
}
