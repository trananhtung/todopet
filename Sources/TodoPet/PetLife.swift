import Combine
import Foundation

/// Growth stages, reached with XP from finished tasks.
enum Stage: Int, CaseIterable {
    case baby, kid, teen, adult, master

    static let thresholds = [0, 100, 300, 700, 1500]

    static func of(xp: Int) -> Stage {
        Stage.allCases.last { xp >= thresholds[$0.rawValue] } ?? .baby
    }

    var name: String {
        switch self {
        case .baby: L("Em bé", "Baby")
        case .kid: L("Nhóc", "Kid")
        case .teen: L("Thiếu niên", "Teen")
        case .adult: L("Trưởng thành", "Grown-up")
        case .master: L("Cao thủ", "Master")
        }
    }

    /// Drawn size relative to the grown-up pet.
    var scale: Double { [0.8, 0.88, 0.95, 1.02, 1.08][rawValue] }
    /// Little leaves on the head of young pets.
    var sprouts: Int { [2, 1, 0, 0, 0][rawValue] }
    var nextXP: Int? { rawValue + 1 < Stage.thresholds.count ? Stage.thresholds[rawValue + 1] : nil }
}

/// Things the pet can wear: milestone ones, ones from chests, and seasonal ones.
enum Accessory: String, CaseIterable, Codable, Identifiable {
    case bow, scarf, sunglasses, tophat, crown, gradcap
    case beanie, flowercrown, partyhat, nonla, bandana, heartglasses, roundglasses, starglasses
    case maicrown, tetscarf, bunnyband, witchhat, santahat, bellcollar

    enum Slot { case head, face, neck }

    var id: String { rawValue }

    /// Regular chest finds (rare tier).
    static let chestPool: [Accessory] = [.beanie, .flowercrown, .partyhat, .nonla, .bandana, .heartglasses, .roundglasses, .starglasses]

    var slot: Slot {
        switch self {
        case .bow, .tophat, .crown, .gradcap, .beanie, .flowercrown, .partyhat, .nonla, .maicrown, .bunnyband, .witchhat, .santahat: .head
        case .sunglasses, .heartglasses, .roundglasses, .starglasses: .face
        case .scarf, .bandana, .tetscarf, .bellcollar: .neck
        }
    }

    /// Seasonal outfits only drop (from legendary chests) during their season.
    var season: Season? {
        switch self {
        case .maicrown, .tetscarf: .tet
        case .bunnyband: .trungthu
        case .witchhat: .halloween
        case .santahat, .bellcollar: .christmas
        default: nil
        }
    }

    var emoji: String {
        switch self {
        case .bow: "🎀"
        case .scarf: "🧣"
        case .sunglasses: "🕶️"
        case .tophat: "🎩"
        case .crown: "👑"
        case .gradcap: "🎓"
        case .beanie: "🧶"
        case .flowercrown: "🌸"
        case .partyhat: "🥳"
        case .nonla: "👒"
        case .bandana: "🤠"
        case .heartglasses: "😍"
        case .roundglasses: "🤓"
        case .starglasses: "🤩"
        case .maicrown: "🌼"
        case .tetscarf: "🧧"
        case .bunnyband: "🐰"
        case .witchhat: "🧙"
        case .santahat: "🎅"
        case .bellcollar: "🔔"
        }
    }

    var name: String {
        switch self {
        case .bow: L("Nơ xinh", "Bow")
        case .scarf: L("Khăn quàng", "Scarf")
        case .sunglasses: L("Kính râm ngầu", "Cool shades")
        case .tophat: L("Mũ quý ông", "Top hat")
        case .crown: L("Vương miện", "Crown")
        case .gradcap: L("Mũ tốt nghiệp", "Grad cap")
        case .beanie: L("Mũ len", "Beanie")
        case .flowercrown: L("Vòng hoa", "Flower crown")
        case .partyhat: L("Mũ tiệc", "Party hat")
        case .nonla: L("Nón lá", "Nón lá (conical hat)")
        case .bandana: L("Khăn bandana", "Bandana")
        case .heartglasses: L("Kính trái tim", "Heart glasses")
        case .roundglasses: L("Kính tròn", "Round glasses")
        case .starglasses: L("Kính ngôi sao", "Star glasses")
        case .maicrown: L("Vòng hoa mai", "Apricot blossom crown")
        case .tetscarf: L("Khăn đỏ ngày Tết", "Red Tết scarf")
        case .bunnyband: L("Băng đô thỏ ngọc", "Moon rabbit ears")
        case .witchhat: L("Mũ phù thuỷ", "Witch hat")
        case .santahat: L("Mũ ông già Noel", "Santa hat")
        case .bellcollar: L("Vòng cổ chuông", "Bell collar")
        }
    }

