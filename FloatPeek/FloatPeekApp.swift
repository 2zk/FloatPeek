import AppKit
import SwiftUI

@main
struct FloatPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var tabManager = FolderTabManager()
    @StateObject private var appCoordinator = AppCoordinator.shared
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        Window("FloatPeek", id: "main") {
            ContentView()
                .frame(minWidth: 160, minHeight: 480)
                .environmentObject(localization)
                .environmentObject(tabManager)
                .environmentObject(appCoordinator)
                .environmentObject(updateManager)
                .environment(\.locale, localization.locale)
        }
        .defaultSize(width: 160, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button(localization.localized("Check for Updates…")) {
                    updateManager.checkForUpdates()
                }
                .disabled(!updateManager.canCheckForUpdates)
            }

            CommandGroup(replacing: .appSettings) {
                Button(localization.localized("Settings…")) {
                    WindowManager.shared.showWindow()
                    appCoordinator.requestSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillHide(_ notification: Notification) {
        QuickLookManager.shared.closePreviewIfVisible()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else {
            return
        }

        let shortcut = KeyboardShortcut.load()
        let didRegisterShortcut = HotKeyManager.shared.registerShortcut(shortcut) {
            WindowManager.shared.toggleWindow()
        }

        guard !didRegisterShortcut else {
            return
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = localized("Global shortcut unavailable")
            alert.informativeText = LocalizationManager.shared.localizedFormat(
                "%@ could not be registered. Choose another shortcut in Settings.",
                shortcut.displayName
            )
            alert.addButton(withTitle: localized("OK"))
            alert.runModal()
        }
    }
}
