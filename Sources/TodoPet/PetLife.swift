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

/// Things the pet can wear, unlocked by milestones.
enum Accessory: String, CaseIterable, Codable, Identifiable {
    case bow, scarf, sunglasses, tophat, crown, gradcap

    enum Slot { case head, face, neck }

    var id: String { rawValue }

    var slot: Slot {
        switch self {
        case .bow, .tophat, .crown, .gradcap: .head
        case .sunglasses: .face
        case .scarf: .neck
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
        }
    }

    var requirement: String {
        switch self {
        case .bow: L("Xong việc đầu tiên", "Finish your first task")
        case .scarf: L("Chuỗi 3 ngày đạt mục tiêu", "A 3-day streak")
        case .sunglasses: L("Combo ×3", "A ×3 combo")
        case .tophat: L("Xong 25 việc", "Finish 25 tasks")
        case .crown: L("Chuỗi 7 ngày đạt mục tiêu", "A 7-day streak")
        case .gradcap: L("Lớn tới giai đoạn Trưởng thành", "Grow up to Grown-up")
        }
    }

    func isEarned(_ s: LifeState) -> Bool {
        switch self {
        case .bow: s.totalDone >= 1
        case .scarf: s.bestStreak >= 3
        case .sunglasses: s.bestCombo >= 3
        case .tophat: s.totalDone >= 25
        case .crown: s.bestStreak >= 7
        case .gradcap: Stage.of(xp: s.xp).rawValue >= Stage.adult.rawValue
        }
    }
}

enum CelebrationKind: String, CaseIterable {
    case jump, spin, flip, dance, fireworks
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

/// Everything the pet remembers across days.
struct LifeState: Codable, Equatable {
    var satiety: Double = 70
    var dirt = 0
    var xp = 0
    var totalDone = 0
    var streak = 0
    var bestStreak = 0
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
    /// Seconds spent today in each distracting app or site.
    var distraction: [String: Double] = [:]

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
        distraction = try c.decodeIfPresent([String: Double].self, forKey: .distraction) ?? d.distraction
    }

    /// A pet with some history, for `--demo` and screenshots.
    static var demo: LifeState {
        var s = LifeState()
        s.satiety = 55
        s.xp = 320
        s.totalDone = 31
        s.streak = 4
        s.bestStreak = 4
        s.bestCombo = 2
        s.goldens = 1
        s.unlocked = ["bow", "scarf", "tophat"]
        s.wearing = ["scarf"]
        s.perfectDays = ["2026-10-20", "2026-10-21", "2026-10-23"]
        s.distraction = ["youtube.com": 720, "facebook.com": 300]
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

    static func syncDay(_ s: inout LifeState, completed: Int, planned: Int, target: Int, workday: Bool) {
        s.dayCompleted = completed
        s.dayPlanned = planned
        s.dayTarget = target
        s.dayWorkday = workday
    }

    static func addDistraction(_ s: inout LifeState, label: String, seconds: Double) {
        s.distraction[label, default: 0] += seconds
    }

    /// Settles the stored day once the date changed: streak, perfect-day sticker, and dirt for lazy workdays.
    /// Workdays the app never saw (Mac off) count as lazy too.
    static func closeDay(_ s: inout LifeState, today: String, isWorkday: (String) -> Bool) -> [Accessory] {
        guard !s.dayKey.isEmpty, s.dayKey < today else {
            if s.dayKey.isEmpty { s.dayKey = today }
            return []
        }
        if s.dayWorkday {
            if s.dayTarget > 0 && s.dayCompleted >= s.dayTarget {
                s.streak += 1
                s.bestStreak = max(s.bestStreak, s.streak)
                if s.dayCompleted >= s.dayPlanned {
                    s.perfectDays.append(s.dayKey)
                    s.xp += 30
                }
            } else {
                s.streak = 0
                if s.dayCompleted == 0 { s.dirt = min(3, s.dirt + 1) }
            }
        }
        var day = nextDay(s.dayKey)
        var guardCount = 0
        while day < today && guardCount < 30 {
            if isWorkday(day) {
                s.streak = 0
                s.dirt = min(3, s.dirt + 1)
            }
            day = nextDay(day)
            guardCount += 1
        }
        s.dayKey = today
        s.dayCompleted = 0
        s.dayPlanned = 0
        s.combo = 0
        s.distraction = [:]
        s.perfectDays = Array(s.perfectDays.suffix(60))
        return checkUnlocks(&s)
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

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
