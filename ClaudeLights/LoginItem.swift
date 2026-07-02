import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for the "Start at Login" toggle.
///
/// `SMAppService` (macOS 13+) registers the app itself as a login item; no
/// separate helper bundle or privileged operation is required.
final class LoginItem {
    /// Whether the app is currently registered to launch at login.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Flips the login-item registration. Errors are logged but not fatal —
    /// the menu simply reflects whatever state the system reports afterwards.
    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ClaudeLights: failed to toggle login item: \(error.localizedDescription)")
        }
    }
}
