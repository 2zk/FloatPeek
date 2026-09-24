import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var isShowingSettings = false
    /// メインウィンドウが画面に表示されているか。起動時は SwiftUI が表示する
    @Published private(set) var isWindowVisible = true

    func requestSettings() {
        isShowingSettings = true
    }

    func dismissSettings() {
        isShowingSettings = false
    }

    func windowBecameVisible() {
        isWindowVisible = true
    }

    func windowBecameHidden() {
        isWindowVisible = false
    }
}
