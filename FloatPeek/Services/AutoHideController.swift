import Combine
import Foundation

@MainActor
protocol AutoHideCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol AutoHideScheduling {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> AutoHideCancellable
}

/// Task.sleep で遅延実行する本番用スケジューラ
@MainActor
struct TaskAutoHideScheduler: AutoHideScheduling {
    private final class ScheduledTask: AutoHideCancellable {
        let task: Task<Void, Never>

        init(task: Task<Void, Never>) {
            self.task = task
        }

        func cancel() {
            task.cancel()
        }
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> AutoHideCancellable {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            action()
        }
        return ScheduledTask(task: task)
    }
}

/// アプリが非アクティブになってから設定秒数後にウィンドウを隠す
@MainActor
final class AutoHideController {
    /// 隠せない状態だったときに再判定するまでの秒数
    static let retryInterval: TimeInterval = 1

    private let preferences: AppPreferences
    private let scheduler: AutoHideScheduling
    private let canHide: @MainActor () -> Bool
    private let hide: @MainActor () -> Void
    private var scheduledTask: AutoHideCancellable?
    private var enabledObservation: AnyCancellable?

    var isScheduled: Bool {
        scheduledTask != nil
    }

    init(
        preferences: AppPreferences,
        scheduler: AutoHideScheduling = TaskAutoHideScheduler(),
        canHide: @escaping @MainActor () -> Bool,
        hide: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.scheduler = scheduler
        self.canHide = canHide
        self.hide = hide
        enabledObservation = preferences.$autoHideEnabled
            .dropFirst()
            .sink { [weak self] isEnabled in
                MainActor.assumeIsolated {
                    if !isEnabled {
                        self?.cancel()
                    }
                }
            }
    }

    func appDidResignActive() {
        guard preferences.autoHideEnabled else {
            cancel()
            return
        }

        schedule(after: TimeInterval(preferences.autoHideDelaySeconds))
    }

    func appDidBecomeActive() {
        cancel()
    }

    func cancel() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }

    private func schedule(after delay: TimeInterval) {
        cancel()
        scheduledTask = scheduler.schedule(after: delay) { [weak self] in
            self?.fire()
        }
    }

    private func fire() {
        scheduledTask = nil
        guard preferences.autoHideEnabled else {
            return
        }

        guard canHide() else {
            schedule(after: Self.retryInterval)
            return
        }

        hide()
    }
}
