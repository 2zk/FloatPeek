import Carbon
import XCTest
@testable import FloatPeek

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testImageScalingDefaultsToEnabledAndPersistsDisabledValue() {
        let preferences = InMemoryPreferences()

        XCTAssertTrue(AppSettings.loadScaleImagesWithWindow(from: preferences))

        AppSettings.saveScaleImagesWithWindow(false, to: preferences)

        XCTAssertFalse(AppSettings.loadScaleImagesWithWindow(from: preferences))
    }

    func testDisplayedFileExtensionsDefaultToThumbnailsAndPersistEmptySelection() {
        let preferences = InMemoryPreferences()

        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: preferences),
            AppSettings.defaultDisplayedFileExtensions
        )
        XCTAssertTrue(
            AppSettings.defaultDisplayedFileExtensions
                .isDisjoint(with: AppSettings.allIconFileExtensions)
        )

        AppSettings.saveDisplayedFileExtensions([], to: preferences)

        XCTAssertEqual(AppSettings.loadDisplayedFileExtensions(from: preferences), [])
    }

    func testLegacyDisplayedExtensionsAddNewThumbnailsOnce() {
        let preferences = InMemoryPreferences()
        preferences.set(
            ["png", "txt"],
            forKey: AppSettings.displayedFileExtensionsKey
        )

        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: preferences),
            ["png", "txt", "webp", "tif", "tiff", "bmp", "svg"]
        )

        AppSettings.saveDisplayedFileExtensions(["png", "txt"], to: preferences)

        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: preferences),
            ["png", "txt"]
        )
    }

    func testLegacyEmptySelectionAddsOnlyNewThumbnails() {
        let preferences = InMemoryPreferences()
        preferences.set([], forKey: AppSettings.displayedFileExtensionsKey)

        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: preferences),
            ["webp", "tif", "tiff", "bmp", "svg"]
        )
    }

    func testBulkFileExtensionSelectionChangesOnlyTargetGroup() {
        let context = makeContext()
        context.viewModel.displayedFileExtensions = ["txt"]

        context.viewModel.setDisplayedFileExtensions(
            AppSettings.thumbnailFileExtensions,
            isDisplayed: true
        )

        XCTAssertEqual(
            context.viewModel.displayedFileExtensions,
            AppSettings.allThumbnailFileExtensions.union(["txt"])
        )

        context.viewModel.setDisplayedFileExtensions(
            AppSettings.thumbnailFileExtensions,
            isDisplayed: false
        )

        XCTAssertEqual(context.viewModel.displayedFileExtensions, ["txt"])

        context.viewModel.setDisplayedFileExtensions(
            AppSettings.iconFileExtensions,
            isDisplayed: false
        )

        XCTAssertEqual(context.viewModel.displayedFileExtensions, [])
        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: context.preferences),
            AppSettings.defaultDisplayedFileExtensions
        )
    }

    func testQuickLookBackgroundColorDefaultsAndPersists() {
        let preferences = InMemoryPreferences()
        let color = QuickLookBackgroundColor(
            red: 0.1,
            green: 0.2,
            blue: 0.3
        )

        XCTAssertEqual(
            AppSettings.loadQuickLookBackgroundColor(from: preferences),
            .defaultColor
        )

        AppSettings.saveQuickLookBackgroundColor(color, to: preferences)

        XCTAssertEqual(
            AppSettings.loadQuickLookBackgroundColor(from: preferences),
            color
        )
    }

    func testQuickLookBackgroundColorFallsBackForInvalidColor() {
        let preferences = InMemoryPreferences()
        preferences.set(
            [1.1, 0.2, 0.3],
            forKey: AppSettings.quickLookBackgroundColorComponentsKey
        )

        let color = AppSettings.loadQuickLookBackgroundColor(from: preferences)

        XCTAssertEqual(
            color.colorComponents,
            QuickLookBackgroundColor.defaultColor.colorComponents
        )
    }

    func testQuickLookBackgroundColorMigratesLegacyBorderColor() {
        let preferences = InMemoryPreferences()
        preferences.set([0.1, 0.2, 0.3], forKey: "quickLookBorderColorComponents")

        XCTAssertEqual(
            AppSettings.loadQuickLookBackgroundColor(from: preferences),
            QuickLookBackgroundColor(red: 0.1, green: 0.2, blue: 0.3)
        )
    }

    func testAddingAndRemovingTabsKeepsSelectionValid() {
        let context = makeContext()

        context.viewModel.addTab()
        let addedTabID = context.viewModel.selectedTabID

        XCTAssertEqual(context.viewModel.tabs.count, 2)
        XCTAssertEqual(context.viewModel.tabs.last?.name, "Folder 2")

        context.viewModel.removeTab(id: addedTabID!)

        XCTAssertEqual(context.viewModel.tabs, context.initialTabs)
        XCTAssertEqual(context.viewModel.selectedTabID, context.initialTabs.first?.id)
    }

    func testChoosingFolderUpdatesDraftWithoutSavingTabs() {
        let folderURL = URL(fileURLWithPath: "/tmp/Images")
        let folderChooser = TestFolderChooser(folderURL: folderURL)
        let context = makeContext(folderChooser: folderChooser)
        let tabID = context.initialTabs[0].id

        context.viewModel.chooseFolder(for: tabID)

        XCTAssertEqual(context.viewModel.tabs[0].folderPath, folderURL.path)
        XCTAssertEqual(context.tabManager.tabs, context.initialTabs)
    }

    func testMovingFolderChangesDraftOrderAndSavePersistsIt() {
        let context = makeContext()
        context.viewModel.addTab()
        context.viewModel.addTab()
        let movedFolder = context.viewModel.tabs[2]
        let firstFolder = context.viewModel.tabs[0]

        context.viewModel.moveTab(id: movedFolder.id, to: firstFolder.id)

        XCTAssertEqual(
            context.viewModel.tabs.map(\.name),
            ["Folder 3", "First", "Folder 2"]
        )
        XCTAssertEqual(context.viewModel.selectedTabID, movedFolder.id)
        XCTAssertEqual(context.tabManager.tabs, context.initialTabs)

        XCTAssertTrue(context.viewModel.save())
        XCTAssertEqual(context.tabManager.tabs, context.viewModel.tabs)
    }

    func testSuccessfulSaveAppliesAllSettings() {
        let context = makeContext()
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        context.viewModel.shortcut = shortcut
        context.viewModel.language = .japanese
        context.viewModel.scaleImagesWithWindow = false
        context.viewModel.displayedFileExtensions = ["png", "pdf"]
        context.viewModel.automaticallyChecksForUpdates = false
        context.viewModel.updateCheckFrequency = .monthly
        context.viewModel.quickLookBackgroundColor = QuickLookBackgroundColor(
            red: 0.1,
            green: 0.2,
            blue: 0.3
        )
        context.viewModel.addTab()

        XCTAssertTrue(context.viewModel.save())

        XCTAssertEqual(context.localization.language, .japanese)
        XCTAssertEqual(context.tabManager.tabs, context.viewModel.tabs)
        XCTAssertEqual(context.tabManager.selectedTabID, context.viewModel.selectedTabID)
        XCTAssertEqual(context.shortcutRegistrar.registeredShortcut, shortcut)
        XCTAssertEqual(context.appPreferences.shortcut, shortcut)
        XCTAssertEqual(KeyboardShortcut.load(from: context.preferences), shortcut)
        XCTAssertFalse(context.appPreferences.scaleImagesWithWindow)
        XCTAssertFalse(AppSettings.loadScaleImagesWithWindow(from: context.preferences))
        XCTAssertEqual(context.appPreferences.displayedFileExtensions, ["png", "pdf"])
        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: context.preferences),
            ["png", "pdf"]
        )
        XCTAssertEqual(
            context.appPreferences.quickLookBackgroundColor,
            context.viewModel.quickLookBackgroundColor
        )
        XCTAssertEqual(
            AppSettings.loadQuickLookBackgroundColor(from: context.preferences),
            context.viewModel.quickLookBackgroundColor
        )
        XCTAssertFalse(context.updateSettings.automaticallyChecksForUpdates)
        XCTAssertEqual(context.updateSettings.updateCheckFrequency, .monthly)
    }

    func testDraftStartsFromSavedSettings() {
        let preferences = InMemoryPreferences()
        let appPreferences = AppPreferences(userDefaults: preferences)
        appPreferences.setScaleImagesWithWindow(false)
        appPreferences.setDisplayedFileExtensions(["txt"])
        let updateSettings = TestUpdateSettings(
            automaticallyChecksForUpdates: false,
            updateCheckFrequency: .daily
        )

        let context = makeContext(
            preferences: preferences,
            appPreferences: appPreferences,
            updateSettings: updateSettings
        )

        XCTAssertFalse(context.viewModel.scaleImagesWithWindow)
        XCTAssertEqual(context.viewModel.displayedFileExtensions, ["txt"])
        XCTAssertFalse(context.viewModel.automaticallyChecksForUpdates)
        XCTAssertEqual(context.viewModel.updateCheckFrequency, .daily)
        XCTAssertEqual(context.viewModel.tabs, context.initialTabs)
        XCTAssertEqual(context.viewModel.selectedTabID, context.initialTabs[0].id)
    }

    func testImageScalingDraftIsNotAppliedBeforeSave() {
        let context = makeContext()

        context.viewModel.scaleImagesWithWindow = false
        context.viewModel.displayedFileExtensions = ["png"]
        context.viewModel.automaticallyChecksForUpdates = false
        context.viewModel.updateCheckFrequency = .daily
        context.viewModel.quickLookBackgroundColor = QuickLookBackgroundColor(
            red: 0.1,
            green: 0.2,
            blue: 0.3
        )

        assertSavedSettingsAreUnchanged(context)
        XCTAssertTrue(context.updateSettings.automaticallyChecksForUpdates)
        XCTAssertEqual(context.updateSettings.updateCheckFrequency, .weekly)
    }

    func testRegistrationFailureDoesNotApplyDraft() {
        let shortcutRegistrar = TestShortcutRegistrar(shouldRegister: false)
        let context = makeContext(shortcutRegistrar: shortcutRegistrar)
        context.viewModel.language = .japanese
        context.viewModel.scaleImagesWithWindow = false
        context.viewModel.displayedFileExtensions = ["png"]
        context.viewModel.quickLookBackgroundColor = QuickLookBackgroundColor(
            red: 0.1,
            green: 0.2,
            blue: 0.3
        )
        context.viewModel.addTab()

        XCTAssertFalse(context.viewModel.save())

        XCTAssertEqual(context.localization.language, .english)
        XCTAssertEqual(context.tabManager.tabs, context.initialTabs)
        assertSavedSettingsAreUnchanged(context)
        XCTAssertNotNil(context.viewModel.errorMessage)
    }

    private func assertSavedSettingsAreUnchanged(
        _ context: TestContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(context.appPreferences.scaleImagesWithWindow, file: file, line: line)
        XCTAssertTrue(
            AppSettings.loadScaleImagesWithWindow(from: context.preferences),
            file: file,
            line: line
        )
        XCTAssertEqual(
            context.appPreferences.displayedFileExtensions,
            AppSettings.defaultDisplayedFileExtensions,
            file: file,
            line: line
        )
        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: context.preferences),
            AppSettings.defaultDisplayedFileExtensions,
            file: file,
            line: line
        )
        XCTAssertEqual(
            context.appPreferences.quickLookBackgroundColor,
            .defaultColor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            AppSettings.loadQuickLookBackgroundColor(from: context.preferences),
            .defaultColor,
            file: file,
            line: line
        )
    }

    private func makeContext(
        shortcutRegistrar: TestShortcutRegistrar? = nil,
        folderChooser: TestFolderChooser? = nil,
        preferences: InMemoryPreferences? = nil,
        appPreferences: AppPreferences? = nil,
        updateSettings: TestUpdateSettings? = nil
    ) -> TestContext {
        let shortcutRegistrar = shortcutRegistrar ?? TestShortcutRegistrar()
        let folderChooser = folderChooser ?? TestFolderChooser()
        let preferences = preferences ?? InMemoryPreferences()
        let appPreferences = appPreferences ?? AppPreferences(userDefaults: preferences)
        let updateSettings = updateSettings ?? TestUpdateSettings()
        preferences.set(AppLanguage.english.rawValue, forKey: AppSettings.languageKey)
        let localization = LocalizationManager(userDefaults: preferences)
        let tabManager = FolderTabManager(userDefaults: preferences)
        let initialTabs = [FolderTab(name: "First", folderPath: "/tmp/First")]
        tabManager.replaceTabs(initialTabs, selectedTabID: initialTabs[0].id)
        let viewModel = SettingsViewModel(
            preferences: appPreferences,
            localization: localization,
            tabManager: tabManager,
            updateSettings: updateSettings,
            shortcutRegistrar: shortcutRegistrar,
            folderChooser: folderChooser,
            onReloadCurrentTab: {},
            onToggleWindow: {}
        )
        return TestContext(
            viewModel: viewModel,
            localization: localization,
            tabManager: tabManager,
            initialTabs: initialTabs,
            shortcutRegistrar: shortcutRegistrar,
            preferences: preferences,
            appPreferences: appPreferences,
            updateSettings: updateSettings
        )
    }
}

