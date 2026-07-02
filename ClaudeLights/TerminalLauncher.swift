import AppKit

/// Brings the terminal a session runs in to the front when the user clicks it.
///
/// The target is detected automatically from the session's captured
/// `TERM_PROGRAM` (no user setting). For Terminal.app and iTerm2, the exact
/// window/tab is focused via AppleScript using the captured tty; for other
/// terminals the app is activated (App level).
///
/// Focusing a specific window uses Apple events, so macOS asks the user to grant
/// Automation permission the first time (see `NSAppleEventsUsageDescription`).
final class TerminalLauncher {
    /// Maps a `TERM_PROGRAM` value to the terminal app's bundle identifier.
    private let bundleIdByTerm: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "Hyper": "co.zeit.hyper",
        "Tabby": "org.tabby",
        "kitty": "net.kovidgoyal.kitty",
        "Alacritty": "org.alacritty",
    ]

    /// Focuses the terminal for a session, preferring its exact window/tab.
    func focus(session: SessionStatus) {
        guard let term = session.term, let bundleId = bundleIdByTerm[term] else {
            if let term = session.term {
                NSLog("ClaudeLights: unknown terminal '\(term)', cannot focus")
            }
            return
        }

        // Precise window focus for the terminals that support AppleScript targeting.
        if let tty = session.tty, !tty.isEmpty {
            if term == "Apple_Terminal", focusWindow(build: terminalScript, tty: tty) { return }
            if term == "iTerm.app", focusWindow(build: itermScript, tty: tty) { return }
        }

        activate(bundleId: bundleId)
    }

    // MARK: - Private

    /// Activates an app by bundle identifier, launching it if necessary.
    private func activate(bundleId: String) {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleId) else {
            NSLog("ClaudeLights: terminal app not installed: \(bundleId)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    /// Runs a tty-targeting AppleScript. Returns whether a matching window was
    /// found. The tty is validated to prevent script injection (it originates
    /// from the on-disk status file, which any local process can write).
    private func focusWindow(build: (String) -> String, tty: String) -> Bool {
        guard tty.range(of: "^ttys?[0-9]+$", options: .regularExpression) != nil else {
            return false
        }
        guard let script = NSAppleScript(source: build(tty)) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("ClaudeLights: AppleScript focus failed: \(error)")
            return false
        }
        return result.stringValue == "1"
    }

    /// AppleScript to focus the Terminal.app tab whose tty ends with `tty`.
    private func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) ends with "\(tty)" then
                        set selected of t to true
                        set frontmost of w to true
                        return "1"
                    end if
                end repeat
            end repeat
        end tell
        return "0"
        """
    }

    /// AppleScript to focus the iTerm2 session whose tty ends with `tty`.
    private func itermScript(tty: String) -> String {
        """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) ends with "\(tty)" then
                            select w
                            select t
                            return "1"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "0"
        """
    }
}
