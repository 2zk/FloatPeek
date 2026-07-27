import Foundation

@MainActor
protocol ShortcutRegistering: AnyObject {
    @discardableResult
    func registerShortcut(
        _ shortcut: KeyboardShortcut,
        action: @escaping @MainActor () -> Void
    ) -> Bool
}

extension HotKeyManager: ShortcutRegistering {}

@MainActor
protocol FolderChoosing {
    func chooseFolder(initialURL: URL?) -> URL?
}

extension FolderManager: FolderChoosing {}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var shortcut: KeyboardShortcut
    @Published var language: AppLanguage
    @Published var tabs: [FolderTab]
    @Published var selectedTabID: FolderTab.ID?
    @Published private(set) var errorMessage: String?

    var canReloadCurrentTab: Bool {
        tabManager.selectedTab?.folderURL != nil
    }

    private let localization: LocalizationManager
    private let tabManager: FolderTabManager
    private let shortcutRegistrar: ShortcutRegistering
    private let folderChooser: FolderChoosing
    private let onReloadCurrentTab: @MainActor () -> Void
    private let onToggleWindow: @MainActor () -> Void

    init(
        shortcut: KeyboardShortcut,
        language: AppLanguage,
        tabs: [FolderTab],
        selectedTabID: FolderTab.ID?,
        localization: LocalizationManager,
        tabManager: FolderTabManager,
        shortcutRegistrar: ShortcutRegistering = HotKeyManager.shared,
        folderChooser: FolderChoosing,
        onReloadCurrentTab: @escaping @MainActor () -> Void,
        onToggleWindow: @escaping @MainActor () -> Void
    ) {
        self.shortcut = shortcut
        self.language = language
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.localization = localization
        self.tabManager = tabManager
        self.shortcutRegistrar = shortcutRegistrar
        self.folderChooser = folderChooser
        self.onReloadCurrentTab = onReloadCurrentTab
        self.onToggleWindow = onToggleWindow
    }

    func selectTab(id: FolderTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else {
            return
        }
        selectedTabID = id
    }

    func addTab() {
        let tab = FolderTab(
            name: localization.localizedFormat("Tab %d", tabs.count + 1)
        )
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func removeTab(id: FolderTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        }
    }

    func moveTab(id: FolderTab.ID, to targetID: FolderTab.ID) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex else {
            return
        }

        let movedTab = tabs.remove(at: sourceIndex)
        tabs.insert(movedTab, at: min(targetIndex, tabs.count))
    }

    func chooseFolder(for id: FolderTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              let folderURL = folderChooser.chooseFolder(initialURL: tabs[index].folderURL) else {
            return
        }

        tabs[index].folderPath = folderURL.path
        if tabs[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tabs[index].name = folderURL.lastPathComponent
        }
        selectedTabID = id
    }

    func restoreDefaultShortcut() {
        shortcut = AppSettings.defaultShortcut
        errorMessage = nil
    }

    func reloadCurrentTab() {
        guard canReloadCurrentTab else {
            return
        }
        onReloadCurrentTab()
    }

    @discardableResult
    func save() -> Bool {
        guard shortcut.isValid else {
            errorMessage = localization.localized("Unsupported shortcut.")
            return false
        }

        let didRegister = shortcutRegistrar.registerShortcut(shortcut, action: onToggleWindow)
        guard didRegister else {
            errorMessage = localization.localized(
                "Could not register this shortcut. It may already be used by another app."
            )
            return false
        }

        shortcut.save()
        localization.language = language
        tabManager.replaceTabs(tabs, selectedTabID: selectedTabID)
        errorMessage = nil
        return true
    }
}
