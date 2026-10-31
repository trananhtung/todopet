import Foundation

/// How hard the Claude coach pushes.
enum CoachTone: String, CaseIterable, Identifiable {
    case gentle, blunt, harsh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gentle: L("Nhẹ nhàng", "Gentle")
        case .blunt: L("Thẳng thắn", "Blunt")
        case .harsh: L("Gắt 🔥", "Harsh 🔥")
        }
    }

    /// What the tone means, in the instructions Claude gets.
    var guide: String {
        switch self {
        case .gentle:
            "Warm and encouraging, like a kind friend. Make starting feel easy. At most one emoji."
        case .blunt:
            "Direct and honest, no sugar-coating and no filler. Name the task and what to do next, right now."
        case .harsh:
            """
            A ruthless drill-sergeant coach who refuses to let them slack. Short, sharp and impatient, with sarcasm and \
            exclamation marks. Call out the procrastination and the excuses head-on, count the wasted minutes, and demand \
            one concrete action right now. Get sharper with each reminder they ignored. Attack the slacking, never the \
            person: no insults about their worth, intelligence, looks, family or health, no profanity, no threats.
            """
        }
    }
}

/// The models offered in Settings (any other model id can be typed in).
enum CoachModel {
    static let presets: [(id: String, label: String)] = [
        ("claude-opus-5-5", L("Claude Opus 5.5: hay nhất (≈ $0.01/lời nhắc)", "Claude Opus 5.5: best (≈ $0.01 per reminder)")),
        ("claude-sonnet-5-5", L("Claude Sonnet 5.5: cân bằng (≈ $0.005/lời nhắc)", "Claude Sonnet 5.5: balanced (≈ $0.005 per reminder)")),
        ("claude-haiku-5-5", L("Claude Haiku 5.5: nhanh, rẻ nhất (≈ $0.0003/lời nhắc)", "Claude Haiku 5.5: fast, cheapest (≈ $0.0003 per reminder)")),
    ]
}

/// What the coach knows when it writes a reminder. Task titles and site names go to the Claude API.
struct CoachContext: Equatable {
    /// The reminder's rule ("nudge", "plan", "distract"…).
    var kind: String
    var petName: String
    var persona: String
    var mood: String
    var nextTask: String?
    var done = 0
    var planned = 0
    var target = 3
    var overdue = 0
    var minutesWithoutProgress = 0
    var distraction: String?
    var distractionMinutes = 0
    var stuckDays = 0
    /// Reminders closed or ignored in a row, and shown today.
    var ignoredInRow = 0
    var remindersToday = 0
    var time = ""
    /// The pet's own line for this moment: what the reminder has to get across.
    var fallback: String
    /// The coach's last lines, so it doesn't repeat itself.
    var recent: [String] = []

    /// 0 (first reminder) … 3 (ignored again and again, hours without progress).
    var escalation: Int {
        min(3, ignoredInRow + (minutesWithoutProgress >= 120 ? 1 : 0) + (distractionMinutes >= 10 ? 1 : 0))
    }
}

enum CoachPrompt {
    static let maxChars = 170

    static let schema: [String: Any] = [
        "type": "object",
        "properties": ["text": ["type": "string"]],
        "required": ["text"],
        "additionalProperties": false,
    ]

    /// The same for every reminder of a tone and language.
    static func system(tone: CoachTone, lang: Lang) -> String {
        """
        You write the speech bubbles of a tiny desktop pet that sits on the user's screen and pushes them to get \
        their Todoist tasks done. Each request describes one moment; reply with one bubble.

        Tone: \(tone.guide)

        Rules:
        - Write in \(lang == .vi ? "Vietnamese, casual (mình/bạn), the way a Vietnamese friend talks" : "English").
        - At most \(maxChars) characters, one or two sentences, speaking as the pet in the first person.
        - Use the concrete facts you're given (the task's name, the minutes, the site) and end with one action they \
        can take right now.
        - Get across what the pet's own line says, in your own words; don't copy it.
        - Never repeat or closely rephrase one of the recent lines.
        - No hashtags, no quotes around the whole bubble, no stage directions.
        """
    }

    /// This moment, as facts.
    static func user(_ c: CoachContext) -> String {
        var lines = [
            "Pet: \(c.petName) (\(c.persona)), feeling \(c.mood). Time: \(c.time).",
            "Reminder: \(describe(c.kind)).",
            "Today: \(c.done) of \(max(c.planned, c.target)) tasks done (goal \(c.target)), \(c.overdue) overdue.",
        ]
        if let t = c.nextTask { lines.append("Next task: “\(t)”.") }
        if c.minutesWithoutProgress >= 30 { lines.append("No progress for \(c.minutesWithoutProgress) minutes.") }
        if let d = c.distraction { lines.append("Right now on \(d) for \(c.distractionMinutes) minutes during work hours.") }
        if c.stuckDays > 0 { lines.append("The next task has been postponed for \(c.stuckDays) days.") }
        lines.append("Reminders ignored in a row: \(c.ignoredInRow); reminders so far today: \(c.remindersToday). Escalation: \(c.escalation)/3.")
        lines.append("The pet's own line: \(c.fallback)")
        if !c.recent.isEmpty { lines.append("Recent lines (don't repeat): " + c.recent.map { "“\($0)”" }.joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }

    static func describe(_ kind: String) -> String {
        switch kind {
        case "nudge": "a regular nudge to start the next task"
        case "plan": "today doesn't have enough tasks planned yet; get them to add tasks"
        case "overdue": "there are overdue tasks; get them handled or rescheduled"
        case "distract": "they're on a distracting app or website during work hours"
        case "grumble", "antic": "they've stayed on a distracting site for a while; the pet is fed up"
        case "stuck": "a task keeps getting postponed; push them to split it or do 2 minutes of it"
        case "hungry": "the pet is starving and only a finished task feeds it"
        case "welcome": "they just came back to the computer after a break"
        default: "a reminder to get back to work"
        }
    }

    /// The bubble text from `{"text": …}`, trimmed and capped; nil when it's empty.
    static func parse(_ json: String) -> String? {
        struct Out: Decodable { let text: String }
        guard let o = try? JSONDecoder().decode(Out.self, from: Data(json.utf8)) else { return nil }
        let t = o.text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"“”"))
        guard !t.isEmpty else { return nil }
        return t.count > maxChars + 40 ? String(t.prefix(maxChars + 39)) + "…" : t
    }
}

/// Asks Claude for one reminder bubble. A single short request: low effort, structured output, no history.
struct CoachClient {
    let client: ClaudeClient

    init(apiKey: String, model: String) {
        client = ClaudeClient(apiKey: apiKey, model: model)
    }

    func line(_ c: CoachContext, tone: CoachTone, lang: Lang, timeout: TimeInterval = 12) async throws -> String {
        let body: [String: Any] = [
            "model": client.model,
            // Room for a little thinking before the one short line.
            "max_tokens": 2000,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": CoachPrompt.schema]],
            "system": CoachPrompt.system(tone: tone, lang: lang),
            "messages": [["role": "user", "content": CoachPrompt.user(c)]],
        ]
        guard let text = CoachPrompt.parse(try ClaudeClient.text(try await client.post(body, timeout: timeout))) else {
            throw ClaudeError.badResponse
        }
        return text
    }
}
