import Foundation

/// User-facing settings, persisted in `UserDefaults` and observable by SwiftUI.
///
/// Each property writes through to `UserDefaults` on change, so preferences are
/// durable across launches without an explicit save step.
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let notifyWorking = "notifyWorking"
        static let notifyDone = "notifyDone"
        static let notifyNeedsInput = "notifyNeedsInput"
        static let soundOnNeedsInput = "soundOnNeedsInput"
        static let attentionSound = "attentionSound"
    }

    @Published var notifyWorking: Bool {
        didSet { defaults.set(notifyWorking, forKey: Key.notifyWorking) }
    }
    @Published var notifyDone: Bool {
        didSet { defaults.set(notifyDone, forKey: Key.notifyDone) }
    }
    @Published var notifyNeedsInput: Bool {
        didSet { defaults.set(notifyNeedsInput, forKey: Key.notifyNeedsInput) }
    }
    @Published var soundOnNeedsInput: Bool {
        didSet { defaults.set(soundOnNeedsInput, forKey: Key.soundOnNeedsInput) }
    }
    /// Name of the system sound played on a needs-input transition.
    @Published var attentionSound: String {
        didSet { defaults.set(attentionSound, forKey: Key.attentionSound) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Sensible defaults: notify only when the user is actually needed, and
        // play a sound for that case.
        defaults.register(defaults: [
            Key.notifyWorking: false,
            Key.notifyDone: false,
            Key.notifyNeedsInput: true,
            Key.soundOnNeedsInput: true,
            Key.attentionSound: AttentionSound.defaultName,
        ])

        notifyWorking = defaults.bool(forKey: Key.notifyWorking)
        notifyDone = defaults.bool(forKey: Key.notifyDone)
        notifyNeedsInput = defaults.bool(forKey: Key.notifyNeedsInput)
        soundOnNeedsInput = defaults.bool(forKey: Key.soundOnNeedsInput)
        attentionSound = defaults.string(forKey: Key.attentionSound) ?? AttentionSound.defaultName
    }

    /// Whether a notification should fire for a transition into `state`.
    func shouldNotify(for state: SessionState) -> Bool {
        switch state {
        case .working: return notifyWorking
        case .done: return notifyDone
        case .needsInput: return notifyNeedsInput
        case .compacting: return false // Transient; not surfaced as a notification.
        }
    }
}
