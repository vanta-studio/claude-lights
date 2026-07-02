import AppKit

/// Wires together preferences, the file watcher, the session store, the
/// observable model, and the status bar UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Location of the shared status file the hooks write to.
    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/claudelights-status.json")

    private let preferences = Preferences()
    private let store = SessionStore()
    private let terminalLauncher = TerminalLauncher()
    private let notifications = NotificationManager()
    private let history = SessionHistory()
    private let usage = UsageStats()
    private let updater = Updater()
    private lazy var model = AppModel(preferences: preferences)
    private var controller: StatusController?
    private var watcher: FileWatcher?

    /// Periodically re-reads the file so stale sessions expire even when no hook
    /// fires (i.e. when the file itself is not changing).
    private var cleanupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clicking a session focuses the terminal it runs in (auto-detected).
        model.activateHandler = { [weak self] session in
            self?.terminalLauncher.focus(session: session)
        }

        // Tapping a notification focuses that session's terminal too.
        notifications.onOpenSession = { [weak self] sessionId in
            guard let self,
                  let session = self.store.sessions.first(where: { $0.sessionId == sessionId })
            else { return }
            self.terminalLauncher.focus(session: session)
        }
        notifications.requestAuthorization()

        // Removing sessions rewrites the status file, then reloads.
        model.removeHandler = { [weak self] session in
            guard let self else { return }
            self.store.remove(sessionId: session.sessionId, from: self.statusURL)
            self.reload()
        }
        model.clearFinishedHandler = { [weak self] in
            guard let self else { return }
            self.store.clearFinished(from: self.statusURL)
            self.reload()
        }

        // Software updates (Sparkle). No-op in the swiftc dev build.
        model.canCheckForUpdates = updater.canCheckForUpdates
        model.checkForUpdatesHandler = { [weak self] in
            self?.updater.checkForUpdates()
        }

        controller = StatusController(model: model, history: history, usage: usage)

        // Show an initial state before any file event arrives.
        reload()

        let watcher = FileWatcher(url: statusURL) { [weak self] in
            // FileWatcher calls back on its own queue; UI work must be on main.
            DispatchQueue.main.async { self?.reload() }
        }
        watcher.start()
        self.watcher = watcher

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupTimer?.invalidate()
        watcher?.stop()
    }

    /// Reloads the store, pushes sessions into the model, refreshes the icon,
    /// and fires notifications/sound for any state transitions. Main-thread only.
    private func reload() {
        store.reload(from: statusURL)
        model.update(sessions: store.sessions)
        controller?.updateIcon()
        handleTransitions(store.recentTransitions)
    }

    /// Coalescing window: rapid consecutive transitions for the same session
    /// only notify once, for the latest state — avoids notification spam when a
    /// session flips state quickly (e.g. working → needs_input → working).
    private let notificationDebounce: TimeInterval = 1.2
    private var pendingNotifications: [String: DispatchWorkItem] = [:]

    /// Records history immediately and schedules a debounced notification/sound
    /// for each session that just changed state.
    private func handleTransitions(_ transitions: [SessionStatus]) {
        for session in transitions {
            // History captures every transition immediately (not debounced).
            history.record(session)
            scheduleNotification(for: session)
        }
    }

    private func scheduleNotification(for session: SessionStatus) {
        // Cancel any pending notification for this session; the latest wins.
        pendingNotifications[session.sessionId]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingNotifications[session.sessionId] = nil
            if self.preferences.shouldNotify(for: session.state) {
                self.notifications.notify(session: session)
            }
            if session.state == .needsInput, self.preferences.soundOnNeedsInput {
                AttentionSound.play(self.preferences.attentionSound)
            }
        }
        pendingNotifications[session.sessionId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + notificationDebounce, execute: work)
    }
}
