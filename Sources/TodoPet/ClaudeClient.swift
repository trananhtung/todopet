import Foundation

enum ClaudeError: LocalizedError {
    case noKey
    case refused
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey: L("Chưa có API key của Claude (thêm trong Cài đặt).", "No Claude API key yet (add one in Settings).")
        case .refused: L("Claude từ chối yêu cầu này.", "Claude declined this request.")
        case let .http(code, body): "Claude API \(code): \(body)"
        case .badResponse: L("Claude trả về dữ liệu không đọc được.", "Couldn't read Claude's answer.")
        }
    }
}

/// Asks Claude to split a task you keep postponing into small first steps.
/// Swift has no official Anthropic SDK, so this calls the Messages API over HTTPS directly.
struct ClaudeClient {
    static let defaultModel = "claude-opus-5-5"

    let apiKey: String
    let model: String

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": ["steps": ["type": "array", "items": ["type": "string"]]],
        "required": ["steps"],
        "additionalProperties": false,
    ]

    func breakdown(title: String, notes: String?) async throws -> [String] {
        let system = L(
            "Bạn giúp người dùng bắt đầu một việc họ cứ trì hoãn. Chia việc thành 3–5 bước cụ thể, mỗi bước làm xong trong 15–30 phút, bắt đầu bằng động từ, dưới 70 ký tự. Bước đầu tiên phải là bước dễ nhất để bắt tay vào ngay. Viết bằng tiếng Việt.",
            "You help someone start a task they keep postponing. Split it into 3–5 concrete steps, each doable in 15–30 minutes, starting with a verb, under 70 characters. The first step must be the easiest one to start right away. Write in English.")
        var prompt = L("Việc: ", "Task: ") + title
        if let notes, !notes.isEmpty { prompt += "\n" + L("Ghi chú: ", "Notes: ") + notes }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": ClaudeClient.schema]],
            "system": system,
            "messages": [["role": "user", "content": prompt]],
        ]
        return try ClaudeClient.parseSteps(try await post(body))
    }

    /// Server-side refusal fallbacks are offered on these models; Claude Haiku 5.5 has none.
    static func hasServerFallback(_ model: String) -> Bool {
        ["claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5", "claude-fable-5-1", "claude-fable-5"].contains(model)
    }

    /// Sends one Messages API request and returns the raw response body.
    func post(_ body: [String: Any], timeout: TimeInterval = 90) async throws -> Data {
        var body = body
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if ClaudeClient.hasServerFallback(model) {
            // On a safety decline, let the API retry on its recommended fallback model.
            body["fallbacks"] = "default"
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ClaudeError.http(code, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        return data
    }

    /// The text block of a response (after any thinking blocks), or a refusal.
    static func text(_ data: Data) throws -> String {
        struct Block: Decodable { let type: String; let text: String? }
        struct Response: Decodable { let content: [Block]; let stop_reason: String? }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { throw ClaudeError.badResponse }
        if r.stop_reason == "refusal" { throw ClaudeError.refused }
        guard let text = r.content.first(where: { $0.type == "text" })?.text else { throw ClaudeError.badResponse }
        return text
    }

    /// Reads `{"steps": [...]}` from the text block of a Messages API response.
    static func parseSteps(_ data: Data) throws -> [String] {
        struct Steps: Decodable { let steps: [String] }
        let json = try text(data)
        guard let steps = try? JSONDecoder().decode(Steps.self, from: Data(json.utf8)) else { throw ClaudeError.badResponse }
        let clean = steps.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { throw ClaudeError.badResponse }
        return Array(clean.prefix(6))
    }
}
