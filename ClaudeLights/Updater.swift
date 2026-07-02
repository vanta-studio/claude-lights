import Foundation

// Sparkle is an external Swift Package added in Xcode (see README → Auto-updates).
// It is not available to the swiftc-based dev build, so all Sparkle usage is
// guarded by `canImport(Sparkle)`. Both builds compile: the dev build gets the
// no-op fallback; the Xcode build gets the real updater.

#if canImport(Sparkle)
import Sparkle

/// Wraps Sparkle's standard updater. The feed URL and public key are configured
/// in Info.plist (`SUFeedURL`, `SUPublicEDKey`).
final class Updater {
    private let controller: SPUStandardUpdaterController

    init() {
        // `startingUpdater: true` begins background scheduling per Info.plist.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Whether a manual update check can be offered in the UI.
    var canCheckForUpdates: Bool { true }

    /// Triggers an interactive update check.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

#else

/// Fallback used when Sparkle is not linked (e.g. the local swiftc dev build).
/// The app builds and runs; update checks are simply unavailable.
final class Updater {
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
}

#endif
