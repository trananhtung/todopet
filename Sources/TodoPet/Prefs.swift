import Foundation
import Combine

/// User preferences, persisted in UserDefaults. The Todoist token lives in the Keychain instead.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var lang: Lang { didSet { currentLang = lang; d.set(lang.rawValue, forKey: "lang") } }
    @Published var petName: String { didSet { d.set(petName, forKey: "petName") } }
    /// How many tasks you should plan for each day (the "Rule of 3").
    @Published var dailyTarget: Int { didSet { d.set(dailyTarget, forKey: "dailyTarget") } }
    @Published var workStart: Int { didSet { d.set(workStart, forKey: "workStart") } }
    @Published var workEnd: Int { didSet { d.set(workEnd, forKey: "workEnd") } }
    /// After this hour the pet gets grumpy if today is not planned yet.
    @Published var planDeadline: Int { didSet { d.set(planDeadline, forKey: "planDeadline") } }
    @Published var remindEvery: Int { didSet { d.set(remindEvery, forKey: "remindEvery") } }
    @Published var focusMinutes: Int { didSet { d.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { d.set(breakMinutes, forKey: "breakMinutes") } }
    /// Todoist filter that defines "my day".
    @Published var filterQuery: String { didSet { d.set(filterQuery, forKey: "filterQuery") } }
    /// Comma-separated app names that count as distractions.
    @Published var distractionApps: String { didSet { d.set(distractionApps, forKey: "distractionApps") } }
    @Published var soundOn: Bool { didSet { d.set(soundOn, forKey: "soundOn") } }
    @Published var workSaturday: Bool { didSet { d.set(workSaturday, forKey: "workSaturday") } }
    @Published var workSunday: Bool { didSet { d.set(workSunday, forKey: "workSunday") } }
    @Published var petScale: Double { didSet { d.set(petScale, forKey: "petScale") } }
    @Published var chaseWhenAngry: Bool { didSet { d.set(chaseWhenAngry, forKey: "chaseWhenAngry") } }

    /// First time the app ever ran; used so day one doesn't start with a grumpy pet.
    let firstLaunch: Date

    static let defaultFilter = "today | overdue"

    init() {
        d.register(defaults: [
            "petName": "Mochi", "dailyTarget": 3, "workStart": 8, "workEnd": 18, "planDeadline": 10,
            "remindEvery": 45, "focusMinutes": 25, "breakMinutes": 5, "filterQuery": Prefs.defaultFilter,
            "distractionApps": "TikTok, Netflix, Steam, Facebook", "soundOn": true,
            "workSaturday": false, "workSunday": false, "petScale": 1.0, "chaseWhenAngry": true,
        ])
        lang = Lang(rawValue: d.string(forKey: "lang") ?? "") ?? .systemDefault
        petName = d.string(forKey: "petName") ?? "Mochi"
        dailyTarget = d.integer(forKey: "dailyTarget")
        workStart = d.integer(forKey: "workStart")
        workEnd = d.integer(forKey: "workEnd")
        planDeadline = d.integer(forKey: "planDeadline")
        remindEvery = d.integer(forKey: "remindEvery")
        focusMinutes = d.integer(forKey: "focusMinutes")
        breakMinutes = d.integer(forKey: "breakMinutes")
        filterQuery = d.string(forKey: "filterQuery") ?? Prefs.defaultFilter
        distractionApps = d.string(forKey: "distractionApps") ?? ""
        soundOn = d.bool(forKey: "soundOn")
        workSaturday = d.bool(forKey: "workSaturday")
        workSunday = d.bool(forKey: "workSunday")
        petScale = d.double(forKey: "petScale")
        chaseWhenAngry = d.bool(forKey: "chaseWhenAngry")
        if let f = d.object(forKey: "firstLaunch") as? Date {
            firstLaunch = f
        } else {
            firstLaunch = Date()
            d.set(firstLaunch, forKey: "firstLaunch")
        }
        currentLang = lang
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

    func isWorkday(_ date: Date) -> Bool {
        switch Calendar.current.component(.weekday, from: date) {
        case 7: return workSaturday
        case 1: return workSunday
        default: return true
        }
    }
}
