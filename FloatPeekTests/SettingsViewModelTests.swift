import XCTest
@testable import FloatPeek

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testAddingAndRemovingTabsKeepsSelectionValid() {
        let context = makeContext()

        context.viewModel.addTab()
        let addedTabID = context.viewModel.selectedTabID

        XCTAssertEqual(context.viewModel.tabs.count, 2)
        XCTAssertEqual(context.viewModel.tabs.last?.name, "Tab 2")

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

    func testSuccessfulSaveAppliesAllSettings() {
        let context = makeContext()
        context.viewModel.language = .japanese
        context.viewModel.addTab()

        XCTAssertTrue(context.viewModel.save())

        XCTAssertEqual(context.localization.language, .japanese)
        XCTAssertEqual(context.tabManager.tabs, context.viewModel.tabs)
        XCTAssertEqual(context.tabManager.selectedTabID, context.viewModel.selectedTabID)
        XCTAssertEqual(context.shortcutRegistrar.registeredShortcut, context.viewModel.shortcut)
    }

    func testRegistrationFailureDoesNotApplyDraft() {
        let shortcutRegistrar = TestShortcutRegistrar(shouldRegister: false)
        let context = makeContext(shortcutRegistrar: shortcutRegistrar)
        context.viewModel.language = .japanese
        context.viewModel.addTab()

        XCTAssertFalse(context.viewModel.save())

        XCTAssertEqual(context.localization.language, .english)
        XCTAssertEqual(context.tabManager.tabs, context.initialTabs)
        XCTAssertNotNil(context.viewModel.errorMessage)
    }

    private func makeContext(
        shortcutRegistrar: TestShortcutRegistrar? = nil,
        folderChooser: TestFolderChooser? = nil
    ) -> TestContext {
        let shortcutRegistrar = shortcutRegistrar ?? TestShortcutRegistrar()
        let folderChooser = folderChooser ?? TestFolderChooser()
        let preferences = InMemoryPreferences()
        preferences.set(AppLanguage.english.rawValue, forKey: AppSettings.languageKey)
        let localization = LocalizationManager(userDefaults: preferences)
        let tabManager = FolderTabManager(userDefaults: preferences)
        let initialTabs = [FolderTab(name: "First", folderPath: "/tmp/First")]
        tabManager.replaceTabs(initialTabs, selectedTabID: initialTabs[0].id)
        let viewModel = SettingsViewModel(
            shortcut: AppSettings.defaultShortcut,
            language: localization.language,
            tabs: initialTabs,
            selectedTabID: initialTabs[0].id,
            localization: localization,
            tabManager: tabManager,
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
            shortcutRegistrar: shortcutRegistrar
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
