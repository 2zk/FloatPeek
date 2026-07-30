import Combine
import XCTest
@testable import FloatPeek

@MainActor
final class UpdateManagerTests: XCTestCase {
    func testCheckForUpdatesInvokesDriverOnceWhenAvailable() {
        let driver = FakeUpdateDriver(canCheckForUpdates: true)
        let manager = UpdateManager(driver: driver)

        manager.checkForUpdates()

        XCTAssertEqual(driver.checkForUpdatesCallCount, 1)
    }

    func testCheckForUpdatesDoesNotInvokeDriverWhenUnavailable() {
        let driver = FakeUpdateDriver(canCheckForUpdates: false)
        let manager = UpdateManager(driver: driver)

        manager.checkForUpdates()

        XCTAssertEqual(driver.checkForUpdatesCallCount, 0)
    }

    func testAvailabilityFollowsDriver() {
        let driver = FakeUpdateDriver(canCheckForUpdates: false)
        let manager = UpdateManager(driver: driver)

        driver.canCheckForUpdates = true

        XCTAssertTrue(manager.canCheckForUpdates)
    }

    func testAppBundleUsesApprovalRequiredUpdateConfiguration() {
        let info = Bundle.main.infoDictionary

        XCTAssertEqual(
            info?["SUFeedURL"] as? String,
            "https://github.com/2zk/FloatPeek/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            info?["SUPublicEDKey"] as? String,
            "dmTOB/jzQBIFxfaVKLgl/NhxFUkGL0Bfaqo877brDbg="
        )
        XCTAssertEqual(info?["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info?["SUScheduledCheckInterval"] as? Int, 86_400)
        XCTAssertEqual(info?["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info?["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertEqual(info?["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info?["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info?["SURequireSignedFeed"] as? Bool, true)
    }

    func testTestTargetBuildsForAppleSilicon() {
#if arch(arm64)
        XCTAssertTrue(true)
#else
        XCTFail("FloatPeek v2.0.0 must be built for arm64.")
#endif
    }
}

@MainActor
private final class FakeUpdateDriver: UpdateDriving {
    @Published var canCheckForUpdates: Bool
    private(set) var checkForUpdatesCallCount = 0

    init(canCheckForUpdates: Bool) {
        self.canCheckForUpdates = canCheckForUpdates
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable {
        $canCheckForUpdates.sink(receiveValue: handler)
    }
}
