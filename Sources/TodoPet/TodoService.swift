import Foundation

enum TodoError: LocalizedError {
    case unauthorized
    case rateLimited
    case http(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return L("Token Todoist không hợp lệ hoặc đã hết hạn.", "The Todoist token is invalid or expired.")
        case .rateLimited:
            return L("Todoist đang giới hạn tốc độ, thử lại sau ít phút.", "Todoist is rate limiting, retrying in a few minutes.")
        case let .http(code, body):
            return "HTTP \(code): \(body)"
        case let .network(msg):
            return L("Lỗi mạng: ", "Network error: ") + msg
        }
    }
}

/// Everything the pet needs from Todoist.
protocol TodoService: AnyObject {
    func activeTasks(filter: String) async throws -> [TodoTask]
    func completedTasks(since: Date, until: Date) async throws -> [TodoTask]
    func stats() async throws -> ProductivityStats
    func addTask(content: String, dueString: String?, priority: Int) async throws
    func quickAdd(text: String) async throws
    func close(id: String) async throws
    func reopen(id: String) async throws
    func reschedule(id: String, dueString: String) async throws
}

// MARK: - Real client (Todoist API v1, https://developer.todoist.com/api/v1/)

final class TodoistClient: TodoService {
    private let token: String
    private let base = URL(string: "https://api.todoist.com/api/v1/")!
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(token: String) {
        self.token = token
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    private struct Page: Decodable {
        var results: [TodoTask]?
        var items: [TodoTask]?
        var nextCursor: String?
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [String: String] = [:],
                      body: [String: Any]? = nil) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            // URLComponents leaves "+" alone, but servers read it as a space.
            comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" { req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id") }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw TodoError.network(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: return data
        case 401: throw TodoError.unauthorized
        case 429: throw TodoError.rateLimited
        default:
            let text = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw TodoError.http(code, text)
        }
    }

    private func paged(_ path: String, _ query: [String: String]) async throws -> [TodoTask] {
        var all: [TodoTask] = []
        var cursor: String?
        for _ in 0..<10 {
            var q = query
            q["limit"] = "200"
            if let cursor { q["cursor"] = cursor }
            let page = try decoder.decode(Page.self, from: try await send("GET", path, query: q))
            all += page.results ?? page.items ?? []
            guard let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return all
    }

    func activeTasks(filter: String) async throws -> [TodoTask] {
        try await paged("tasks/filter", ["query": filter])
    }

    func completedTasks(since: Date, until: Date) async throws -> [TodoTask] {
        try await paged("tasks/completed/by_completion_date",
                        ["since": DateParse.utcString(since), "until": DateParse.utcString(until)])
    }

    func stats() async throws -> ProductivityStats {
        try decoder.decode(ProductivityStats.self, from: try await send("GET", "tasks/completed/stats"))
    }

    func addTask(content: String, dueString: String?, priority: Int) async throws {
        var body: [String: Any] = ["content": content, "priority": priority]
        if let dueString {
            body["due_string"] = dueString
            body["due_lang"] = "en"
        }
        try await send("POST", "tasks", body: body)
    }

    func quickAdd(text: String) async throws {
        try await send("POST", "tasks/quick", body: ["text": text])
    }

    func close(id: String) async throws {
        try await send("POST", "tasks/\(id)/close")
    }

    func reopen(id: String) async throws {
        try await send("POST", "tasks/\(id)/reopen")
    }

    func reschedule(id: String, dueString: String) async throws {
        try await send("POST", "tasks/\(id)", body: ["due_string": dueString, "due_lang": "en"])
    }
}

// MARK: - Demo service (no account needed): `TodoPet --demo`

final class DemoService: TodoService {
    private var active: [TodoTask]
    private var done: [TodoTask] = []
    private var counter = 100

    init(now: Date = Date()) {
        let today = DayMath.key(now)
        let yesterday = DayMath.key(now.addingTimeInterval(-86_400))
        let soon = DayMath.at(hour: DayMath.hour(now) + 1, on: now)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        active = [
            TodoTask(id: "1", content: L("Viết báo cáo tuần", "Write the weekly report"), priority: 4,
                     due: TodoDue(date: today, string: "today")),
            TodoTask(id: "2", content: L("Gọi cho khách hàng ABC", "Call client ABC"), priority: 3,
                     due: TodoDue(date: f.string(from: soon), string: "today")),
            TodoTask(id: "3", content: L("Trả lời email của sếp", "Reply to the boss's email"), priority: 1,
                     due: TodoDue(date: yesterday, string: "yesterday")),
        ]
    }

    private func pause() async { try? await Task.sleep(nanoseconds: 150_000_000) }

    func activeTasks(filter: String) async throws -> [TodoTask] { await pause(); return active }
    func completedTasks(since: Date, until: Date) async throws -> [TodoTask] { await pause(); return done }
    func stats() async throws -> ProductivityStats {
        ProductivityStats(completedCount: 42 + done.count, daysItems: nil,
                          goals: .init(dailyGoal: 3, currentDailyStreak: .init(count: 4), maxDailyStreak: .init(count: 9)),
                          karma: 1234)
    }

    func addTask(content: String, dueString: String?, priority: Int) async throws {
        await pause()
        counter += 1
        let now = Date()
        let day: String? = switch dueString {
        case "today": DayMath.key(now)
        case "tomorrow": DayMath.key(now.addingTimeInterval(86_400))
        default: nil
        }
        active.append(TodoTask(id: "\(counter)", content: content, priority: priority,
                               due: day.map { TodoDue(date: $0, string: dueString) }))
    }

    func quickAdd(text: String) async throws {
        try await addTask(content: text, dueString: "today", priority: 1)
    }

    func close(id: String) async throws {
        await pause()
        guard let i = active.firstIndex(where: { $0.id == id }) else { return }
        var t = active.remove(at: i)
        t.checked = true
        t.completedAt = DateParse.utcString(Date())
        done.append(t)
    }

    func reopen(id: String) async throws {
        await pause()
        guard let i = done.firstIndex(where: { $0.id == id }) else { return }
        var t = done.remove(at: i)
        t.checked = false
        t.completedAt = nil
        active.append(t)
    }

    func reschedule(id: String, dueString: String) async throws {
        await pause()
        guard let i = active.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        let day = dueString == "tomorrow" ? DayMath.key(now.addingTimeInterval(86_400)) : DayMath.key(now)
        active[i].due = TodoDue(date: day, string: dueString)
        if dueString == "tomorrow" { active.remove(at: i) }
    }
}
