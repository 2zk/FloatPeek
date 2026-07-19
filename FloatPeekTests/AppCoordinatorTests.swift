import XCTest
@testable import FloatPeek

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testSettingsRequestUpdatesPresentationState() {
        let coordinator = AppCoordinator()

        coordinator.requestSettings()

        XCTAssertTrue(coordinator.isShowingSettings)
    }

    func testRepeatedVisibilityChangesProduceDistinctRevisions() {
        let coordinator = AppCoordinator()

        coordinator.windowBecameVisible()
        coordinator.windowBecameVisible()
        coordinator.windowBecameHidden()

        XCTAssertEqual(coordinator.windowVisibleRevision, 2)
        XCTAssertEqual(coordinator.windowHiddenRevision, 1)
    }
}
