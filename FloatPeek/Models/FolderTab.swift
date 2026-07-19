import Combine
import Foundation

struct FolderTab: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var folderPath: String

    init(id: UUID = UUID(), name: String = "", folderPath: String = "") {
        self.id = id
        self.name = name
        self.folderPath = folderPath
    }

    @MainActor
    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        if let folderURL {
            return folderURL.lastPathComponent
        }

        return localized("Untitled Tab")
    }

    var folderURL: URL? {
        guard !folderPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: folderPath)
    }
}

@MainActor
final class FolderTabManager: ObservableObject {
    @Published private(set) var tabs: [FolderTab]
    @Published private(set) var selectedTabID: FolderTab.ID?

    var selectedTab: FolderTab? {
        tabs.first { $0.id == selectedTabID }
    }

    private let userDefaults: PreferencesStoring

    init(userDefaults: PreferencesStoring = AppEnvironment.preferences) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: AppSettings.folderTabsKey),
           let savedTabs = try? JSONDecoder().decode([FolderTab].self, from: data) {
            tabs = savedTabs
        } else if let legacyPath = userDefaults.string(forKey: AppSettings.selectedFolderPathKey),
                  !legacyPath.isEmpty {
            let folderURL = URL(fileURLWithPath: legacyPath)
            tabs = [FolderTab(name: folderURL.lastPathComponent, folderPath: legacyPath)]
        } else {
            tabs = [FolderTab()]
        }

        if let selectedIDString = userDefaults.string(forKey: AppSettings.selectedFolderTabIDKey),
           let selectedID = UUID(uuidString: selectedIDString),
           tabs.contains(where: { $0.id == selectedID }) {
            selectedTabID = selectedID
        } else {
            selectedTabID = tabs.first?.id
        }

        persist()
    }

    func selectTab(id: FolderTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else {
            return
        }

        selectedTabID = id
        persistSelectedTab()
    }

    func replaceTabs(_ newTabs: [FolderTab], selectedTabID: FolderTab.ID?) {
        tabs = newTabs

        if let selectedTabID,
           newTabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = selectedTabID
        } else {
            self.selectedTabID = newTabs.first?.id
        }

        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tabs) {
            userDefaults.set(data, forKey: AppSettings.folderTabsKey)
        }
        persistSelectedTab()
    }

    private func persistSelectedTab() {
        userDefaults.set(selectedTabID?.uuidString, forKey: AppSettings.selectedFolderTabIDKey)
    }
}