    var requirement: String {
        if let season { return L("Rương huyền thoại dịp \(season.name) \(season.emoji)", "Legendary chest around \(season.name) \(season.emoji)") }
        return switch self {
        case .bow: L("Xong việc đầu tiên", "Finish your first task")
        case .scarf: L("Chuỗi 3 ngày làm việc", "A 3-day streak")
        case .sunglasses: L("Combo ×3", "A ×3 combo")
        case .tophat: L("Xong 25 việc", "Finish 25 tasks")
        case .crown: L("Chuỗi 7 ngày làm việc", "A 7-day streak")
        case .gradcap: L("Lớn tới giai đoạn Trưởng thành", "Grow up to Grown-up")
        default: L("Rương quà hiếm 🎁", "Rare chest find 🎁")
        }
    }

    /// Milestone accessories unlock on their own; the others only come from chests.
    func isEarned(_ s: LifeState) -> Bool {
        switch self {
        case .bow: s.totalDone >= 1
        case .scarf: s.bestStreak >= 3
        case .sunglasses: s.bestCombo >= 3
        case .tophat: s.totalDone >= 25
        case .crown: s.bestStreak >= 7
        case .gradcap: Stage.of(xp: s.xp).rawValue >= Stage.adult.rawValue
        default: false
        }
    }
}

enum CelebrationKind: String, CaseIterable {
    case jump, spin, flip, dance, fireworks
    /// "Xin vía": a calm float holding up a glowing star (not a reward for a task).
    case blessing
}

/// What the pet does right after you finish a task.
struct CelebrationEvent: Equatable {
    let id = UUID()
    let kind: CelebrationKind
    let food: String
    let golden: Bool
    let combo: Int
    let start: Date
}

struct FeedResult {
    var food: String
    var combo: Int
    var golden: Bool
    var kind: CelebrationKind
    var unlocked: [Accessory]
    var levelUp: Stage?
    var cleaned: Bool
}

/// A broken streak that can come back: finish `LifeRules.repairTasks` tasks on a workday before `until`.
struct RepairQuest: Codable, Equatable {
    var streak: Int
    /// Last day ("yyyy-MM-dd") the quest can be done.
    var until: String
    /// Today's tasks brought the streak back (it was `from` before); final when the day closes.
    var restoredFrom: Int?
}

/// How a settled day went: `kept` (a task done on a day the app saw), `excused` (a packed calendar, nothing done),
/// `frozen` (a missed workday, a snack saved the streak), `broken` (a missed workday) or `none` (a day off, or a day
/// the app never saw).
enum DayOutcome: String {
    case kept, excused, frozen, broken, none
}

struct DayClose {
    /// The day that was settled; "" when nothing was.
    var day = ""
    var outcome = DayOutcome.none
    /// The streak a broken day ended.
    var lost = 0
    var snackEarned = false
    var sticker = false
    /// The sticker filled a page: +50 XP and a snack.
    var pageDone = false
    var repairOffered = false
    var repairExpired = false
    var unlocked: [Accessory] = []
}

/// Everything the pet remembers across days.
struct LifeState: Codable, Equatable {
    var satiety: Double = 70
    var dirt = 0
    var xp = 0
    var totalDone = 0
    /// Workdays in a row with at least one finished task (days off and days the Mac was off don't count).
    var streak = 0
    var bestStreak = 0
    /// 🍪 in the stash (0–2): one saves the streak on a missed workday.
    var snacks = 1
    var repair: RepairQuest?
    var combo = 0
    var bestCombo = 0
    var goldens = 0
    var lastDoneAt: Date?
    var lastDecayAt: Date?
    var perfectDays: [String] = []
    var unlocked: [String] = []
    var wearing: [String] = []
    // The day in progress, settled when the date changes.
    var dayKey = ""
    var dayCompleted = 0
    var dayPlanned = 0
    var dayTarget = 3
    var dayWorkday = true
    /// Todoist answered today (a day the Mac was off never counts against you).
    var daySeen = false
    /// The calendar left less than an hour free: a day with nothing done is excused.
    var dayBusy = false
    /// Seconds spent today in each distracting app or site.
    var distraction: [String: Double] = [:]
    /// Unsolicited reminders shown today (the daily budget).
    var dayNudges = 0
    /// How much each repeating reminder is stretched today after being closed or ignored (×2, ×4, ×8).
    var dayBackoff: [String: Int] = [:]
    /// Reminders closed or ignored in a row; three hold the rest for an hour.
    var dismissedInRow = 0
    var nudgeHoldUntil: Date?
    // The game: chests for work time, knitting during focus, trips, the sticker book and weekly chapters.
    var chests = 0
    var chestsToday = 0
    /// Seconds of real work towards the next chest.
    var workSec: Double = 0
    /// Knitting progress, 0…1.
    var craft: Double = 0
    var decor: [String] = []
    var craftXpToday = 0
    var craftXpDay = ""
    /// Decorations shown in the home corner (up to 3).
    var home: [String] = []
    var souvenirs: [String] = []
    var trip: TripState?
    var tripDay: String?
    var tripDeclined: String?
    var stickerPage = 1
    var pageFilled = StickerRules.pageGifts
    var week = WeekStats()
    var lastWeek: WeekStats?
    /// The week whose chapter was opened in a morning greeting.
    var chapterShown = ""

