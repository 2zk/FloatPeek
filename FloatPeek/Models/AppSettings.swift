import Carbon
import Foundation

struct QuickLookBackgroundColor: Equatable {
    static let defaultColor = QuickLookBackgroundColor(
        red: 1,
        green: 149.0 / 255.0,
        blue: 0
    )

    var red: Double
    var green: Double
    var blue: Double

    var colorComponents: [Double] {
        [red, green, blue]
    }

    func normalized() -> QuickLookBackgroundColor {
        let defaultColor = Self.defaultColor
        let components = colorComponents
        let hasValidColor = components.allSatisfy { $0.isFinite && (0...1).contains($0) }

        return QuickLookBackgroundColor(
            red: hasValidColor ? red : defaultColor.red,
            green: hasValidColor ? green : defaultColor.green,
            blue: hasValidColor ? blue : defaultColor.blue
        )
    }
}

struct AppSettings {
    static let selectedFolderPathKey = "selectedFolderPath"
    static let shortcutKeyCodeKey = "shortcutKeyCode"
    static let shortcutModifiersKey = "shortcutModifiers"
    static let windowFrameKey = "windowFrame"
    static let languageKey = "language"
    static let folderTabsKey = "folderTabs"
    static let selectedFolderTabIDKey = "selectedFolderTabID"
    static let scaleImagesWithWindowKey = "scaleImagesWithWindow"
    static let displayedFileExtensionsKey = "displayedFileExtensions"
    static let displayedFileExtensionsMigrationVersionKey =
        "displayedFileExtensionsMigrationVersion"
    static let quickLookBackgroundColorComponentsKey = "quickLookBackgroundColorComponents"
    static let autoHideEnabledKey = "autoHideEnabled"
    static let autoHideDelaySecondsKey = "autoHideDelaySeconds"
    static let defaultAutoHideDelaySeconds = 10
    static let autoHideDelayRange = 1...600
    private static let legacyQuickLookBorderColorComponentsKey =
        "quickLookBorderColorComponents"

    static let thumbnailFileExtensions = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "heic",
        "webp",
        "tif",
        "tiff",
        "bmp",
        "svg",
        "pdf"
    ]
    static let iconFileExtensions = [
        "txt",
        "md",
        "csv",
        "rtf",
        "doc",
        "docx",
        "xls",
        "xlsx",
        "ppt",
        "pptx"
    ]
    static let supportedFileExtensions = thumbnailFileExtensions + iconFileExtensions
    static let allThumbnailFileExtensions = Set(thumbnailFileExtensions)
    static let allIconFileExtensions = Set(iconFileExtensions)
    static let allSupportedFileExtensions = Set(supportedFileExtensions)
    static let defaultDisplayedFileExtensions = allThumbnailFileExtensions

    private static let newlyAddedThumbnailFileExtensions: Set<String> = [
        "webp",
        "tif",
        "tiff",
        "bmp",
        "svg"
    ]
    private static let displayedFileExtensionsMigrationVersion = 1

    static let defaultShortcut = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_1),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    static func loadScaleImagesWithWindow(
        from userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) -> Bool {
        userDefaults.object(forKey: scaleImagesWithWindowKey) as? Bool ?? true
    }

    static func saveScaleImagesWithWindow(
        _ isEnabled: Bool,
        to userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) {
        userDefaults.set(isEnabled, forKey: scaleImagesWithWindowKey)
    }

    static func loadAutoHideEnabled(
        from userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) -> Bool {
        userDefaults.object(forKey: autoHideEnabledKey) as? Bool ?? false
    }

    static func saveAutoHideEnabled(
        _ isEnabled: Bool,
        to userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) {
        userDefaults.set(isEnabled, forKey: autoHideEnabledKey)
    }

    static func loadAutoHideDelaySeconds(
        from userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) -> Int {
        let storedSeconds = userDefaults.object(forKey: autoHideDelaySecondsKey) as? Int
        return clampedAutoHideDelaySeconds(storedSeconds ?? defaultAutoHideDelaySeconds)
    }

    static func saveAutoHideDelaySeconds(
        _ seconds: Int,
        to userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) {
        userDefaults.set(clampedAutoHideDelaySeconds(seconds), forKey: autoHideDelaySecondsKey)
    }

    static func clampedAutoHideDelaySeconds(_ seconds: Int) -> Int {
        min(max(seconds, autoHideDelayRange.lowerBound), autoHideDelayRange.upperBound)
    }

    static func loadDisplayedFileExtensions(
        from userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) -> Set<String> {
        let storedExtensions = userDefaults.object(
            forKey: displayedFileExtensionsKey
        ) as? [String]
        var displayedExtensions = storedExtensions.map {
            Set($0).intersection(allSupportedFileExtensions)
        } ?? defaultDisplayedFileExtensions

        let migrationVersion = userDefaults.integer(
            forKey: displayedFileExtensionsMigrationVersionKey
        )
        guard migrationVersion < displayedFileExtensionsMigrationVersion else {
            return displayedExtensions
        }

        if storedExtensions != nil {
            displayedExtensions.formUnion(newlyAddedThumbnailFileExtensions)
        }
        saveDisplayedFileExtensions(displayedExtensions, to: userDefaults)
        return displayedExtensions
    }

    static func saveDisplayedFileExtensions(
        _ extensions: Set<String>,
        to userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) {
        let storedExtensions = supportedFileExtensions.filter(extensions.contains)
        userDefaults.set(storedExtensions, forKey: displayedFileExtensionsKey)
        userDefaults.set(
            displayedFileExtensionsMigrationVersion,
            forKey: displayedFileExtensionsMigrationVersionKey
        )
    }

    static func loadQuickLookBackgroundColor(
        from userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) -> QuickLookBackgroundColor {
        let defaultColor = QuickLookBackgroundColor.defaultColor
        let storedComponents = (
            userDefaults.object(forKey: quickLookBackgroundColorComponentsKey)
                ?? userDefaults.object(forKey: legacyQuickLookBorderColorComponentsKey)
        ) as? [Double]

        guard let storedComponents,
              storedComponents.count == 3 else {
            return defaultColor
        }

        return QuickLookBackgroundColor(
            red: storedComponents[0],
            green: storedComponents[1],
            blue: storedComponents[2]
        ).normalized()
    }

    static func saveQuickLookBackgroundColor(
        _ color: QuickLookBackgroundColor,
        to userDefaults: PreferencesStoring = AppEnvironment.preferences
    ) {
        let normalizedColor = color.normalized()
        userDefaults.set(
            normalizedColor.colorComponents,
            forKey: quickLookBackgroundColorComponentsKey
        )
    }
}
