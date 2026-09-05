import Foundation
import CoreServices

/// Watches a set of folder paths with FSEvents and reports changed paths on
/// a background queue (FSEvents latency acts as the debounce).
final class FolderWatcher {
    typealias ChangeHandler = ([String]) -> Void

    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private let queue = DispatchQueue(label: "com.motstar.fsevents", qos: .utility)
    private let onChange: ChangeHandler

    init(paths: [String], onChange: @escaping ChangeHandler) {
        self.watchedPaths = paths
        self.onChange = onChange
    }

    /// (Re)starts watching with the given paths. Safe to call repeatedly.
    func update(paths: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.watchedPaths = paths
            self.restartLocked()
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.restartLocked()
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: Private

    private func restartLocked() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        guard !watchedPaths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let newStream = FSEventStreamCreate(
            nil,
            folderWatcherCallback,
            &context,
            watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5, // latency seconds — natural debounce for bursts of changes
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
        stream = newStream
    }

    fileprivate func handleEventPaths(_ paths: [String]) {
        onChange(paths)
    }
}

/// C callback trampoline — recovers the watcher from the context pointer and
/// forwards the changed paths (CFArray thanks to kFSEventStreamCreateFlagUseCFTypes).
private let folderWatcherCallback: FSEventStreamCallback = {
    _, clientCallBackInfo, numEvents, eventPaths, _, _ in
    guard let clientCallBackInfo, numEvents > 0 else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    let pathsArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    let paths = (pathsArray as NSArray) as? [String] ?? []
    watcher.handleEventPaths(paths)
}
