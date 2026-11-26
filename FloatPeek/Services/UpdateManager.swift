import AppKit
import Combine
import Foundation
import Sparkle

enum UpdateCheckFrequency: TimeInterval, CaseIterable, Identifiable {
    case daily = 86_400
    case weekly = 604_800
    case monthly = 2_592_000

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .daily:
            "Daily"
        case .weekly:
            "Weekly"
        case .monthly:
            "Monthly"
        }
    }

    init(updateCheckInterval: TimeInterval) {
        self = Self.allCases.first { $0.rawValue == updateCheckInterval } ?? .weekly
    }
}

@MainActor
protocol UpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get }
    var updateCheckInterval: TimeInterval { get }
    var lastUpdateCheckDate: Date? { get }

    func checkForUpdates()
    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool)
    func setUpdateCheckInterval(_ interval: TimeInterval)
    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable
    func observeAutomaticallyChecksForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable
    func observeUpdateCheckInterval(
        _ handler: @escaping @MainActor (TimeInterval) -> Void
    ) -> AnyCancellable
    func observeLastUpdateCheckDate(
        _ handler: @escaping @MainActor (Date?) -> Void
    ) -> AnyCancellable
}

@MainActor
final class SparkleUpdateDriver: UpdateDriving {
    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate: SparkleUpdateLifecycleDelegate

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        updaterController.updater.automaticallyChecksForUpdates
    }

    var updateCheckInterval: TimeInterval {
        updaterController.updater.updateCheckInterval
    }

    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    init(bundle: Bundle = .main, coordinator: AppCoordinator = .shared) {
        updaterDelegate = SparkleUpdateLifecycleDelegate(
            dismissSettings: coordinator.dismissSettings
        )
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )

        if !AppEnvironment.isRunningTests,
           Self.hasValidConfiguration(bundle: bundle) {
            updaterController.startUpdater()
        }
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = isEnabled
    }

    func setUpdateCheckInterval(_ interval: TimeInterval) {
        updaterController.updater.updateCheckInterval = interval
    }

    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable {
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink(receiveValue: handler)
    }

    func observeUpdateCheckInterval(
        _ handler: @escaping @MainActor (TimeInterval) -> Void
    ) -> AnyCancellable {
        updaterController.updater
            .publisher(for: \.updateCheckInterval)
            .receive(on: RunLoop.main)
            .sink(receiveValue: handler)
    }

    func observeAutomaticallyChecksForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable {
        updaterController.updater
            .publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink(receiveValue: handler)
    }

    func observeLastUpdateCheckDate(
        _ handler: @escaping @MainActor (Date?) -> Void
    ) -> AnyCancellable {
        updaterController.updater
            .publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink(receiveValue: handler)
    }

    private static func hasValidConfiguration(bundle: Bundle) -> Bool {
        guard let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }

        return URL(string: feedURL)?.scheme == "https"
            && !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publicKey.contains("$(")
    }
}

@MainActor
final class SparkleUpdateLifecycleDelegate: NSObject, SPUUpdaterDelegate {
    /// シートが残っていた場合に終了要求を待つ間隔と回数
    static let sheetRetryInterval: TimeInterval = 0.2
    static let maxSheetRetries = 10

    private let dismissSettings: () -> Void
    private let endAttachedSheets: () -> Void
    private let hasAttachedSheets: () -> Bool
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let requestApplicationTermination: () -> Void

    init(
        dismissSettings: @escaping () -> Void,
        endAttachedSheets: @escaping () -> Void = {
            SparkleUpdateLifecycleDelegate.endAttachedSheets(in: NSApp.windows)
        },
        hasAttachedSheets: @escaping () -> Bool = {
            NSApp.windows.contains { $0.attachedSheet != nil }
        },
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated(action)
            }
        },
        requestApplicationTermination: @escaping () -> Void = {
            NSApp.terminate(nil)
        }
    ) {
        self.dismissSettings = dismissSettings
        self.endAttachedSheets = endAttachedSheets
        self.hasAttachedSheets = hasAttachedSheets
        self.schedule = schedule
        self.requestApplicationTermination = requestApplicationTermination
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        requestTerminationForRelaunch()
    }

    /// シートが開いていると AppKit が終了を中止するため、閉じてから終了を要求する
    func requestTerminationForRelaunch() {
        dismissSettings()
        endAttachedSheets()
        schedule(0) { [weak self] in
            self?.requestTerminationWhenSheetsClosed(remainingRetries: Self.maxSheetRetries)
        }
    }

    /// 開いているシートを、シート上のシートから順に閉じる
    static func endAttachedSheets(in windows: [NSWindow]) {
        for window in windows {
            endAttachedSheet(of: window)
        }
    }

    private static func endAttachedSheet(of window: NSWindow) {
        guard let sheet = window.attachedSheet else {
            return
        }

        endAttachedSheet(of: sheet)
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }

    private func requestTerminationWhenSheetsClosed(remainingRetries: Int) {
        endAttachedSheets()

        guard hasAttachedSheets(), remainingRetries > 0 else {
            requestApplicationTermination()
            return
        }

        schedule(Self.sheetRetryInterval) { [weak self] in
            self?.requestTerminationWhenSheetsClosed(remainingRetries: remainingRetries - 1)
        }
    }
}

/// 設定画面から更新確認の設定を読み書きするためのインターフェース
@MainActor
protocol UpdateSettingsManaging: AnyObject {
    var automaticallyChecksForUpdates: Bool { get }
    var updateCheckFrequency: UpdateCheckFrequency { get }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool)
    func setUpdateCheckFrequency(_ frequency: UpdateCheckFrequency)
}

@MainActor
final class UpdateManager: ObservableObject, UpdateSettingsManaging {
    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var updateCheckFrequency: UpdateCheckFrequency
    @Published private(set) var lastUpdateCheckDate: Date?

    private let driver: any UpdateDriving
    private var canCheckForUpdatesObservation: AnyCancellable?
    private var automaticallyChecksForUpdatesObservation: AnyCancellable?
    private var updateCheckIntervalObservation: AnyCancellable?
    private var lastUpdateCheckDateObservation: AnyCancellable?

    init(driver: any UpdateDriving = SparkleUpdateDriver()) {
        self.driver = driver
        canCheckForUpdates = driver.canCheckForUpdates
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        updateCheckFrequency = UpdateCheckFrequency(
            updateCheckInterval: driver.updateCheckInterval
        )
        lastUpdateCheckDate = driver.lastUpdateCheckDate
        canCheckForUpdatesObservation = driver.observeCanCheckForUpdates { [weak self] canCheck in
            self?.canCheckForUpdates = canCheck
        }
        automaticallyChecksForUpdatesObservation = driver.observeAutomaticallyChecksForUpdates {
            [weak self] isEnabled in
            self?.automaticallyChecksForUpdates = isEnabled
        }
        updateCheckIntervalObservation = driver.observeUpdateCheckInterval { [weak self] interval in
            self?.updateCheckFrequency = UpdateCheckFrequency(updateCheckInterval: interval)
        }
        lastUpdateCheckDateObservation = driver.observeLastUpdateCheckDate { [weak self] date in
            self?.lastUpdateCheckDate = date
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            return
        }

        driver.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        driver.setAutomaticallyChecksForUpdates(isEnabled)
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
    }

    func setUpdateCheckFrequency(_ frequency: UpdateCheckFrequency) {
        driver.setUpdateCheckInterval(frequency.rawValue)
        updateCheckFrequency = UpdateCheckFrequency(
            updateCheckInterval: driver.updateCheckInterval
        )
    }
}
