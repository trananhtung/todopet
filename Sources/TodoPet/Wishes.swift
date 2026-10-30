import Combine
import Foundation

/// Something you want to achieve ("xin vía"). Structured like WOOP (Oettingen): the wish, the outcome you
/// picture, the main obstacle, and an if-then plan. Picturing the goal *and* the obstacle, then planning,
/// works better than positive thinking alone, so every reminder also asks for one small step.
struct Wish: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var why = ""
    var obstacle = ""
    var plan = ""
    var emoji = "🌟"
    var created = Date()
    /// Finished Todoist tasks that were created as steps for this wish.
    var steps = 0
    var stepTaskIds: [String] = []
    var lastStepAt: Date?
    var lastShown: Date?

    init(title: String, why: String = "", obstacle: String = "", plan: String = "", emoji: String = "🌟") {
        self.title = title
        self.why = why
        self.obstacle = obstacle
        self.plan = plan
        self.emoji = emoji
    }

    /// Tolerates missing keys, so adding fields later never loses your wishes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        obstacle = try c.decodeIfPresent(String.self, forKey: .obstacle) ?? ""
        plan = try c.decodeIfPresent(String.self, forKey: .plan) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🌟"
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        stepTaskIds = try c.decodeIfPresent([String].self, forKey: .stepTaskIds) ?? []
        lastStepAt = try c.decodeIfPresent(Date.self, forKey: .lastStepAt)
        lastShown = try c.decodeIfPresent(Date.self, forKey: .lastShown)
    }

    static let emojis = ["🌟", "🎯", "💪", "📚", "💰", "🏃", "❤️", "✈️", "🏠", "🎓", "🧘", "🚀"]
}

/// Pure rules for the wish reminders (covered by `--selftest`).
enum WishRules {
    /// The wish to bring up next: the one shown least recently (never-shown first, then oldest).
    static func next(_ wishes: [Wish]) -> Wish? {
        wishes.filter { !$0.title.isEmpty }.min { a, b in
            switch (a.lastShown, b.lastShown) {
            case (nil, nil): a.created < b.created
            case (nil, _): true
            case (_, nil): false
            case let (x?, y?): x < y
            }
        }
    }

    /// Spreads `perDay` reminders across the working day.
    static func spacingMinutes(workStart: Int, workEnd: Int, perDay: Int) -> Double {
        max(60, Double(max(1, workEnd - workStart)) * 60 / Double(max(1, perDay) + 1))
    }

    /// The Todoist task created for a small step: marked with ✨ and linked back in its description.
    static func stepContent(_ step: String) -> String { "✨ " + step.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func stepDescription(_ wish: Wish) -> String { L("Bước nhỏ cho điều ước: ", "A small step towards: ") + wish.title }
}

/// Your wishes, kept on this Mac (UserDefaults).
final class WishStore: ObservableObject {
    @Published private(set) var wishes: [Wish] {
        didSet { if wishes != oldValue { save() } }
    }
    private let defaults: UserDefaults?
    private let key = "wishes"

    /// `persist: false` keeps them in memory (demo mode, snapshots, tests).
    init(persist: Bool = true, initial: [Wish]? = nil) {
        defaults = persist ? .standard : nil
        if let initial {
            wishes = initial
        } else if let data = defaults?.data(forKey: key), let w = try? JSONDecoder().decode([Wish].self, from: data) {
            wishes = w
        } else {
            wishes = []
        }
    }

    static var demo: [Wish] {
        [Wish(title: L("Nói tiếng Anh trôi chảy", "Speak fluent English"), why: L("Tự tin đi phỏng vấn công ty nước ngoài", "Interview with confidence abroad"),
              obstacle: L("Ngại nói, hay để mai", "Shy, keep putting it off"), plan: L("Nếu ăn trưa xong thì nói tiếng Anh 10 phút với app", "If lunch is over, then speak English for 10 minutes with an app"),
              emoji: "📚"),
         Wish(title: L("Chạy được 10 km", "Run 10 km"), why: L("Khoẻ và nhiều năng lượng hơn", "Feel fit and energetic"), emoji: "🏃")]
    }

    func add(_ w: Wish) { wishes.append(w) }

    func update(_ w: Wish) {
        guard let i = wishes.firstIndex(where: { $0.id == w.id }) else { return }
        wishes[i] = w
    }

    func remove(_ id: UUID) { wishes.removeAll { $0.id == id } }

    func markShown(_ id: UUID, at now: Date = Date()) {
        guard let i = wishes.firstIndex(where: { $0.id == id }) else { return }
        wishes[i].lastShown = now
    }

    func linkStep(_ taskId: String, to id: UUID) {
        guard let i = wishes.firstIndex(where: { $0.id == id }) else { return }
        wishes[i].stepTaskIds = Array((wishes[i].stepTaskIds + [taskId]).suffix(200))
    }

    /// A finished Todoist task: if it was a step for a wish, count it. Returns that wish.
    @discardableResult
    func completeStep(taskId: String, at now: Date = Date()) -> Wish? {
        guard let i = wishes.firstIndex(where: { $0.stepTaskIds.contains(taskId) }) else { return nil }
        wishes[i].steps += 1
        wishes[i].lastStepAt = now
        wishes[i].stepTaskIds.removeAll { $0 == taskId }
        return wishes[i]
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(wishes) else { return }
        defaults.set(data, forKey: key)
    }
}
