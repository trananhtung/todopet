import AppKit

/// Reads the address of the active tab in the frontmost browser, so the pet can notice distracting sites.
/// Uses AppleScript (macOS asks once per browser for Automation permission). Addresses and page titles stay in
/// memory only.
@MainActor
final class BrowserWatcher {
    struct Browser {
        let bundleID: String
        let name: String
        let script: String
    }

    struct Visit {
        let host: String
        /// The latest address on this host (the "where was I?" card reopens it).
        var url: String
        var title: String
        /// A private or incognito window: used for distraction checks, never remembered.
        var isPrivate: Bool
        /// When you arrived on this host.
        let since: Date
    }

    enum Result {
        case url(String)
        case denied
        case failed
    }

    static let browsers: [Browser] = {
        func safari(_ id: String, _ name: String) -> Browser {
            Browser(bundleID: id, name: name, script: """
            with timeout of 5 seconds
                tell application id "\(id)"
                    if (count of documents) is 0 then return ""
                    return (URL of front document) & linefeed & (name of front document)
                end tell
            end timeout
            """)
        }
        func chromium(_ id: String, _ name: String) -> Browser {
            Browser(bundleID: id, name: name, script: """
            with timeout of 5 seconds
                tell application id "\(id)"
                    if (count of windows) is 0 then return ""
                    set t to active tab of front window
                    set m to ""
                    try
                        set m to mode of front window
                    end try
                    return (URL of t) & linefeed & (title of t) & linefeed & m
                end tell
            end timeout
            """)
        }
        return [
            safari("com.apple.Safari", "Safari"),
            safari("com.apple.SafariTechnologyPreview", "Safari Technology Preview"),
            chromium("com.google.Chrome", "Google Chrome"),
            chromium("com.google.Chrome.beta", "Google Chrome Beta"),
            chromium("com.brave.Browser", "Brave"),
            chromium("com.microsoft.edgemac", "Microsoft Edge"),
            chromium("company.thebrowser.Browser", "Arc"),
            chromium("com.vivaldi.Vivaldi", "Vivaldi"),
            chromium("com.operasoftware.Opera", "Opera"),
            chromium("org.chromium.Chromium", "Chromium"),
            chromium("com.coccoc.Coccoc", "Cốc Cốc"),
        ]
    }()

    private(set) var visit: Visit?
    /// Browsers the user refused Automation access to; we stop asking them.
    private(set) var denied: Set<String> = []
    var enabled = true
    var onDeniedChange: (() -> Void)?

    private var running = false
    private var timer: Timer?
    private let frontBundle: () -> String?

    init(frontBundle: @escaping () -> String?) {
        self.frontBundle = frontBundle
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    static func isBrowser(_ bundleID: String?) -> Bool {
        browsers.contains { $0.bundleID == bundleID }
    }

    func poll() {
        guard enabled, let id = frontBundle(), let browser = Self.browsers.first(where: { $0.bundleID == id }) else {
            visit = nil
            return
        }
        guard !running, !denied.contains(id) else { return }
        running = true
        let script = browser.script
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = BrowserWatcher.run(script)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(result, browserID: id) }
            }
        }
    }

    private func handle(_ result: Result, browserID: String) {
        running = false
        guard frontBundle() == browserID else { return }
        switch result {
        case .url(let raw):
            let lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            let url = lines[0].trimmingCharacters(in: .whitespaces)
            let title = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
            let isPrivate = lines.count > 2 && lines[2].trimmingCharacters(in: .whitespaces) == "incognito"
            guard let host = BrowserWatcher.host(of: url) else {
                visit = nil
                return
            }
            if visit?.host != host {
                visit = Visit(host: host, url: url, title: title, isPrivate: isPrivate, since: Date())
            } else {
                visit?.url = url
                visit?.title = title
                visit?.isPrivate = isPrivate
            }
        case .denied:
            denied.insert(browserID)
            visit = nil
            onDeniedChange?()
        case .failed:
            break
        }
    }

    /// Lets the user retry after granting access in System Settings.
    func resetDenied() {
        denied = []
        onDeniedChange?()
    }

    nonisolated static func host(of url: String) -> String? {
        guard let h = URL(string: url)?.host?.lowercased(), !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Returns the matching rule when the page is on the distraction list.
    /// Plain rules match a domain and its subdomains ("youtube.com" matches "m.youtube.com");
    /// rules with a slash match part of the address ("youtube.com/shorts").
    nonisolated static func match(host: String, url: String, rules: [String]) -> String? {
        let lowerURL = url.lowercased()
        for rule in rules {
            if rule.contains("/") {
                if lowerURL.contains(rule) { return rule }
            } else if host == rule || host.hasSuffix("." + rule) {
                return rule
            }
        }
        return nil
    }

    nonisolated private static func run(_ script: String) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return .failed }
        // Generous timeout: the first call waits for the user to answer the permission prompt.
        if done.wait(timeout: .now() + 60) == .timedOut {
            p.terminate()
            return .failed
        }
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus == 0 { return .url(stdout) }
        // -1743: the user denied Automation access for this browser.
        return stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authorized") ? .denied : .failed
    }
}