    init() {}

    /// Tolerates missing keys, so adding fields later never wipes the pet's progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LifeState()
        satiety = try c.decodeIfPresent(Double.self, forKey: .satiety) ?? d.satiety
        dirt = try c.decodeIfPresent(Int.self, forKey: .dirt) ?? d.dirt
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? d.xp
        totalDone = try c.decodeIfPresent(Int.self, forKey: .totalDone) ?? d.totalDone
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? d.streak
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? d.bestStreak
        snacks = min(LifeRules.maxSnacks, max(0, try c.decodeIfPresent(Int.self, forKey: .snacks) ?? d.snacks))
        repair = try c.decodeIfPresent(RepairQuest.self, forKey: .repair)
        combo = try c.decodeIfPresent(Int.self, forKey: .combo) ?? d.combo
        bestCombo = try c.decodeIfPresent(Int.self, forKey: .bestCombo) ?? d.bestCombo
        goldens = try c.decodeIfPresent(Int.self, forKey: .goldens) ?? d.goldens
        lastDoneAt = try c.decodeIfPresent(Date.self, forKey: .lastDoneAt)
        lastDecayAt = try c.decodeIfPresent(Date.self, forKey: .lastDecayAt)
        perfectDays = try c.decodeIfPresent([String].self, forKey: .perfectDays) ?? d.perfectDays
        unlocked = try c.decodeIfPresent([String].self, forKey: .unlocked) ?? d.unlocked
        wearing = try c.decodeIfPresent([String].self, forKey: .wearing) ?? d.wearing
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? d.dayKey
        dayCompleted = try c.decodeIfPresent(Int.self, forKey: .dayCompleted) ?? d.dayCompleted
        dayPlanned = try c.decodeIfPresent(Int.self, forKey: .dayPlanned) ?? d.dayPlanned
        dayTarget = try c.decodeIfPresent(Int.self, forKey: .dayTarget) ?? d.dayTarget
        dayWorkday = try c.decodeIfPresent(Bool.self, forKey: .dayWorkday) ?? d.dayWorkday
        daySeen = try c.decodeIfPresent(Bool.self, forKey: .daySeen) ?? d.daySeen
        dayBusy = try c.decodeIfPresent(Bool.self, forKey: .dayBusy) ?? d.dayBusy
        distraction = try c.decodeIfPresent([String: Double].self, forKey: .distraction) ?? d.distraction
        dayNudges = try c.decodeIfPresent(Int.self, forKey: .dayNudges) ?? d.dayNudges
        dayBackoff = try c.decodeIfPresent([String: Int].self, forKey: .dayBackoff) ?? d.dayBackoff
        dismissedInRow = try c.decodeIfPresent(Int.self, forKey: .dismissedInRow) ?? d.dismissedInRow
        nudgeHoldUntil = try c.decodeIfPresent(Date.self, forKey: .nudgeHoldUntil)
        chests = min(ChestRules.maxHeld, max(0, try c.decodeIfPresent(Int.self, forKey: .chests) ?? d.chests))
        chestsToday = try c.decodeIfPresent(Int.self, forKey: .chestsToday) ?? d.chestsToday
        workSec = try c.decodeIfPresent(Double.self, forKey: .workSec) ?? d.workSec
        craft = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .craft) ?? d.craft))
        decor = try c.decodeIfPresent([String].self, forKey: .decor) ?? d.decor
        craftXpToday = try c.decodeIfPresent(Int.self, forKey: .craftXpToday) ?? d.craftXpToday
        craftXpDay = try c.decodeIfPresent(String.self, forKey: .craftXpDay) ?? d.craftXpDay
        home = try c.decodeIfPresent([String].self, forKey: .home) ?? d.home
        souvenirs = try c.decodeIfPresent([String].self, forKey: .souvenirs) ?? d.souvenirs
        trip = try c.decodeIfPresent(TripState.self, forKey: .trip)
        if let t = trip, t.back < t.start || t.back > t.start.addingTimeInterval(TripRules.maxMinutes * 60) { trip = nil }
        tripDay = try c.decodeIfPresent(String.self, forKey: .tripDay)
        tripDeclined = try c.decodeIfPresent(String.self, forKey: .tripDeclined)
        // Older versions had only the list of perfect days: the book picks up where it would be.
        stickerPage = try c.decodeIfPresent(Int.self, forKey: .stickerPage) ?? 1 + perfectDays.count / (StickerRules.pageSize - StickerRules.pageGifts)
        pageFilled = try c.decodeIfPresent(Int.self, forKey: .pageFilled)
            ?? StickerRules.pageGifts + perfectDays.count % (StickerRules.pageSize - StickerRules.pageGifts)
        week = try c.decodeIfPresent(WeekStats.self, forKey: .week) ?? d.week
        lastWeek = try c.decodeIfPresent(WeekStats.self, forKey: .lastWeek)
        chapterShown = try c.decodeIfPresent(String.self, forKey: .chapterShown) ?? d.chapterShown
    }

    /// A pet with some history, for `--demo` and screenshots.
    static var demo: LifeState {
        var s = LifeState()
        s.satiety = 55
        s.xp = 320
        s.totalDone = 31
        s.streak = 4
        s.bestStreak = 4
        s.snacks = 1
        s.bestCombo = 2
        s.goldens = 1
        s.unlocked = ["bow", "scarf", "tophat"]
        s.wearing = ["scarf"]
        s.perfectDays = ["2026-10-20", "2026-10-21", "2026-10-23"]
        s.distraction = ["youtube.com": 720, "facebook.com": 300]
        s.chests = 1
        s.workSec = 1100
        s.craft = 0.4
        s.decor = ["plant", "mug", "lamp", "fishbowl"]
        s.home = ["plant", "lamp", "fishbowl"]
        s.souvenirs = ["hoian", "dalat"]
        s.unlocked += ["beanie", "witchhat"]
        s.wearing = ["scarf", "witchhat"]
        s.pageFilled = 5
        s.week = WeekStats(key: WeekRules.key(Date()), done: 7, stickers: 1, trips: 1)
        s.lastWeek = WeekStats(key: "", done: 12, stickers: 3, trips: 2)
        return s
    }

    var stage: Stage { Stage.of(xp: xp) }
    var hungry: Bool { satiety < 30 }
    var wornAccessories: [Accessory] { wearing.compactMap(Accessory.init(rawValue:)) }
    var distractionTotal: Double { distraction.values.reduce(0, +) }
}

