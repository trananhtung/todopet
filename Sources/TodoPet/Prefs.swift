import Foundation
import Combine

enum SoundMode: String, CaseIterable, Identifiable {
    /// Silent.
    case off
    /// Meetings, tasks due now, end of focus, and finished tasks; ordinary bubbles stay silent.
    case important
    /// Every bubble and every grumble.
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: L("Tắt", "Off")
        case .important: L("Chỉ khi quan trọng", "Important only")
        case .all: L("Tất cả", "Everything")
        }
    }
}

/// User preferences, persisted in UserDefaults. The Todoist token lives in the Keychain instead.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d: UserDefaults

    @Published var lang: Lang { didSet { currentLang = lang; d.set(lang.rawValue, forKey: "lang") } }
    @Published var petName: String { didSet { d.set(petName, forKey: "petName") } }
    /// Mochi or Bảnh Bao.
    @Published var species: Species { didSet { currentSpecies = species; d.set(species.rawValue, forKey: "species") } }
    /// How many tasks you should plan for each day (the "Rule of 3").
    @Published var dailyTarget: Int { didSet { d.set(dailyTarget, forKey: "dailyTarget") } }
    @Published var workStart: Int { didSet { d.set(workStart, forKey: "workStart") } }
    @Published var workEnd: Int { didSet { d.set(workEnd, forKey: "workEnd") } }
    /// After this hour the pet worries if today is not planned yet.
    @Published var planDeadline: Int { didSet { d.set(planDeadline, forKey: "planDeadline") } }
    @Published var remindEvery: Int { didSet { d.set(remindEvery, forKey: "remindEvery") } }
    @Published var focusMinutes: Int { didSet { d.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { d.set(breakMinutes, forKey: "breakMinutes") } }
    /// Todoist filter that defines "my day".
    @Published var filterQuery: String { didSet { d.set(filterQuery, forKey: "filterQuery") } }
    /// Comma-separated app names that count as distractions.
    @Published var distractionApps: String { didSet { d.set(distractionApps, forKey: "distractionApps") } }
    @Published var soundMode: SoundMode { didSet { d.set(soundMode.rawValue, forKey: "soundMode") } }
    @Published var workSaturday: Bool { didSet { d.set(workSaturday, forKey: "workSaturday") } }
    @Published var workSunday: Bool { didSet { d.set(workSunday, forKey: "workSunday") } }
    @Published var petScale: Double { didSet { d.set(petScale, forKey: "petScale") } }
    @Published var chaseWhenAngry: Bool { didSet { d.set(chaseWhenAngry, forKey: "chaseWhenAngry") } }
    /// Read the active browser tab to notice distracting websites.
    @Published var watchBrowsers: Bool { didSet { d.set(watchBrowsers, forKey: "watchBrowsers") } }
    /// Comma-separated sites ("youtube.com") or address parts ("youtube.com/shorts").
    @Published var distractionSites: String { didSet { d.set(distractionSites, forKey: "distractionSites") } }
    @Published var useCalendar: Bool { didSet { d.set(useCalendar, forKey: "useCalendar") } }
    /// Lower the daily target on meeting-heavy days.
    @Published var adaptTarget: Bool { didSet { d.set(adaptTarget, forKey: "adaptTarget") } }
    @Published var meetingLead: Int { didSet { d.set(meetingLead, forKey: "meetingLead") } }
    /// After this many days on your list, a task counts as "keeps getting postponed".
    @Published var stuckDays: Int { didSet { d.set(stuckDays, forKey: "stuckDays") } }
    @Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }
    /// Escalating mischief when you slack off (grumbling, sign parade, standing in the way).
    @Published var antics: Bool { didSet { d.set(antics, forKey: "antics") } }
    /// Say some lines out loud with a macOS voice.
    @Published var voiceOn: Bool { didSet { d.set(voiceOn, forKey: "voiceOn") } }
    /// Hold non-urgent bubbles while you're typing steadily ("in the zone").
    @Published var protectFlow: Bool { didSet { d.set(protectFlow, forKey: "protectFlow") } }
    /// Keep the pet still (no walking, small movements) while you type.
    @Published var stillWhileTyping: Bool { didSet { d.set(stillWhileTyping, forKey: "stillWhileTyping") } }
    /// Minimum minutes between two unsolicited bubbles.
    @Published var bubbleGap: Int { didSet { d.set(bubbleGap, forKey: "bubbleGap") } }
    /// Keep the pet's diary (on this Mac only, 14 days).
    @Published var keepLog: Bool { didSet { d.set(keepLog, forKey: "keepLog") } }
    /// How many times a day the pet brings up one of your wishes ("xin vía"); 0 turns it off.
    @Published var wishPerDay: Int { didSet { d.set(wishPerDay, forKey: "wishPerDay") } }
    /// At most this many unsolicited reminders a day; meetings and timed tasks don't count.
    @Published var nudgeBudget: Int { didSet { d.set(nudgeBudget, forKey: "nudgeBudget") } }
    /// Minutes a task without a Todoist duration counts for in the day's load.
    @Published var defaultEstimate: Int { didSet { d.set(defaultEstimate, forKey: "defaultEstimate") } }
    /// Offer "where was I?" after a break, a meeting or a detour.
    @Published var resumeCard: Bool { didSet { d.set(resumeCard, forKey: "resumeCard") } }
    /// The "where was I?" card may show the page title and address (never from a private window).
    @Published var resumeDetails: Bool { didSet { d.set(resumeDetails, forKey: "resumeDetails") } }
    /// Let Claude write the reminders, with your Anthropic API key.
    @Published var coachOn: Bool { didSet { d.set(coachOn, forKey: "coachOn") } }
    @Published var coachModel: String { didSet { d.set(coachModel, forKey: "coachModel") } }
    @Published var coachTone: CoachTone { didSet { d.set(coachTone.rawValue, forKey: "coachTone") } }
    /// Relentless: twice as many reminders, no backing off when you ignore them, no hour-long hold.
    @Published var strictMode: Bool { didSet { d.set(strictMode, forKey: "strictMode") } }
    /// Show the home corner (knitted decorations) at the bottom-right of the screen.
    @Published var showHome: Bool { didSet { d.set(showHome, forKey: "showHome") } }

    /// First time the app ever ran; used so day one doesn't start with a grumpy pet.
    let firstLaunch: Date

    static let defaultFilter = "today | overdue"

    /// `defaults` can be a throwaway suite (snapshots), so dev tools never touch your real settings.
    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            "petName": "Mochi", "dailyTarget": 3, "workStart": 8, "workEnd": 18, "planDeadline": 10,
            "remindEvery": 45, "focusMinutes": 25, "breakMinutes": 5, "filterQuery": Prefs.defaultFilter,
            "distractionApps": "TikTok, Netflix, Steam, Facebook", "soundOn": true,
            "workSaturday": false, "workSunday": false, "petScale": 1.0, "chaseWhenAngry": true,
            "watchBrowsers": true,
            "distractionSites": "youtube.com, facebook.com, tiktok.com, instagram.com, x.com, reddit.com, netflix.com",
            "useCalendar": true, "adaptTarget": true, "meetingLead": 5, "stuckDays": 3,
            "claudeModel": ClaudeClient.defaultModel,
            "antics": true, "voiceOn": false,
            "protectFlow": true, "stillWhileTyping": true, "bubbleGap": 15, "keepLog": true, "wishPerDay": 2,
            "nudgeBudget": 8, "defaultEstimate": 30, "resumeCard": true, "resumeDetails": true, "showHome": true,
            "coachOn": false, "coachModel": ClaudeClient.defaultModel, "coachTone": "harsh", "strictMode": false,
        ])
        lang = Lang(rawValue: d.string(forKey: "lang") ?? "") ?? .systemDefault
        petName = d.string(forKey: "petName") ?? "Mochi"
        species = Species(rawValue: d.string(forKey: "species") ?? "") ?? .mochi
        dailyTarget = d.integer(forKey: "dailyTarget")
        workStart = d.integer(forKey: "workStart")
        workEnd = d.integer(forKey: "workEnd")
        planDeadline = d.integer(forKey: "planDeadline")
        remindEvery = d.integer(forKey: "remindEvery")
        focusMinutes = d.integer(forKey: "focusMinutes")
        breakMinutes = d.integer(forKey: "breakMinutes")
        filterQuery = d.string(forKey: "filterQuery") ?? Prefs.defaultFilter
        distractionApps = d.string(forKey: "distractionApps") ?? ""
        // Older versions had an on/off switch ("soundOn"); "on" becomes "important only".
        soundMode = SoundMode(rawValue: d.string(forKey: "soundMode") ?? "") ?? (d.bool(forKey: "soundOn") ? .important : .off)
        workSaturday = d.bool(forKey: "workSaturday")
        workSunday = d.bool(forKey: "workSunday")
        petScale = d.double(forKey: "petScale")
        chaseWhenAngry = d.bool(forKey: "chaseWhenAngry")
        watchBrowsers = d.bool(forKey: "watchBrowsers")
        distractionSites = d.string(forKey: "distractionSites") ?? ""
        useCalendar = d.bool(forKey: "useCalendar")
        adaptTarget = d.bool(forKey: "adaptTarget")
        meetingLead = d.integer(forKey: "meetingLead")
        stuckDays = d.integer(forKey: "stuckDays")
        claudeModel = d.string(forKey: "claudeModel") ?? ClaudeClient.defaultModel
        antics = d.bool(forKey: "antics")
        voiceOn = d.bool(forKey: "voiceOn")
        protectFlow = d.bool(forKey: "protectFlow")
        stillWhileTyping = d.bool(forKey: "stillWhileTyping")
        bubbleGap = d.integer(forKey: "bubbleGap")
        keepLog = d.bool(forKey: "keepLog")
        wishPerDay = d.integer(forKey: "wishPerDay")
        nudgeBudget = d.integer(forKey: "nudgeBudget")
        defaultEstimate = d.integer(forKey: "defaultEstimate")
        resumeCard = d.bool(forKey: "resumeCard")
        resumeDetails = d.bool(forKey: "resumeDetails")
        showHome = d.bool(forKey: "showHome")
        coachOn = d.bool(forKey: "coachOn")
        coachModel = d.string(forKey: "coachModel") ?? ClaudeClient.defaultModel
        coachTone = CoachTone(rawValue: d.string(forKey: "coachTone") ?? "") ?? .harsh
        strictMode = d.bool(forKey: "strictMode")
        if let f = d.object(forKey: "firstLaunch") as? Date {
            firstLaunch = f
        } else {
            firstLaunch = Date()
            d.set(firstLaunch, forKey: "firstLaunch")
        }
        currentLang = lang
        currentSpecies = species
    }

    var effectiveFilter: String {
        let f = filterQuery.trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? Prefs.defaultFilter : f
    }

    var distractionList: [String] {
        distractionApps.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    var siteRules: [String] {
        distractionSites.split(separator: ",")
            .map { rule -> String in
                var r = rule.trimmingCharacters(in: .whitespaces).lowercased()
                for prefix in ["https://", "http://", "www."] where r.hasPrefix(prefix) { r.removeFirst(prefix.count) }
                return r
            }
            .filter { !$0.isEmpty }
    }

    var effectiveCoachModel: String {
        let m = coachModel.trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? ClaudeClient.defaultModel : m
    }

    var effectiveClaudeModel: String {
        let m = claudeModel.trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? ClaudeClient.defaultModel : m
    }

    func isWorkday(_ date: Date) -> Bool {
        switch Calendar.current.component(.weekday, from: date) {
        case 7: return workSaturday
        case 1: return workSunday
        default: return true
        }
    }
}
