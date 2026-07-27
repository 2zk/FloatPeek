import AppKit
import XCTest
@testable import FloatPeek

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testTestHostUsesInMemoryPreferences() {
        XCTAssertTrue(AppEnvironment.isRunningTests)
        XCTAssertTrue(AppEnvironment.preferences is InMemoryPreferences)
    }

    func testNormalEnvironmentUsesStandardPreferences() {
        let preferences = AppEnvironment.makePreferences(environment: [:])

        XCTAssertTrue(preferences === UserDefaults.standard)
    }

    func testTestEnvironmentDoesNotWriteToStandardPreferences() {
        let key = "AppLifecycleTests.isolation.\(UUID().uuidString)"
        let preferences = AppEnvironment.makePreferences(environment: [
            "XCTestConfigurationFilePath": "/tmp/FloatPeekTests.xctestconfiguration"
        ])

        preferences.set("isolated", forKey: key)

        XCTAssertEqual(preferences.string(forKey: key), "isolated")
        XCTAssertNil(UserDefaults.standard.string(forKey: key))
    }

    func testAppDisablesAutomaticWindowTabbingBeforeLaunch() {
        NSWindow.allowsAutomaticWindowTabbing = true

        AppDelegate().applicationWillFinishLaunching(
            Notification(name: NSApplication.willFinishLaunchingNotification)
        )

        XCTAssertFalse(NSWindow.allowsAutomaticWindowTabbing)
    }

    func testConfiguredWindowDisallowsNativeTabs() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        WindowManager.shared.configure(window: window)

        XCTAssertEqual(window.tabbingMode, .disallowed)
    }

    func testAppStaysRunningWhenLastWindowCloses() {
        let appDelegate = AppDelegate()

        XCTAssertFalse(
            appDelegate.applicationShouldTerminateAfterLastWindowClosed(.shared)
        )
    }

    func testSystemLanguageUsesSupportedPreferredLanguage() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["ja-JP", "en-US"]),
            "ja"
        )
    }

    func testSystemLanguageFallsBackToEnglishForUnsupportedLanguage() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["fr-FR"]),
            "en"
        )
    }

    func testSelectedLanguageIsSavedAndRestored() {
        let suiteName = "AppLifecycleTests.language.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let localization = LocalizationManager(userDefaults: userDefaults)
        XCTAssertEqual(localization.language, .system)

        localization.language = .japanese

        XCTAssertEqual(
            LocalizationManager(userDefaults: userDefaults).language,
            .japanese
        )
    }

    func testLegacyFolderSettingMigratesToFirstTab() {
        let suiteName = "AppLifecycleTests.tabs.migration.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults.set("/tmp/Images", forKey: AppSettings.selectedFolderPathKey)

        let tabManager = FolderTabManager(userDefaults: userDefaults)

        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertEqual(tabManager.tabs.first?.name, "Images")
        XCTAssertEqual(tabManager.tabs.first?.folderPath, "/tmp/Images")
        XCTAssertEqual(tabManager.selectedTabID, tabManager.tabs.first?.id)
    }

    func testTabsAndSelectionAreSavedAndRestored() {
        let suiteName = "AppLifecycleTests.tabs.persistence.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let firstTab = FolderTab(name: "First", folderPath: "/tmp/First")
        let secondTab = FolderTab(name: "Second", folderPath: "/tmp/Second")
        let tabManager = FolderTabManager(userDefaults: userDefaults)

        tabManager.replaceTabs([firstTab, secondTab], selectedTabID: secondTab.id)
        let restoredManager = FolderTabManager(userDefaults: userDefaults)

        XCTAssertEqual(restoredManager.tabs, [firstTab, secondTab])
        XCTAssertEqual(restoredManager.selectedTabID, secondTab.id)
    }

    func testRemovingSelectedTabSelectsFirstRemainingTab() {
        let suiteName = "AppLifecycleTests.tabs.selection.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let firstTab = FolderTab(name: "First")
        let removedTab = FolderTab(name: "Removed")
        let tabManager = FolderTabManager(userDefaults: userDefaults)

        tabManager.replaceTabs([firstTab], selectedTabID: removedTab.id)

        XCTAssertEqual(tabManager.selectedTabID, firstTab.id)
    }

    func testSelectingAdjacentTabsWrapsAround() {
        let suiteName = "AppLifecycleTests.tabs.adjacent.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let firstTab = FolderTab(name: "First")
        let secondTab = FolderTab(name: "Second")
        let thirdTab = FolderTab(name: "Third")
        let tabManager = FolderTabManager(userDefaults: userDefaults)

        tabManager.replaceTabs([firstTab, secondTab, thirdTab], selectedTabID: firstTab.id)

        XCTAssertTrue(tabManager.selectNextTab())
        XCTAssertEqual(tabManager.selectedTabID, secondTab.id)
        XCTAssertTrue(tabManager.selectNextTab())
        XCTAssertEqual(tabManager.selectedTabID, thirdTab.id)
        XCTAssertTrue(tabManager.selectNextTab())
        XCTAssertEqual(tabManager.selectedTabID, firstTab.id)

        XCTAssertTrue(tabManager.selectPreviousTab())
        XCTAssertEqual(tabManager.selectedTabID, thirdTab.id)
    }

    func testSelectingAdjacentTabRequiresMultipleTabs() {
        let suiteName = "AppLifecycleTests.tabs.single.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let onlyTab = FolderTab(name: "Only")
        let tabManager = FolderTabManager(userDefaults: userDefaults)

        tabManager.replaceTabs([onlyTab], selectedTabID: onlyTab.id)

        XCTAssertFalse(tabManager.selectNextTab())
        XCTAssertFalse(tabManager.selectPreviousTab())
        XCTAssertEqual(tabManager.selectedTabID, onlyTab.id)
    }
}
