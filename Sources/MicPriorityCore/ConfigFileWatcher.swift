import Foundation
import os

/// Notifies when the config file changes on disk (e.g. the CLI and the app editing the same file).
///
/// Watches the containing directory because `ConfigStore.save` writes atomically (replaces the file).
/// The handler runs on a private queue and receives the freshly loaded config.
public final class ConfigFileWatcher {
    private let store: ConfigStore
    private let handler: (PriorityConfig) -> Void
    private let queue = DispatchQueue(label: "com.alencar.micpriority.config-watcher")
    private let logger = Logger(subsystem: Log.subsystem, category: "ConfigFileWatcher")
    private var source: DispatchSourceFileSystemObject?
    private var lastData: Data?

    public init(store: ConfigStore, handler: @escaping (PriorityConfig) -> Void) {
        self.store = store
        self.handler = handler
    }

    deinit { stop() }

    public func start() {
        let directory = store.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Cannot watch \(directory.path, privacy: .public)")
            return
        }
        lastData = try? Data(contentsOf: store.url)
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in self?.fileChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    private func fileChanged() {
        guard let data = try? Data(contentsOf: store.url), data != lastData else { return }
        lastData = data
        do {
            handler(try store.load())
        } catch {
            logger.error("Ignoring unreadable config: \(String(describing: error), privacy: .public)")
        }
    }
}
