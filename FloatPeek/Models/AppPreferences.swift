import Combine
import Foundation

/// 保存済みの設定値を保持し、変更を利用側へ公開する唯一の保存先
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published private(set) var shortcut: KeyboardShortcut
    @Published private(set) var scaleImagesWithWindow: Bool
    @Published private(set) var displayedFileExtensions: Set<String>
    @Published private(set) var quickLookBackgroundColor: QuickLookBackgroundColor

    private let userDefaults: PreferencesStoring

    init(userDefaults: PreferencesStoring = AppEnvironment.preferences) {
        self.userDefaults = userDefaults
        shortcut = KeyboardShortcut.load(from: userDefaults)
        scaleImagesWithWindow = AppSettings.loadScaleImagesWithWindow(from: userDefaults)
        displayedFileExtensions = AppSettings.loadDisplayedFileExtensions(from: userDefaults)
        quickLookBackgroundColor = AppSettings.loadQuickLookBackgroundColor(from: userDefaults)
    }

    func setShortcut(_ shortcut: KeyboardShortcut) {
        shortcut.save(to: userDefaults)
        self.shortcut = shortcut
    }

    func setScaleImagesWithWindow(_ isEnabled: Bool) {
        AppSettings.saveScaleImagesWithWindow(isEnabled, to: userDefaults)
        scaleImagesWithWindow = isEnabled
    }

    func setDisplayedFileExtensions(_ extensions: Set<String>) {
        AppSettings.saveDisplayedFileExtensions(extensions, to: userDefaults)
        displayedFileExtensions = extensions.intersection(AppSettings.allSupportedFileExtensions)
    }

    func setQuickLookBackgroundColor(_ color: QuickLookBackgroundColor) {
        let normalizedColor = color.normalized()
        AppSettings.saveQuickLookBackgroundColor(normalizedColor, to: userDefaults)
        quickLookBackgroundColor = normalizedColor
    }
}
