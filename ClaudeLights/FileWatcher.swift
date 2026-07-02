import Foundation

/// Watches a single file for changes using a kernel event source
/// (`DispatchSource`) rather than polling.
///
/// The status file is updated by the hook scripts with an atomic
/// `write-temp + rename` (`mv`), which replaces the file's inode. A vnode watch
/// bound to the original file descriptor therefore sees a `.rename`/`.delete`
/// event; when that happens the watcher re-opens the new file and re-arms.
///
/// While the file does not yet exist (before the first hook fires) the watcher
/// retries on a short timer — the only situation in which it polls at all. Once
/// the file exists, updates are delivered purely through kernel events.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.example.claudelights.filewatcher")

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1

    /// - Parameters:
    ///   - url: File to watch.
    ///   - onChange: Called on the watcher's private queue whenever the file
    ///     changes. Callers should hop to the main queue before touching UI.
    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    /// Begins watching. Safe to call once.
    func start() {
        queue.async { [weak self] in self?.arm() }
    }

    /// Stops watching and releases the file descriptor.
    func stop() {
        queue.async { [weak self] in
            self?.source?.cancel()
            self?.source = nil
        }
    }

    // MARK: - Private

    private func arm() {
        // If the file is not there yet, retry shortly. This is the only polling
        // path and it ends as soon as the first hook creates the file.
        guard FileManager.default.fileExists(atPath: url.path) else {
            scheduleRetry()
            return
        }

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            scheduleRetry()
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )

        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self, let flags = newSource?.data else { return }
            self.onChange()
            // The file was replaced (atomic rename) or removed: re-open it.
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.reArm()
            }
        }

        newSource.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source = newSource
        newSource.resume()

        // Emit the initial state immediately.
        onChange()
    }

    private func reArm() {
        source?.cancel() // Cancel handler closes the old descriptor.
        source = nil
        // A brief delay lets the atomic replace settle before we re-open.
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.arm() }
    }

    private func scheduleRetry() {
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.arm() }
    }
}
