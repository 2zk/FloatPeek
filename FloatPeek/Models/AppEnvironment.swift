import Foundation

protocol PreferencesStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func data(forKey defaultName: String) -> Data?
    func integer(forKey defaultName: String) -> Int
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: PreferencesStoring {}

final class InMemoryPreferences: PreferencesStoring {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        withLock { values[defaultName] }
    }

    func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    func integer(forKey defaultName: String) -> Int {
        object(forKey: defaultName) as? Int ?? 0
    }

    func set(_ value: Any?, forKey defaultName: String) {
        withLock {
            values[defaultName] = value
        }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

enum AppEnvironment {
    nonisolated(unsafe) static let preferences = makePreferences()

    static var isRunningTests: Bool {
        isRunningTests(environment: ProcessInfo.processInfo.environment)
    }

    static func makePreferences(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PreferencesStoring {
        isRunningTests(environment: environment)
            ? InMemoryPreferences()
            : UserDefaults.standard
    }

    static func isRunningTests(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
