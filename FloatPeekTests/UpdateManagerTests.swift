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

    func testAutomaticUpdateChecksCanBeChanged() {
        let driver = FakeUpdateDriver(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true
        )
        let manager = UpdateManager(driver: driver)

        manager.setAutomaticallyChecksForUpdates(false)

        XCTAssertFalse(manager.automaticallyChecksForUpdates)
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
    }

    func testUpdateCheckFrequencyCanBeChanged() {
        let driver = FakeUpdateDriver(
            canCheckForUpdates: true,
            updateCheckInterval: UpdateCheckFrequency.weekly.rawValue
        )
        let manager = UpdateManager(driver: driver)

        manager.setUpdateCheckFrequency(.monthly)

        XCTAssertEqual(manager.updateCheckFrequency, .monthly)
        XCTAssertEqual(driver.updateCheckInterval, UpdateCheckFrequency.monthly.rawValue)
    }

    func testUnknownUpdateCheckIntervalUsesWeeklyFrequency() {
        let driver = FakeUpdateDriver(
            canCheckForUpdates: true,
            updateCheckInterval: 123
        )
        let manager = UpdateManager(driver: driver)

        XCTAssertEqual(manager.updateCheckFrequency, .weekly)
    }

    func testLastUpdateCheckDateFollowsDriver() {
        let driver = FakeUpdateDriver(canCheckForUpdates: true)
        let manager = UpdateManager(driver: driver)
        let date = Date(timeIntervalSinceReferenceDate: 123)

        driver.lastUpdateCheckDate = date

        XCTAssertEqual(manager.lastUpdateCheckDate, date)
    }

    func testUpdateRelaunchRequestsApplicationTermination() {
        var terminationRequestCount = 0
        let delegate = SparkleUpdateLifecycleDelegate {
            terminationRequestCount += 1
        }

        delegate.requestTerminationForRelaunch()

        XCTAssertEqual(terminationRequestCount, 1)
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
        XCTAssertEqual(info?["SUScheduledCheckInterval"] as? Int, 604_800)
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
    @Published var automaticallyChecksForUpdates: Bool
    @Published var updateCheckInterval: TimeInterval
    @Published var lastUpdateCheckDate: Date?
    private(set) var checkForUpdatesCallCount = 0

    init(
        canCheckForUpdates: Bool,
        automaticallyChecksForUpdates: Bool = true,
        updateCheckInterval: TimeInterval = UpdateCheckFrequency.weekly.rawValue,
        lastUpdateCheckDate: Date? = nil
    ) {
        self.canCheckForUpdates = canCheckForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.updateCheckInterval = updateCheckInterval
        self.lastUpdateCheckDate = lastUpdateCheckDate
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        automaticallyChecksForUpdates = isEnabled
    }

    func setUpdateCheckInterval(_ interval: TimeInterval) {
        updateCheckInterval = interval
    }

    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable {
        $canCheckForUpdates.sink(receiveValue: handler)
    }

    func observeAutomaticallyChecksForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable {
        $automaticallyChecksForUpdates.sink(receiveValue: handler)
    }

    func observeUpdateCheckInterval(
        _ handler: @escaping @MainActor (TimeInterval) -> Void
    ) -> AnyCancellable {
        $updateCheckInterval.sink(receiveValue: handler)
    }

    func observeLastUpdateCheckDate(
        _ handler: @escaping @MainActor (Date?) -> Void
    ) -> AnyCancellable {
        $lastUpdateCheckDate.sink(receiveValue: handler)
    }
}