/// Pure rules for feeding, hunger, growth and day settlement (covered by `--selftest`).
enum LifeRules {
    static let comboWindow: TimeInterval = 30 * 60
    static let foods = ["🍙", "🍡", "🐟", "🧁", "🍓", "🍪", "🥟", "🍩"]
    static let hungerPerHour = 7.0

    /// `roll` decides a rare golden treat (10%), `pick` the food and the dance.
    static func feed(_ s: inout LifeState, now: Date, roll: Double, pick: Double) -> FeedResult {
        let before = s.stage
        if let last = s.lastDoneAt, now.timeIntervalSince(last) <= comboWindow { s.combo += 1 } else { s.combo = 1 }
        s.lastDoneAt = now
        s.bestCombo = max(s.bestCombo, s.combo)
        s.totalDone += 1
        s.week.done += 1
        let golden = roll < 0.1
        if golden { s.goldens += 1 }
        s.xp += 10 + 5 * min(max(s.combo - 1, 0), 4) + (golden ? 20 : 0)
        s.satiety = min(100, s.satiety + 25)
        let cleaned = s.dirt > 0
        if cleaned { s.dirt -= 1 }
        let dances: [CelebrationKind] = [.jump, .spin, .flip, .dance]
        let i = min(Int(pick * Double(dances.count)), dances.count - 1)
        let kind: CelebrationKind = golden || s.combo >= 3 ? .fireworks : dances[i]
        let food = golden ? "🍰" : foods[min(Int(pick * Double(foods.count * 7)) % foods.count, foods.count - 1)]
        let unlocked = checkUnlocks(&s)
        return FeedResult(food: food, combo: s.combo, golden: golden, kind: kind, unlocked: unlocked,
                          levelUp: s.stage != before ? s.stage : nil, cleaned: cleaned)
    }

