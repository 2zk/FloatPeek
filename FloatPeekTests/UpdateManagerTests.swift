import AppKit
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

    func testUpdateRelaunchClosesSheetsBeforeRequestingApplicationTermination() {
        var events: [String] = []
        let scheduler = ImmediateRelaunchScheduler()
        let delegate = SparkleUpdateLifecycleDelegate(
            dismissSettings: { events.append("dismiss settings") },
            endAttachedSheets: { events.append("end sheets") },
            hasAttachedSheets: { false },
            schedule: scheduler.schedule,
            requestApplicationTermination: { events.append("request termination") }
        )

        delegate.requestTerminationForRelaunch()
        XCTAssertEqual(events, ["dismiss settings", "end sheets"])

        scheduler.runAll()
        XCTAssertEqual(
            events,
            ["dismiss settings", "end sheets", "end sheets", "request termination"]
        )
    }

    func testUpdateRelaunchWaitsUntilSheetIsGone() {
        var remainingSheetChecks = 2
        var terminationCount = 0
        let scheduler = ImmediateRelaunchScheduler()
        let delegate = SparkleUpdateLifecycleDelegate(
            dismissSettings: {},
            endAttachedSheets: {},
            hasAttachedSheets: {
                defer { remainingSheetChecks -= 1 }
                return remainingSheetChecks > 0
            },
            schedule: scheduler.schedule,
            requestApplicationTermination: { terminationCount += 1 }
        )

        delegate.requestTerminationForRelaunch()
        scheduler.runAll()

        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(
            scheduler.delays,
            [
                0,
                SparkleUpdateLifecycleDelegate.sheetRetryInterval,
                SparkleUpdateLifecycleDelegate.sheetRetryInterval
            ]
        )
    }

    func testUpdateRelaunchRequestsTerminationAfterRetryLimit() {
        var terminationCount = 0
        let scheduler = ImmediateRelaunchScheduler()
        let delegate = SparkleUpdateLifecycleDelegate(
            dismissSettings: {},
            endAttachedSheets: {},
            hasAttachedSheets: { true },
            schedule: scheduler.schedule,
            requestApplicationTermination: { terminationCount += 1 }
        )

        delegate.requestTerminationForRelaunch()
        scheduler.runAll()

        XCTAssertEqual(terminationCount, 1)
        XCTAssertEqual(scheduler.delays.count, SparkleUpdateLifecycleDelegate.maxSheetRetries + 1)
    }

    func testEndAttachedSheetsClosesSheetAttachedToWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        window.beginSheet(sheet)
        XCTAssertNotNil(window.attachedSheet)

        SparkleUpdateLifecycleDelegate.endAttachedSheets(in: [window])

        XCTAssertNil(window.attachedSheet)
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

/// 予約された処理を記録し、テストから順に実行する
@MainActor
private final class ImmediateRelaunchScheduler {
    private(set) var delays: [TimeInterval] = []
    private var pending: [@MainActor () -> Void] = []

    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        delays.append(delay)
        pending.append(action)
    }

    func runAll() {
        while !pending.isEmpty {
            pending.removeFirst()()
        }
    }
}