@MainActor
private struct TestContext {
    let viewModel: SettingsViewModel
    let localization: LocalizationManager
    let tabManager: FolderTabManager
    let initialTabs: [FolderTab]
    let shortcutRegistrar: TestShortcutRegistrar
    let preferences: InMemoryPreferences
    let appPreferences: AppPreferences
    let updateSettings: TestUpdateSettings
}

@MainActor
private final class TestUpdateSettings: UpdateSettingsManaging {
    private(set) var automaticallyChecksForUpdates: Bool
    private(set) var updateCheckFrequency: UpdateCheckFrequency

    init(
        automaticallyChecksForUpdates: Bool = true,
        updateCheckFrequency: UpdateCheckFrequency = .weekly
    ) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.updateCheckFrequency = updateCheckFrequency
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        automaticallyChecksForUpdates = isEnabled
    }

    func setUpdateCheckFrequency(_ frequency: UpdateCheckFrequency) {
        updateCheckFrequency = frequency
    }
}

private final class TestShortcutRegistrar: ShortcutRegistering {
    private let shouldRegister: Bool
    private(set) var registeredShortcut: KeyboardShortcut?

    init(shouldRegister: Bool = true) {
        self.shouldRegister = shouldRegister
    }

    func registerShortcut(
        _ shortcut: KeyboardShortcut,
        action: @escaping @MainActor () -> Void
    ) -> Bool {
        guard shouldRegister else {
            return false
        }
        registeredShortcut = shortcut
        return true
    }
}

@MainActor
private final class TestFolderChooser: FolderChoosing {
    private let folderURL: URL?

    init(folderURL: URL? = nil) {
        self.folderURL = folderURL
    }

    func chooseFolder(initialURL: URL?) -> URL? {
        folderURL
    }
}