    /// Reverses one feed (when you undo a completion).
    static func unfeed(_ s: inout LifeState) {
        s.totalDone = max(0, s.totalDone - 1)
        s.week.done = max(0, s.week.done - 1)
        s.xp = max(0, s.xp - 10)
        s.satiety = max(0, s.satiety - 25)
        s.combo = max(0, s.combo - 1)
    }

    static func checkUnlocks(_ s: inout LifeState) -> [Accessory] {
        var new: [Accessory] = []
        for a in Accessory.allCases where !s.unlocked.contains(a.rawValue) && a.isEarned(s) {
            s.unlocked.append(a.rawValue)
            new.append(a)
            // Put it on right away if nothing else is in that slot.
            if !s.wornAccessories.contains(where: { $0.slot == a.slot }) { s.wearing.append(a.rawValue) }
        }
        return new
    }

    /// Hunger grows during work hours only (at most one hour per step, so sleep or lunch doesn't starve the pet).
    static func decay(_ s: inout LifeState, now: Date, working: Bool) {
        defer { s.lastDecayAt = now }
        guard working, let last = s.lastDecayAt, now > last else { return }
        s.satiety = max(0, s.satiety - hungerPerHour * min(now.timeIntervalSince(last), 3600) / 3600)
    }

    static let maxSnacks = 2
    /// Finished tasks that bring a broken streak back, on a workday within `repairDays` of the break.
    static let repairTasks = 2
    static let repairDays = 14
    static let maxBackoff = 8

    /// Records today as seen after a Todoist sync. A packed calendar stays packed for the day.
    static func syncDay(_ s: inout LifeState, completed: Int, planned: Int, target: Int, workday: Bool, busy: Bool = false) {
        s.dayCompleted = completed
        s.dayPlanned = planned
        s.dayTarget = target
        s.dayWorkday = workday
        s.dayBusy = s.dayBusy || busy
        s.daySeen = true
    }

    /// The repair quest today can finish: a workday no later than its last day.
    static func activeRepair(_ s: LifeState) -> RepairQuest? {
        guard let r = s.repair, s.dayWorkday, s.dayKey <= r.until else { return nil }
        return r
    }

    /// After a sync: the old streak is back while today has `repairTasks` finished tasks, and goes back if the count
    /// drops again (an Undo). `closeDay` makes it final. Returns true when the streak just came back.
    @discardableResult
    static func checkRepair(_ s: inout LifeState) -> Bool {
        guard let quest = s.repair else { return false }
        let done = activeRepair(s) != nil && s.dayCompleted >= repairTasks
        if done && quest.restoredFrom == nil {
            s.repair?.restoredFrom = s.streak
            s.streak = max(s.streak, quest.streak)
            s.bestStreak = max(s.bestStreak, s.streak)
            return true
        }
        if !done, let from = quest.restoredFrom {
            s.streak = from
            s.repair?.restoredFrom = nil
        }
        return false
    }

    static func addDistraction(_ s: inout LifeState, label: String, seconds: Double) {
        s.distraction[label, default: 0] += seconds
    }

