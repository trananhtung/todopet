import Foundation

/// UI language. The whole app is bilingual; every user-facing string goes through `L(vi, en)`.
enum Lang: String, CaseIterable, Identifiable {
    case en, vi

    var id: String { rawValue }
    var label: String { self == .vi ? "Tiếng Việt" : "English" }

    static var systemDefault: Lang {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("vi") ? .vi : .en
    }
}

/// Current UI language, kept in sync by `Prefs.lang`.
nonisolated(unsafe) var currentLang: Lang = .systemDefault

/// Bilingual string: `L("Xin chào", "Hello")`.
func L(_ vi: String, _ en: String) -> String { currentLang == .vi ? vi : en }

/// Picks one random bilingual variant.
func pick(_ options: [(String, String)]) -> String {
    let o = options.randomElement() ?? ("", "")
    return L(o.0, o.1)
}
