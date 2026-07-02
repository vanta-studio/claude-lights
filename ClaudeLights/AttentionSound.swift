import AppKit

/// Plays the "needs input" attention sound. The chosen sound is one of the
/// built-in macOS system sounds (in `/System/Library/Sounds`).
///
/// The played `NSSound` is retained in a static property for the duration of
/// playback — otherwise a freshly created, immediately-released sound can be cut
/// off or skipped on rapid replays.
enum AttentionSound {
    /// Selectable built-in system sounds, in menu order.
    static let all = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    /// The default when nothing is chosen.
    static let defaultName = "Ping"

    private static var player: NSSound?

    /// Plays the named system sound, falling back to the default if unavailable.
    static func play(_ name: String) {
        player?.stop()
        let sound = NSSound(named: NSSound.Name(name)) ?? NSSound(named: NSSound.Name(defaultName))
        player = sound
        sound?.play()
    }
}
