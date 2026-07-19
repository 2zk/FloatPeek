import AppKit

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private let windowSize = CGSize(width: 160, height: 600)
    private let userDefaults: PreferencesStoring
    private weak var managedWindow: NSWindow?

    private override init() {
        userDefaults = AppEnvironment.preferences
        super.init()
    }

    func configure(window: NSWindow) {
        let isNewWindow = managedWindow !== window
        managedWindow = window
        window.tabbingMode = .disallowed
        window.level = .floating
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.isReleasedWhenClosed = false
        window.delegate = self

        if isNewWindow {
            restoreSavedFrame(to: window)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveFrame(of: sender)
        notifyMonitoringShouldStop()
        sender.orderOut(nil)
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        notifyMonitoringShouldStop()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        notifyWindowBecameVisible()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func toggleWindow() {
        let window = resolvedWindow()

        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }

    func showWindow() {
        guard let window = resolvedWindow() else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        configure(window: window)
        applySavedOrDefaultFrame(to: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        notifyWindowBecameVisible()
    }

    func hideWindow() {
        guard let window = resolvedWindow() else {
            return
        }

        saveFrame(of: window)
        notifyMonitoringShouldStop()
        window.orderOut(nil)
    }

    private func notifyWindowBecameVisible() {
        AppCoordinator.shared.windowBecameVisible()
    }

    private func notifyMonitoringShouldStop() {
        QuickLookManager.shared.closePreviewIfVisible()
        AppCoordinator.shared.windowBecameHidden()
    }

    private func resolvedWindow() -> NSWindow? {
        if let managedWindow {
            return managedWindow
        }

        let window = NSApp.windows.first { window in
            window.contentViewController != nil || window.contentView != nil
        }

        if let window {
            configure(window: window)
        }

        return window
    }

    private func applySavedOrDefaultFrame(to window: NSWindow) {
        if restoreSavedFrame(to: window) {
            return
        }

        position(window: window)
        saveFrame(of: window)
    }

    @discardableResult
    private func restoreSavedFrame(to window: NSWindow) -> Bool {
        guard let frame = loadSavedFrame() else {
            return false
        }

        window.setFrame(adjustedFrame(frame), display: true)
        return true
    }

    private func loadSavedFrame() -> NSRect? {
        guard let frameString = userDefaults.string(forKey: AppSettings.windowFrameKey) else {
            return nil
        }

        let frame = NSRectFromString(frameString)
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }

        return frame
    }

    private func saveFrame(from notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        saveFrame(of: window)
    }

    private func saveFrame(of window: NSWindow) {
        userDefaults.set(NSStringFromRect(window.frame), forKey: AppSettings.windowFrameKey)
    }

    private func adjustedFrame(_ frame: NSRect) -> NSRect {
        let screen = screen(containing: frame) ?? targetScreen()
        let visibleFrame = screen.visibleFrame
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func position(window: NSWindow) {
        let visibleFrame = targetScreen().visibleFrame
        let width = min(windowSize.width, visibleFrame.width)
        let height = min(windowSize.height, visibleFrame.height)
        let frame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.maxY - height,
            width: width,
            height: height
        )

        window.setFrame(frame, display: true)
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.visibleFrame.intersects(frame)
        }
    }

    private func targetScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
