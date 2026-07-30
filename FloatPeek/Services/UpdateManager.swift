import Combine
import Foundation
import Sparkle

@MainActor
protocol UpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }

    func checkForUpdates()
    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable
}

@MainActor
final class SparkleUpdateDriver: UpdateDriving {
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    init(bundle: Bundle = .main) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
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

    func observeCanCheckForUpdates(
        _ handler: @escaping @MainActor (Bool) -> Void
    ) -> AnyCancellable {
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
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
final class UpdateManager: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool

    private let driver: any UpdateDriving
    private var canCheckForUpdatesObservation: AnyCancellable?

    init(driver: any UpdateDriving = SparkleUpdateDriver()) {
        self.driver = driver
        canCheckForUpdates = driver.canCheckForUpdates
        canCheckForUpdatesObservation = driver.observeCanCheckForUpdates { [weak self] canCheck in
            self?.canCheckForUpdates = canCheck
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            return
        }

        driver.checkForUpdates()
    }
}
