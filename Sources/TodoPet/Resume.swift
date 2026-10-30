import Foundation

/// "Where was I?": what you were working on (task, app, page), kept in memory only, never saved or logged.
/// After an interruption a clear cue to resume helps you get back faster (Trafton 2005; Iqbal & Horvitz 2007),
/// and a one-line "next step" helps you let go of the work in between (Leroy & Glomb 2018).
struct WorkContext: Equatable {
    var taskId: String?
    var taskTitle: String?
    /// Only the next task in line, not one you were focusing on or last acted on: the card says "Next up".
    var taskIsNext = false
    var app: String?
    var bundle: String?
    var pageTitle: String?
    /// http(s) address of the browser tab, cleaned by `ResumeRules.workURL`.
    var url: String?
    /// Optional one-line next step (📌 Pin my place).
    var note: String?
    var at: Date
}

enum ResumeRules {
    /// Coming back after this long away offers the card.
    static let awayMinutes = 5.0
    /// Leaving a distraction after this long offers it too.
    static let detourMinutes = 2.0
    /// The card comes at most this often.
    static let cooldownMinutes = 30.0
    static let maxURL = 2048

    /// Call apps and pages: being in a meeting isn't the work you come back to after it.
    static let conferencingBundles = ["us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp",
                                      "Cisco-Systems.Spark", "com.skype.skype", "com.apple.FaceTime"]
    static let conferencingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com"]
    /// The pet itself and system surfaces are never "where you were".
    static let notWorkBundles = ["com.todopet.mochi", "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.dock",
                                 "com.apple.Spotlight", "com.apple.notificationcenterui", "com.apple.controlcenter",
                                 "com.apple.systemuiserver", "com.apple.UserNotificationCenter", "com.apple.SecurityAgent"]

    static func isConferencing(bundle: String?, url: String?) -> Bool {
        if let b = bundle, conferencingBundles.contains(b) { return true }
        guard let host = url.flatMap(BrowserWatcher.host(of:)) else { return false }
        return conferencingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isWorkApp(bundle: String?) -> Bool {
        guard let b = bundle, !b.isEmpty else { return false }
        return !notWorkBundles.contains(b) && !conferencingBundles.contains(b)
    }

    private static let secretWords: Set<String> = ["token", "code", "key", "secret", "sig", "signature", "auth", "session",
                                                   "password", "passwd", "pwd", "state", "credential", "credentials", "jwt", "sid"]
    private static let secretEndings = ["token", "secret", "password", "passwd", "signature", "apikey", "sessionid", "session"]

    /// "access_token", "X-Amz-Signature", "apiKey" and "sessionid" look like secrets; "keyword", "author" and "page" don't.
    static func isSecretParam(_ name: String) -> Bool {
        let spaced = name.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression).lowercased()
        let parts = spaced.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init)
        let compact = parts.joined()
        return parts.contains(where: secretWords.contains) || secretEndings.contains { compact.hasSuffix($0) }
    }

    /// An http(s) address for the card and for Reopen: no credentials, no #fragment, no query parameters that look
    /// like secrets (OAuth codes, signed links, session ids), at most 2048 characters.
    static func workURL(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              var c = URLComponents(string: raw), let scheme = c.scheme?.lowercased(),
              scheme == "http" || scheme == "https", c.host?.isEmpty == false else { return nil }
        c.fragment = nil
        c.user = nil
        c.password = nil
        if let items = c.percentEncodedQueryItems {
            let kept = items.filter { !isSecretParam($0.name.removingPercentEncoding ?? $0.name) }
            c.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        }
        guard var s = c.string else { return nil }
        if s.count > maxURL {
            s = String(s.prefix(maxURL)).replacingOccurrences(of: "%[0-9A-Fa-f]?$", with: "", options: .regularExpression)
        }
        return s
    }

    /// Coming back after 5+ minutes away, after a meeting, or leaving a distraction after 2+ minutes.
    static func shouldOffer(awayMinutes: Double = 0, afterMeeting: Bool = false, leftDistractionMinutes: Double? = nil) -> Bool {
        awayMinutes >= Self.awayMinutes || afterMeeting || (leftDistractionMinutes ?? 0) >= detourMinutes
    }

    /// "Docs - Google Chrome" in Google Chrome → "Docs".
    static func titleWithoutApp(_ title: String, app: String?) -> String {
        guard let app, !app.isEmpty else { return title }
        for sep in [" - ", " — ", " – ", " | "] {
            let suffix = sep + app
            if title.count > suffix.count, title.lowercased().hasSuffix(suffix.lowercased()) {
                return String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return title
    }

    /// "Google Chrome — Q4 budget", the app alone, or the site's host; nil when unknown.
    static func whereText(_ c: WorkContext) -> String? {
        let raw = c.pageTitle.map { titleWithoutApp($0, app: c.app) }
        let title = raw.flatMap { $0.isEmpty || $0.lowercased() == (c.app ?? "").lowercased() ? nil : TextClean.short($0, 60) }
        switch (c.app, title) {
        case let (app?, title?): return "\(app) — \(title)"
        case let (app?, nil): return app
        case let (nil, title?): return title
        default: return workURL(c.url).flatMap(BrowserWatcher.host(of:))
        }
    }

    static func host(_ c: WorkContext) -> String? { workURL(c.url).flatMap(BrowserWatcher.host(of:)) }
}
