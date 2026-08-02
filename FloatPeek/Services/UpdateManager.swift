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

    init(bundle: Bundle = .main) {
        updaterDelegate = SparkleUpdateLifecycleDelegate()
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
    private let requestApplicationTermination: () -> Void

    init(requestApplicationTermination: @escaping () -> Void = {
        NSApp.terminate(nil)
    }) {
        self.requestApplicationTermination = requestApplicationTermination
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        requestTerminationForRelaunch()
    }

    func requestTerminationForRelaunch() {
        requestApplicationTermination()
    }
}

@MainActor
final class UpdateManager: ObservableObject {
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
