import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var isShowingSettings = false
    @Published private(set) var windowVisibleRevision = 0
    @Published private(set) var windowHiddenRevision = 0

    func requestSettings() {
        isShowingSettings = true
    }

    func windowBecameVisible() {
        windowVisibleRevision += 1
    }

    func windowBecameHidden() {
        windowHiddenRevision += 1
    }
}
