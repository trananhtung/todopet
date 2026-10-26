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
    /// An unsolicited reminder (not a reply to something you did); your response goes into the diary.
    var reminder = false
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
    private var anticSnoozedUntil = Date.distantPast
    private var annoyedSince: Date?
    private var angrySince: Date?
    private var engagedSince: Date?
    private var flowStartedAt = Date()
    private var distractionSession: (label: String, start: Date, logged: Bool)?
    private var lastFlowEnd = Date.distantPast
    private var lastAppSwitch = Date.distantPast

    /// The pet should keep still: you're typing, in the zone, or in a meeting.
    var calmMotion: Bool {
        prefs.stillWhileTyping && (flow || CalmRules.secondsSinceKey() < 20 || CalendarMath.current(events, at: Date()) != nil)
    }
    private var lastStatsAt = Date.distantPast
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Prefs, demo: Bool) {
        self.prefs = prefs
        life = demo ? PetLife(persist: false, initial: .demo) : PetLife()
        log = PetLog(folder: demo ? nil : PetLog.defaultFolder)
        log.enabled = prefs.keepLog
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
        settleLife(now)
        if hasToken && didLoadOnce {
            let s = life.state, done = day.completed.count, planned = day.planned, goal = target, workday = ctx.workday
            if s.dayCompleted != done || s.dayPlanned != planned || s.dayTarget != goal || s.dayWorkday != workday {
                life.mutate { LifeRules.syncDay(&$0, completed: done, planned: planned, target: goal, workday: workday) }
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
        if mood == .annoyed || mood == .angry { annoyedSince = annoyedSince ?? now } else { annoyedSince = nil }
    }

    /// Settles a finished day (streak, perfect-day sticker, dirt) once the date has changed, even after a restart.
    private func settleLife(_ now: Date) {
        let today = DayMath.key(now)
        guard life.state.dayKey != today else { return }
        let before = life.state
        let unlocked = life.mutate { s in
            LifeRules.closeDay(&s, today: today) { [prefs] key in DateParse.parse(key).map(prefs.isWorkday) ?? false }
        }
        let after = life.state
        if !before.dayKey.isEmpty {
            var text = L("Chốt ngày \(before.dayKey): xong \(before.dayCompleted)/\(before.dayTarget) → chuỗi \(after.streak) ngày",
                         "Closed \(before.dayKey): \(before.dayCompleted)/\(before.dayTarget) done → \(after.streak)-day streak")
            if after.perfectDays.count > before.perfectDays.count { text += L(", nhận sticker 🌟", ", earned a 🌟 sticker") }
            if after.dirt > before.dirt { text += L(", bẩn thêm \(after.dirt - before.dirt) lớp", ", \(after.dirt - before.dirt) more layer(s) of dirt") }
            log.add(.life, text)
        }
        if !unlocked.isEmpty {
            say(Bubble(text: Lines.unlocked(unlocked), seconds: 12, urgent: true))
        }
    }

    private func speak(_ text: String) {
        if prefs.voiceOn { Voice.shared.say(text) }
    }

    func endAntic() {
        antic = nil
    }

    private func spareAction() -> BubbleAction {
        BubbleAction(title: L("Tha cho tôi 15'", "Spare me 15'")) { [weak self] in
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
    /// without it the bubble is a reply to something you did.
    func say(_ b: Bubble, chime: Chime = .chatter, why: String? = nil, antic: Bool = false) {
        if let cur = bubble, !cur.actions.isEmpty, !b.urgent, b.actions.isEmpty { return }
        var b = b
        b.reminder = why != nil
        bubble = b
        lastBubbleAt = Date()
        play(chime)
        let quote = "“" + TextClean.short(b.text.replacingOccurrences(of: "\n", with: " "), 90) + "”"
        if let why {
            log.add(antic ? .antic : .bubble, quote + " — " + L("vì ", "because ") + why)
        } else {
            log.add(.system, L("Pet nói ", "Pet said ") + quote)
        }
    }

    /// What you did with the last bubble: tapped a button, closed it, or let it fade away.
    enum BubbleResponse {
        case picked(String), closed, ignored
    }

    func noteResponse(_ r: BubbleResponse) {
        switch r {
        case .picked(let title): log.add(.response, L("Bạn bấm “\(title)”", "You tapped “\(title)”"), tag: "picked")
        case .closed: log.add(.response, L("Bạn đóng bong bóng", "You closed the bubble"), tag: "closed")
        case .ignored: log.add(.response, L("Bạn không phản hồi (tự ẩn)", "No response (faded away)"), tag: "ignored")
        }
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
        if let last = fired[key], Date().timeIntervalSince(last) < minutes * 60 { return false }
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
        updateFlow(now)
        recompute()
        runRules(now)
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
        BubbleAction(title: L("Để sau", "Later")) { [weak self] in
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
                var actions: [BubbleAction] = []
                if let url = e.joinURL {
                    actions.append(BubbleAction(title: L("Vào họp ↗", "Join ↗"), primary: true) { NSWorkspace.shared.open(url) })
                }
                actions.append(BubbleAction(title: "OK") {})
                say(Bubble(text: Lines.meetingSoon(e, minutes: max(1, Int(mins.rounded(.up)))), actions: actions, seconds: 90, urgent: true),
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
            if minutes > 15, ctx.inWork, let next = day.next {
                say(Bubble(text: Lines.welcomeBack(next), actions: [focusAction(next), laterAction()], seconds: 30),
                    why: L("bạn vừa quay lại sau \(minutes) phút", "you just came back after \(minutes) minutes"))
                return
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

        // Distraction apps and sites come first: there's no concentration to protect right then.
        // Grumpy and stuck on one for 5+ minutes: the pet jumps in the way.
        if prefs.antics, ctx.inWork, mood == .angry, now > anticSnoozedUntil, day.open.count > 0, let d = distraction,
           d.minutes >= 5, every("antic", minutes: 20) {
            antic = AnticEvent(kind: .block, start: now)
            say(Bubble(text: Lines.block(app: d.app, next: day.next), actions: [focusAction(day.next), spareAction()],
                       seconds: 25, urgent: true), chime: .grumble,
                why: L("đang cáu và ở \(d.app) \(Int(d.minutes)) phút → nhảy lên chắn màn hình",
                       "grumpy and on \(d.app) for \(Int(d.minutes)) min → jumped in the way"), antic: true)
            speak(Lines.voiceBlock(app: d.app))
            return
        }
        if ctx.inWork, day.open.count > 0, let d = distraction, d.minutes >= 2, every("distract", minutes: 10) {
            say(Bubble(text: Lines.distraction(mood: mood, app: d.app, left: day.open.count, next: day.next), actions: [
                focusAction(day.next),
                BubbleAction(title: L("Nghỉ xíu thôi (10')", "Just a quick break (10')")) { [weak self] in
                    self?.distractionSnoozedUntil = Date().addingTimeInterval(600)
                },
            ], seconds: 30), why: L("ở \(d.app) \(Int(d.minutes)) phút trong giờ làm", "on \(d.app) for \(Int(d.minutes)) min during work hours"))
            return
        }

        if ctx.night, DayMath.hour(now) >= 23, once("night-\(dayKey)") {
            say(Bubble(text: Lines.lateNight(), seconds: 10), why: L("đã quá 23 giờ mà bạn vẫn dùng máy", "past 11pm and you're still at it"))
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
            if life.state.streak > 0 { text += "\n" + Lines.streak(life.state.streak) }
            say(Bubble(text: text,
                       actions: needsPlan ? planActions() : (day.next.map { [focusAction($0), laterAction()] } ?? []),
                       seconds: 60),
                why: L("lời chào đầu ngày làm việc", "first greeting of the workday")
                    + (needsPlan ? L(", mới có \(day.planned)/\(target) việc", ", only \(day.planned)/\(target) planned") : ""))
            return
        }

        // 4. Not planned enough: nag every 30 minutes once the planning deadline passed.
        if ctx.inWork, day.planned < target, ctx.hoursAfterPlanDeadline >= 0, every("plan", minutes: 30) {
            say(Bubble(text: Lines.plan(mood: mood, planned: day.planned, target: target), actions: planActions(), seconds: 60),
                why: L("đã qua \(prefs.planDeadline)h mà mới có \(day.planned)/\(target) việc", "past \(prefs.planDeadline):00 with only \(day.planned)/\(target) planned"))
            return
        }

        // 6. A task that keeps getting postponed: offer to split it (or drop it). Once per task per day.
        if ctx.inWork, let s = stuck.first(where: { fired["stuck-\($0.task.id)-\(dayKey)"] == nil }), every("stuck", minutes: 120) {
            fired["stuck-\(s.task.id)-\(dayKey)"] = now
            say(Bubble(text: Lines.stuck(s, mood: mood), actions: [
                BubbleAction(title: L("✂️ Chia nhỏ", "✂️ Split it"), primary: true) { [weak self] in self?.openBreakdown?(s.task) },
                BubbleAction(title: L("Bỏ khỏi kế hoạch", "Drop from plan")) { [weak self] in self?.unplan(s.task) },
                laterAction(),
            ], seconds: 60), why: L("“\(TextClean.short(s.task.title, 30))” nằm trong danh sách \(s.days) ngày",
                                    "“\(TextClean.short(s.task.title, 30))” has been on your list \(s.days) days"))
            return
        }

        // 6b. A hungry pet begs for a finished task.
        if ctx.inWork, life.state.hungry, every("hungry", minutes: 60) {
            say(Bubble(text: Lines.hungry(life.state.satiety, next: day.next),
                       actions: day.next.map { [focusAction($0), laterAction()] } ?? [], seconds: 30),
                why: L("độ no còn \(Int(life.state.satiety))%", "only \(Int(life.state.satiety))% full"))
            speak(Lines.voiceHungry())
            return
        }

        // 6c. Mischief that escalates while you slack: grumbling, then a parade with the task on a sign.
        // Never while you're typing (that's work, even if no task got ticked off yet).
        if prefs.antics, ctx.inWork, now > anticSnoozedUntil, CalmRules.secondsSinceKey() > 60, let next = day.next {
            if let a = angrySince, now.timeIntervalSince(a) >= 10 * 60, every("antic", minutes: 20) {
                antic = AnticEvent(kind: .parade(next.title), start: now)
                say(Bubble(text: Lines.parade(next), actions: [focusAction(next), spareAction()], seconds: 25, urgent: true),
                    chime: .grumble, why: L("đã cáu \(Int(now.timeIntervalSince(a) / 60)) phút, không gõ phím → diễu hành với biển",
                                            "grumpy for \(Int(now.timeIntervalSince(a) / 60)) min, not typing → sign parade") + reasonSuffix(),
                    antic: true)
                speak(Lines.voiceAngry(next))
                return
            }
            if let a = annoyedSince, now.timeIntervalSince(a) >= 10 * 60, every("grumble", minutes: 30) {
                antic = AnticEvent(kind: .grumble, start: now)
                say(Bubble(text: Lines.grumble(next), actions: [focusAction(next), spareAction()], seconds: 15), chime: .grumble,
                    why: L("đã nhăn nhó \(Int(now.timeIntervalSince(a) / 60)) phút", "annoyed for \(Int(now.timeIntervalSince(a) / 60)) min")
                        + reasonSuffix(), antic: true)
                speak(Lines.voiceGrumble())
                return
            }
        }

        // 7. Overdue tasks.
        if ctx.inWork, !day.overdue.isEmpty, every("overdue", minutes: 90) {
            say(Bubble(text: Lines.overdue(mood: mood, count: day.overdue.count), actions: [
                BubbleAction(title: L("Dời vào hôm nay", "Move to today"), primary: true) { [weak self] in self?.pullOverdueToToday() },
                BubbleAction(title: L("Xem", "Show")) { [weak self] in self?.openBoard?(false) },
            ], seconds: 45), why: L("\(day.overdue.count) việc quá hạn (nhắc tối đa 90 phút/lần)", "\(day.overdue.count) overdue task(s) (at most every 90 min)"))
            return
        }

        // 8. Give the next task a concrete time slot (implementation intention), once a day.
        if ctx.inWork, day.planned >= target, let s = suggestions.first, s.start.timeIntervalSince(now) < 3 * 3600,
           once("timeblock-\(dayKey)") {
            say(Bubble(text: Lines.timeBlock(s), actions: [
                BubbleAction(title: L("⏰ Đặt giờ", "⏰ Set time"), primary: true) { [weak self] in self?.schedule(s) },
                laterAction(),
            ], seconds: 60), why: L("gợi ý khung giờ trống (mỗi ngày một lần)", "a free time slot (once a day)"))
            return
        }

        // 9. End-of-day review (shutdown ritual).
        if ctx.inWork, now >= ctx.reviewTime, day.remaining > 0, once("review-\(dayKey)") {
            say(Bubble(text: Lines.review(completed: day.completed.count, planned: day.planned, remaining: day.remaining), actions: [
                BubbleAction(title: L("Dời sang mai", "Move to tomorrow"), primary: true) { [weak self] in self?.moveTodayToTomorrow() },
                BubbleAction(title: L("Làm tiếp", "Keep going")) {},
            ], seconds: 90), why: L("30 phút trước giờ tan làm, còn \(day.remaining) việc", "30 min before work ends, \(day.remaining) left"))
            return
        }

        // 9b. A sulky end-of-day report on time spent in distracting apps and sites.
        if ctx.inWork, now >= ctx.reviewTime, life.state.distractionTotal >= 10 * 60, once("distractsum-\(dayKey)") {
            say(Bubble(text: Lines.distractionSummary(life.state.distraction), seconds: 25),
                why: L("cuối ngày, xao nhãng \(Int(life.state.distractionTotal / 60)) phút", "end of day, \(Int(life.state.distractionTotal / 60)) min of distractions"))
            speak(Lines.voiceSummary(minutes: Int(life.state.distractionTotal / 60)))
            return
        }

        // 10. Regular nudge with the next task.
        let minutes = Double(prefs.remindEvery)
        if ctx.inWork, let next = day.next, now.timeIntervalSince(lastBubbleAt) > minutes * 60, every("nudge", minutes: minutes) {
            let idleHours = now.timeIntervalSince(lastProgress) / 3600
            say(Bubble(text: Lines.nudge(mood: mood, next: next, hoursIdle: idleHours),
                       actions: [focusAction(next), completeAction(next), laterAction()], seconds: 45),
                why: L("\(prefs.remindEvery) phút chưa nhắc; \(String(format: "%.1f", idleHours)) giờ chưa có tiến triển",
                       "\(prefs.remindEvery) min since the last reminder; no progress for \(String(format: "%.1f", idleHours))h"))
            return
        }

        // 11. A tip now and then, only when the mood is good.
        if ctx.inWork, mood == .happy || mood == .normal, now.timeIntervalSince(lastBubbleAt) > 40 * 60,
           every("tip", minutes: 150) {
            say(Bubble(text: Lines.tip(), seconds: 14), why: L("pet đang vui và đã im lặng 40 phút", "the pet is in a good mood and quiet for 40 min"))
        }
    }

    /// Without setting it: has `key` not fired for `minutes`?
    private func isDue(_ key: String, minutes: Double) -> Bool {
        fired[key].map { Date().timeIntervalSince($0) >= minutes * 60 } ?? true
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
            bubble = Bubble(text: lines.joined(separator: "\n"), actions: actions, seconds: unlocked.isEmpty && levelUp == nil ? 8 : 14,
                            urgent: true)
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

    // MARK: - Focus (Pomodoro)

    func startFocus(_ task: TodoTask?, minutes: Int? = nil) {
        let m = minutes ?? prefs.focusMinutes
        let now = Date()
        let t = task ?? day.next
        focus = FocusSession(task: t, start: now, end: now.addingTimeInterval(Double(m) * 60), isBreak: false, minutes: m)
        recompute()
        bubble = Bubble(text: Lines.focusStart(t, minutes: m), seconds: 5)
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
