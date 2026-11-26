import XCTest
@testable import FloatPeek

@MainActor
final class AutoHideControllerTests: XCTestCase {
    func testDoesNotScheduleWhenDisabled() {
        let context = makeContext(isEnabled: false)

        context.controller.appDidResignActive()

        XCTAssertTrue(context.scheduler.pending.isEmpty)
        XCTAssertEqual(context.hideCount, 0)
    }

    func testHidesAfterConfiguredDelayWhenAppResignsActive() {
        let context = makeContext(delaySeconds: 7)

        context.controller.appDidResignActive()

        XCTAssertEqual(context.scheduler.pending.map(\.delay), [7])
        context.scheduler.runNext()
        XCTAssertEqual(context.hideCount, 1)
        XCTAssertFalse(context.controller.isScheduled)
    }

    func testBecomingActiveCancelsPendingHide() {
        let context = makeContext()

        context.controller.appDidResignActive()
        context.controller.appDidBecomeActive()
        context.scheduler.runNext()

        XCTAssertEqual(context.hideCount, 0)
    }

    func testRetriesWhileWindowIsInUse() {
        let context = makeContext()
        context.state.canHide = false

        context.controller.appDidResignActive()
        context.scheduler.runNext()

        XCTAssertEqual(context.hideCount, 0)
        XCTAssertEqual(context.scheduler.pending.map(\.delay), [AutoHideController.retryInterval])

        context.state.canHide = true
        context.scheduler.runNext()

        XCTAssertEqual(context.hideCount, 1)
    }

    func testDisablingSettingCancelsPendingHide() {
        let context = makeContext()

        context.controller.appDidResignActive()
        context.preferences.setAutoHideEnabled(false)
        context.scheduler.runNext()

        XCTAssertEqual(context.hideCount, 0)
        XCTAssertFalse(context.controller.isScheduled)
    }

    func testResigningAgainRestartsTimer() {
        let context = makeContext()

        context.controller.appDidResignActive()
        context.controller.appDidResignActive()

        XCTAssertEqual(context.scheduler.pending.count, 1)
    }

    private func makeContext(
        isEnabled: Bool = true,
        delaySeconds: Int = 10
    ) -> TestContext {
        let preferences = AppPreferences(userDefaults: InMemoryPreferences())
        preferences.setAutoHideEnabled(isEnabled)
        preferences.setAutoHideDelaySeconds(delaySeconds)
        let scheduler = TestScheduler()
        let state = TestState()
        let controller = AutoHideController(
            preferences: preferences,
            scheduler: scheduler,
            canHide: { state.canHide },
            hide: { state.hideCount += 1 }
        )
        return TestContext(
            controller: controller,
            preferences: preferences,
            scheduler: scheduler,
            state: state
        )
    }
}

@MainActor
private struct TestContext {
    let controller: AutoHideController
    let preferences: AppPreferences
    let scheduler: TestScheduler
    let state: TestState

    var hideCount: Int {
        state.hideCount
    }
}

@MainActor
private final class TestState {
    var canHide = true
    var hideCount = 0
}

@MainActor
private final class TestScheduler: AutoHideScheduling {
    final class Entry: AutoHideCancellable {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false

        init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    private var entries: [Entry] = []

    var pending: [Entry] {
        entries.filter { !$0.isCancelled }
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> AutoHideCancellable {
        let entry = Entry(delay: delay, action: action)
        entries.append(entry)
        return entry
    }

    /// 次の未キャンセル予約を実行する
    func runNext() {
        guard let entry = pending.first else {
            return
        }
        entries.removeAll { $0 === entry }
        entry.action()
    }
}
