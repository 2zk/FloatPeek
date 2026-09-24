import AppKit
import XCTest
@testable import FloatPeek

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testSettingsRequestUpdatesPresentationState() {
        let coordinator = AppCoordinator()

        coordinator.requestSettings()

        XCTAssertTrue(coordinator.isShowingSettings)
    }

    func testDismissingSettingsClearsPresentationState() {
        let coordinator = AppCoordinator()
        coordinator.requestSettings()

        coordinator.dismissSettings()

        XCTAssertFalse(coordinator.isShowingSettings)
    }

    func testWindowVisibilityFollowsLatestChange() {
        let coordinator = AppCoordinator()
        XCTAssertTrue(coordinator.isWindowVisible)

        coordinator.windowBecameHidden()
        XCTAssertFalse(coordinator.isWindowVisible)

        coordinator.windowBecameVisible()
        XCTAssertTrue(coordinator.isWindowVisible)
    }

    func testWindowManagerReportsMiniaturizeAndRestoreToCoordinator() {
        let coordinator = AppCoordinator()
        let windowManager = WindowManager(
            userDefaults: InMemoryPreferences(),
            coordinator: coordinator
        )

        windowManager.windowDidMiniaturize(
            Notification(name: NSWindow.didMiniaturizeNotification)
        )
        XCTAssertFalse(coordinator.isWindowVisible)

        windowManager.windowDidDeminiaturize(
            Notification(name: NSWindow.didDeminiaturizeNotification)
        )
        XCTAssertTrue(coordinator.isWindowVisible)
    }
}
