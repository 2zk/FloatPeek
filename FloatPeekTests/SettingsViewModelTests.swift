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

    func testDisplayedFileExtensionsDefaultToAllAndPersistEmptySelection() {
        let preferences = InMemoryPreferences()

        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: preferences),
            AppSettings.allSupportedFileExtensions
        )

        AppSettings.saveDisplayedFileExtensions([], to: preferences)

        XCTAssertEqual(AppSettings.loadDisplayedFileExtensions(from: preferences), [])
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
        context.viewModel.language = .japanese
        context.viewModel.scaleImagesWithWindow = false
        context.viewModel.displayedFileExtensions = ["png", "pdf"]
        context.viewModel.addTab()

        XCTAssertTrue(context.viewModel.save())

        XCTAssertEqual(context.localization.language, .japanese)
        XCTAssertEqual(context.tabManager.tabs, context.viewModel.tabs)
        XCTAssertEqual(context.tabManager.selectedTabID, context.viewModel.selectedTabID)
        XCTAssertEqual(context.shortcutRegistrar.registeredShortcut, context.viewModel.shortcut)
        XCTAssertFalse(AppSettings.loadScaleImagesWithWindow(from: context.preferences))
        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: context.preferences),
            ["png", "pdf"]
        )
        XCTAssertEqual(context.imageScalingRecorder.values, [false])
        XCTAssertEqual(context.fileExtensionsRecorder.values, [["png", "pdf"]])
    }

    func testImageScalingDraftIsNotAppliedBeforeSave() {
        let context = makeContext()

        context.viewModel.scaleImagesWithWindow = false
        context.viewModel.displayedFileExtensions = ["png"]

        XCTAssertTrue(AppSettings.loadScaleImagesWithWindow(from: context.preferences))
        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: context.preferences),
            AppSettings.allSupportedFileExtensions
        )
        XCTAssertTrue(context.imageScalingRecorder.values.isEmpty)
        XCTAssertTrue(context.fileExtensionsRecorder.values.isEmpty)
    }

    func testRegistrationFailureDoesNotApplyDraft() {
        let shortcutRegistrar = TestShortcutRegistrar(shouldRegister: false)
        let context = makeContext(shortcutRegistrar: shortcutRegistrar)
        context.viewModel.language = .japanese
        context.viewModel.scaleImagesWithWindow = false
        context.viewModel.displayedFileExtensions = ["png"]
        context.viewModel.addTab()

        XCTAssertFalse(context.viewModel.save())

        XCTAssertEqual(context.localization.language, .english)
        XCTAssertEqual(context.tabManager.tabs, context.initialTabs)
        XCTAssertTrue(AppSettings.loadScaleImagesWithWindow(from: context.preferences))
        XCTAssertEqual(
            AppSettings.loadDisplayedFileExtensions(from: context.preferences),
            AppSettings.allSupportedFileExtensions
        )
        XCTAssertTrue(context.imageScalingRecorder.values.isEmpty)
        XCTAssertTrue(context.fileExtensionsRecorder.values.isEmpty)
        XCTAssertNotNil(context.viewModel.errorMessage)
    }

    private func makeContext(
        shortcutRegistrar: TestShortcutRegistrar? = nil,
        folderChooser: TestFolderChooser? = nil
    ) -> TestContext {
        let shortcutRegistrar = shortcutRegistrar ?? TestShortcutRegistrar()
        let folderChooser = folderChooser ?? TestFolderChooser()
        let preferences = InMemoryPreferences()
        let imageScalingRecorder = TestImageScalingRecorder()
        let fileExtensionsRecorder = TestFileExtensionsRecorder()
        preferences.set(AppLanguage.english.rawValue, forKey: AppSettings.languageKey)
        let localization = LocalizationManager(userDefaults: preferences)
        let tabManager = FolderTabManager(userDefaults: preferences)
        let initialTabs = [FolderTab(name: "First", folderPath: "/tmp/First")]
        tabManager.replaceTabs(initialTabs, selectedTabID: initialTabs[0].id)
        let viewModel = SettingsViewModel(
            shortcut: AppSettings.defaultShortcut,
            language: localization.language,
            scaleImagesWithWindow: AppSettings.loadScaleImagesWithWindow(from: preferences),
            displayedFileExtensions: AppSettings.loadDisplayedFileExtensions(from: preferences),
            tabs: initialTabs,
            selectedTabID: initialTabs[0].id,
            localization: localization,
            tabManager: tabManager,
            shortcutRegistrar: shortcutRegistrar,
            folderChooser: folderChooser,
            userDefaults: preferences,
            onReloadCurrentTab: {},
            onToggleWindow: {},
            onScaleImagesWithWindowChange: imageScalingRecorder.record,
            onDisplayedFileExtensionsChange: fileExtensionsRecorder.record
        )
        return TestContext(
            viewModel: viewModel,
            localization: localization,
            tabManager: tabManager,
            initialTabs: initialTabs,
            shortcutRegistrar: shortcutRegistrar,
            preferences: preferences,
            imageScalingRecorder: imageScalingRecorder,
            fileExtensionsRecorder: fileExtensionsRecorder
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
    let imageScalingRecorder: TestImageScalingRecorder
    let fileExtensionsRecorder: TestFileExtensionsRecorder
}

@MainActor
private final class TestImageScalingRecorder {
    private(set) var values: [Bool] = []

    func record(_ isEnabled: Bool) {
        values.append(isEnabled)
    }
}

@MainActor
private final class TestFileExtensionsRecorder {
    private(set) var values: [Set<String>] = []

    func record(_ fileExtensions: Set<String>) {
        values.append(fileExtensions)
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
