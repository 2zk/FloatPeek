import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case japanese

    var id: Self {
        self
    }

    @MainActor
    var displayName: String {
        switch self {
        case .system:
            return localized("System Default")
        case .english:
            return localized("English")
        case .japanese:
            return localized("Japanese")
        }
    }

    func resolvedLanguageCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .system:
            return Bundle.preferredLocalizations(
                from: ["en", "ja"],
                forPreferences: preferredLanguages
            ).first ?? "en"
        case .english:
            return "en"
        case .japanese:
            return "ja"
        }
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: AppSettings.languageKey)
        }
    }

    var locale: Locale {
        Locale(identifier: language.resolvedLanguageCode())
    }

    private let userDefaults: PreferencesStoring

    init(userDefaults: PreferencesStoring = AppEnvironment.preferences) {
        self.userDefaults = userDefaults
        language = userDefaults.string(forKey: AppSettings.languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func localized(_ key: String) -> String {
        let languageCode = language.resolvedLanguageCode()

        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
}

@MainActor
func localized(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}
