import CoreServices
import Darwin
import Foundation

protocol FolderMonitoring: AnyObject, Sendable {
    @discardableResult
    func startMonitoring(
        folderURL: URL,
        displayedFileExtensions: Set<String>,
        onChange: @escaping @Sendable () -> Void
    ) async -> Bool
    func stopMonitoring() async
}

final class FolderMonitor: FolderMonitoring, @unchecked Sendable {
    private static let eventCallback: FSEventStreamCallback = {
        _, callbackInfo, eventCount, eventPaths, eventFlags, _ in
        guard let callbackInfo else {
            return
        }

        let monitor = Unmanaged<FolderMonitor>
            .fromOpaque(callbackInfo)
            .takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        let flags = Array(
            UnsafeBufferPointer(start: eventFlags, count: eventCount)
        )
        monitor.handleEvents(paths: paths, flags: flags)
    }

    private let eventQueue = DispatchQueue(label: "com.floatpeek.FloatPeek.folder-monitor")
    private let eventQueueKey = DispatchSpecificKey<UInt8>()
    private let debounceInterval: TimeInterval
    private let eventLatency: CFTimeInterval
    private var stream: FSEventStreamRef?
    private var rootEventSource: DispatchSourceFileSystemObject?
    private var monitoredFolderPath: String?
    private var monitoredFiles: Set<URL> = []
    private var displayedFileExtensions: Set<String> = []
    private var changeHandler: (@Sendable () -> Void)?
    private var pendingChange: DispatchWorkItem?

    init(
        debounceInterval: TimeInterval = 0.5,
        eventLatency: CFTimeInterval = 0.1
    ) {
        self.debounceInterval = debounceInterval
        self.eventLatency = eventLatency
        eventQueue.setSpecific(key: eventQueueKey, value: 1)
    }

    deinit {
        if DispatchQueue.getSpecific(key: eventQueueKey) != nil {
            stopMonitoringOnQueue()
        } else {
            eventQueue.sync {
                stopMonitoringOnQueue()
            }
        }
    }

    @discardableResult
    func startMonitoring(
        folderURL: URL,
        displayedFileExtensions: Set<String>,
        onChange: @escaping @Sendable () -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            eventQueue.async { [self] in
                continuation.resume(
                    returning: startMonitoringOnQueue(
                        folderURL: folderURL,
                        displayedFileExtensions: displayedFileExtensions,
                        onChange: onChange
                    )
                )
            }
        }
    }

    func stopMonitoring() async {
        await withCheckedContinuation { continuation in
            eventQueue.async { [self] in
                stopMonitoringOnQueue()
                continuation.resume()
            }
        }
    }

    private func startMonitoringOnQueue(
        folderURL: URL,
        displayedFileExtensions: Set<String>,
        onChange: @escaping @Sendable () -> Void
    ) -> Bool {
        stopMonitoringOnQueue()

        let standardizedFolderURL = folderURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: standardizedFolderURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return false
        }

        monitoredFolderPath = standardizedFolderURL.path
        monitoredFiles = []
        self.displayedFileExtensions = displayedFileExtensions
        changeHandler = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            Self.eventCallback,
            &context,
            [standardizedFolderURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            eventLatency,
            flags
        ) else {
            clearState()
            return false
        }

        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            clearState()
            return false
        }

        self.stream = stream
        startMonitoringRoot(at: standardizedFolderURL.path)
        monitoredFiles = loadMonitoredFiles(in: standardizedFolderURL) ?? []
        return true
    }

    private func stopMonitoringOnQueue() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        rootEventSource?.cancel()
        rootEventSource = nil
        clearState()
    }

    private func handleEvents(
        paths: [String],
        flags: [FSEventStreamEventFlags]
    ) {
        guard paths.indices.contains(where: { index in
            flags.indices.contains(index) && isRelevantEvent(
                path: paths[index],
                flags: flags[index]
            )
        }) else {
            return
        }

        refreshMonitoredFiles()
        scheduleChange()
    }

    private func scheduleChange() {
        guard pendingChange == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingChange = nil
            self.changeHandler?()
        }
        pendingChange = workItem
        eventQueue.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }

    private func startMonitoringRoot(at path: String) {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: eventQueue
        )
        source.setEventHandler { [weak self] in
            self?.handleRootEvent()
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        rootEventSource = source
        source.resume()
    }

    private func handleRootEvent() {
        guard let monitoredFolderPath else {
            return
        }

        let folderURL = URL(fileURLWithPath: monitoredFolderPath)
        guard let updatedFiles = loadMonitoredFiles(in: folderURL) else {
            scheduleChange()
            return
        }

        guard updatedFiles != monitoredFiles else {
            return
        }

        monitoredFiles = updatedFiles
        scheduleChange()
    }

    private func refreshMonitoredFiles() {
        guard let monitoredFolderPath,
              let updatedFiles = loadMonitoredFiles(
                in: URL(fileURLWithPath: monitoredFolderPath)
              ) else {
            return
        }

        monitoredFiles = updatedFiles
    }

    private func loadMonitoredFiles(
        in folderURL: URL
    ) -> Set<URL>? {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return Set(fileURLs.compactMap { fileURL in
            guard displayedFileExtensions.contains(
                fileURL.pathExtension.lowercased()
            ), !fileURL.hasDirectoryPath else {
                return nil
            }

            return fileURL.standardizedFileURL
        })
    }

    private func isRelevantEvent(
        path: String,
        flags: FSEventStreamEventFlags
    ) -> Bool {
        guard let monitoredFolderPath else {
            return false
        }

        let eventURL = URL(fileURLWithPath: path).standardizedFileURL
        if eventURL.path == monitoredFolderPath {
            return flags & FSEventStreamEventFlags(
                kFSEventStreamEventFlagRootChanged
            ) != 0
        }

        guard eventURL.deletingLastPathComponent().path == monitoredFolderPath,
              flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) == 0,
              !eventURL.lastPathComponent.hasPrefix(".") else {
            return false
        }

        return displayedFileExtensions.contains(
            eventURL.pathExtension.lowercased()
        )
    }

    private func clearState() {
        pendingChange?.cancel()
        pendingChange = nil
        monitoredFolderPath = nil
        monitoredFiles = []
        displayedFileExtensions = []
        changeHandler = nil
    }
}
