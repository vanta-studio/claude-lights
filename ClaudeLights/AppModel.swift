import AppKit

/// The single observable source of truth for the SwiftUI popover.
///
/// `AppDelegate` pushes fresh sessions into it after every file reload; the UI
/// observes `sessions` and the intent methods route user actions back out
/// through injectable handlers (wired up as later phases add behavior).
final class AppModel: ObservableObject {
    /// Sessions to display, already sorted (worst state first) by the store.
    @Published private(set) var sessions: [SessionStatus] = []

    /// Mirrors the current login-item registration for the settings toggle.
    @Published var startsAtLogin: Bool

    let preferences: Preferences
    private let loginItem = LoginItem()

    /// Invoked when the user clicks a session (wired to the terminal launcher).
    var activateHandler: ((SessionStatus) -> Void)?
    /// Invoked when the user removes a single session.
    var removeHandler: ((SessionStatus) -> Void)?
    /// Invoked when the user clears all finished sessions.
    var clearFinishedHandler: (() -> Void)?
    /// Invoked when the user asks to check for updates.
    var checkForUpdatesHandler: (() -> Void)?

    /// Whether the "Check for Updates…" control should be shown (Sparkle linked).
    @Published var canCheckForUpdates = false

    init(preferences: Preferences) {
        self.preferences = preferences
        self.startsAtLogin = loginItem.isEnabled
    }

    /// The highest-severity state across all sessions, or `nil` if none.
    var worstState: SessionState? {
        sessions.map(\.state).max { $0.severity < $1.severity }
    }

    /// Replaces the visible sessions (called on the main thread after a reload).
    func update(sessions: [SessionStatus]) {
        self.sessions = sessions
    }

    // MARK: - Intents

    func activate(_ session: SessionStatus) {
        activateHandler?(session)
    }

    func remove(_ session: SessionStatus) {
        removeHandler?(session)
    }

    func clearFinished() {
        clearFinishedHandler?()
    }

    func checkForUpdates() {
        checkForUpdatesHandler?()
    }

    /// True when at least one session is finished (enables "Clear finished").
    var hasFinishedSessions: Bool {
        sessions.contains { $0.state == .done }
    }

    func toggleStartAtLogin() {
        loginItem.toggle()
        startsAtLogin = loginItem.isEnabled
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
