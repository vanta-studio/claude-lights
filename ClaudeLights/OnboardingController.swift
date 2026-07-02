import AppKit
import SwiftUI

/// Owns the first-run welcome window. Shown automatically on launch until the
/// user has completed onboarding or the hooks are installed; reachable later
/// via Settings → "Show welcome window".
final class OnboardingController {
    private static let completedKey = "hasCompletedOnboarding"

    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    /// Shows the window on first run: never completed AND hooks not installed
    /// (users who wired hooks manually shouldn't be greeted like newcomers).
    func showIfNeeded() {
        guard !hasCompletedOnboarding, model.hookStatus != .installed else { return }
        show()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(model: model) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Welcome to ClaudeLights")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        // Accessory apps (no Dock icon) need an explicit activation for the
        // window to come to the front on launch.
        NSApp.activate(ignoringOtherApps: true)
    }
}