    /// Settles the stored day once the date changed. Forgiving: on any day the app saw, one finished task keeps the
    /// streak; a goal day adds a 🍪 snack, a perfect day a sticker. A missed workday eats a snack if there is a streak
    /// to save, or breaks it (dirt, and a repair quest for streaks of 2+). Days the app never saw (Mac off), days off
    /// and packed calendar days with nothing done change nothing.
    static func closeDay(_ s: inout LifeState, today: String, isWorkday: (String) -> Bool) -> DayClose {
        var r = DayClose()
        guard !s.dayKey.isEmpty, s.dayKey < today else {
            if s.dayKey.isEmpty { s.dayKey = today }
            return r
        }
        r.day = s.dayKey
        let seen = s.daySeen
        let missed = seen && s.dayWorkday && s.dayCompleted == 0
        // The quest's day is over: with enough tasks done the old streak stays back, otherwise it goes back.
        let quest = seen ? activeRepair(s) : nil
        if let rq = s.repair {
            let base = rq.restoredFrom ?? s.streak
            if quest != nil && s.dayCompleted >= repairTasks {
                s.streak = max(base, rq.streak)
                s.repair = nil
            } else {
                s.streak = base
                s.repair?.restoredFrom = nil
            }
        }
        var broke = 0
        if seen && s.dayCompleted > 0 {
            r.outcome = .kept
            s.streak += 1
            s.bestStreak = max(s.bestStreak, s.streak)
            if s.dayTarget > 0 && s.dayCompleted >= s.dayTarget {
                r.snackEarned = addSnack(&s)
                if s.dayCompleted >= s.dayPlanned {
                    r.sticker = true
                    s.perfectDays.append(s.dayKey)
                    s.xp += 30
                    r.pageDone = StickerRules.add(&s)
                }
            }
        } else if missed && s.dayBusy {
            r.outcome = .excused
        } else if missed && s.streak > 0 && s.snacks > 0 {
            r.outcome = .frozen
            s.snacks -= 1
        } else if missed {
            r.outcome = .broken
            r.lost = s.streak
            broke = s.streak
            s.dirt = min(3, s.dirt + 1)
            s.streak = 0
        }
        // An unfinished quest ends with its day (a busy day doesn't use it up), and after its last day at the latest.
        if let rq = s.repair, (quest != nil && r.outcome != .excused) || today > rq.until {
            s.repair = nil
            r.repairExpired = true
        }
        let until = addDays(r.day, repairDays)
        if broke >= 2 && until >= today {
            s.repair = RepairQuest(streak: broke, until: until)
            r.repairOffered = true
        }
        s.dayKey = today
        s.dayCompleted = 0
        s.dayPlanned = 0
        s.dayWorkday = isWorkday(today)
        s.daySeen = false
        s.dayBusy = false
        s.combo = 0
        s.distraction = [:]
        s.dayNudges = 0
        s.dayBackoff = [:]
        s.dismissedInRow = 0
        s.nudgeHoldUntil = nil
        s.chestsToday = 0
        s.workSec = 0
        if let d = DateParse.parse(today) { WeekRules.roll(&s, today: d) }
        s.perfectDays = Array(s.perfectDays.suffix(60))
        r.unlocked = checkUnlocks(&s)
        return r
    }

    private static func addSnack(_ s: inout LifeState) -> Bool {
        guard s.snacks < maxSnacks else { return false }
        s.snacks += 1
        return true
    }

    static func addDays(_ key: String, _ n: Int) -> String {
        guard let d = DateParse.parse(key), let x = Calendar.current.date(byAdding: .day, value: n, to: d) else { return key }
        return DayMath.key(x)
    }

    static func nextDay(_ key: String) -> String {
        guard let d = DateParse.parse(key), let n = Calendar.current.date(byAdding: .day, value: 1, to: d) else { return "9999" }
        return DayMath.key(n)
    }
}

/// Holds the pet's life and saves it after every change.
final class PetLife: ObservableObject {
    @Published private(set) var state: LifeState {
        didSet { if state != oldValue { save() } }
    }
    private let defaults: UserDefaults?
    private let key = "petLife"

    /// `persist: false` keeps everything in memory (demo mode and snapshots).
    init(persist: Bool = true, initial: LifeState? = nil) {
        defaults = persist ? .standard : nil
        if let initial {
            state = initial
        } else if let data = defaults?.data(forKey: key), let s = try? JSONDecoder().decode(LifeState.self, from: data) {
            state = s
        } else {
            state = LifeState()
        }
    }

    @discardableResult
    func mutate<T>(_ change: (inout LifeState) -> T) -> T {
        var s = state
        let result = change(&s)
        state = s
        return result
    }

    /// Wears an unlocked accessory (replacing whatever is in the same slot) or takes it off.
    func toggle(_ a: Accessory) {
        guard state.unlocked.contains(a.rawValue) else { return }
        mutate { s in
            if s.wearing.contains(a.rawValue) {
                s.wearing.removeAll { $0 == a.rawValue }
            } else {
                s.wearing.removeAll { Accessory(rawValue: $0)?.slot == a.slot }
                s.wearing.append(a.rawValue)
            }
        }
    }

    /// Puts a knitted decoration in the home corner (up to 3) or takes it out.
    func toggleHome(_ d: Decor) {
        guard state.decor.contains(d.rawValue) else { return }
        mutate { s in
            if s.home.contains(d.rawValue) {
                s.home.removeAll { $0 == d.rawValue }
            } else {
                s.home.append(d.rawValue)
                if s.home.count > 3 { s.home.removeFirst() }
            }
        }
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
