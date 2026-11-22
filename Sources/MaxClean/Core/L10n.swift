import Foundation

enum Lang: String, CaseIterable, Identifiable {
    case en, ru, uz
    var id: String { rawValue }
    var title: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .uz: return "O'zbekcha"
        }
    }
    var localeID: String {
        switch self {
        case .en: return "en_US"
        case .ru: return "ru_RU"
        case .uz: return "uz_Latn"
        }
    }

    static var systemDefault: Lang {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        switch code {
        case "ru", "kk", "ky", "tg", "be", "uk": return .ru
        case "uz": return .uz
        default: return .en
        }
    }

    static var current: Lang {
        Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "") ?? systemDefault
    }
}

/// Uch tildagi matn: T("o'zbekcha", "English", "Русский")
func T(_ uz: String, _ en: String, _ ru: String) -> String {
    switch Lang.current {
    case .uz: return uz
    case .en: return en
    case .ru: return ru
    }
}
