import AppKit
import Foundation

final class FolderManager {
    @MainActor
    func chooseFolder(initialURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = initialURL
        panel.prompt = localized("Choose")
        panel.message = localized("Choose a folder for FloatPeek.")

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return nil
        }

        return folderURL
    }
}
