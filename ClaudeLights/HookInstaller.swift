import Combine
import CryptoKit
import Foundation

/// How ClaudeLights' hook wiring in `~/.claude/settings.json` currently looks.
enum HookInstallStatus: Equatable {
    enum RepairReason: Equatable {
        /// The helper binary referenced from settings.json is gone.
        case helperMissing
        /// The installed helper differs from the one bundled with this app.
        case helperOutdated
        /// Some of our hook events are wired, but not all of them.
        case partialWiring
        /// Our entries point somewhere other than the expected helper path
        /// (e.g. a previous install location).
        case wrongPath
    }

    case unknown
    case notInstalled
    case installed
    case needsRepair(RepairReason)
    /// The old jq-based shell scripts from the repository are wired up.
    case legacyShellHooks
    /// settings.json exists but is not strict JSON (comments, trailing
    /// commas, …). We never write in this state.
    case settingsUnreadable(String)
}

enum HookInstallError: LocalizedError {
    case settingsUnreadable(String)
    case bundledHelperMissing
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .settingsUnreadable(let detail):
            return String(localized: "settings.json could not be parsed (\(detail)). Fix it manually, then try again.")
        case .bundledHelperMissing:
            return String(localized: "The hook helper is missing from the app bundle. Reinstall ClaudeLights.")
        case .writeFailed(let detail):
            return String(localized: "Could not write settings.json (\(detail)).")
        }
    }
}

/// Installs, repairs, and removes the Claude Code hook wiring.
///
/// The helper binary is copied out of the app bundle to a stable location
/// (`~/Library/Application Support/ClaudeLights/`) so the wiring in
/// settings.json survives app updates, relocation, and App Translocation.
/// `ensureHelperCurrent()` re-copies it whenever the bundled helper changes.
final class HookInstaller: ObservableObject {
    @Published private(set) var status: HookInstallStatus = .unknown

    /// One wired hook event: `'<helper>' <verb>` under `event`, optionally
    /// restricted by a matcher (Claude Code's per-event filter).
    private struct Wiring {
        let event: String
        let verb: String
        let matcher: String?
    }

    private static let wirings: [Wiring] = [
        Wiring(event: "UserPromptSubmit", verb: "working", matcher: nil),
        Wiring(event: "PostToolUse", verb: "resume", matcher: nil),
        Wiring(event: "Stop", verb: "done", matcher: nil),
        Wiring(event: "PreCompact", verb: "compacting", matcher: nil),
        Wiring(event: "Notification", verb: "needs_input", matcher: "idle_prompt|permission_prompt"),
        Wiring(event: "SessionEnd", verb: "remove", matcher: nil),
    ]

    static let helperName = "claudelights-hook"
    private static let backupPrefix = "settings.json.claudelights-backup-"
    private static let keptBackups = 3

    private let settingsURL: URL
    private let helperDirectory: URL
    private let bundledHelperURL: URL
    private let fileManager = FileManager.default

    /// - Parameters:
    ///   - settingsURL: Claude Code's settings file. Defaults to
    ///     `~/.claude/settings.json`; override with `CLAUDELIGHTS_SETTINGS_FILE`
    ///     (also the escape hatch for `CLAUDE_CONFIG_DIR` setups, which a GUI
    ///     app cannot see).
    ///   - helperDirectory: Where the helper is installed. Defaults to
    ///     `~/Library/Application Support/ClaudeLights`; override with
    ///     `CLAUDELIGHTS_HELPER_DIR`.
    ///   - bundledHelperURL: The helper inside the app bundle.
    init(settingsURL: URL? = nil, helperDirectory: URL? = nil, bundledHelperURL: URL? = nil) {
        let env = ProcessInfo.processInfo.environment
        self.settingsURL = settingsURL
            ?? env["CLAUDELIGHTS_SETTINGS_FILE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
        self.helperDirectory = helperDirectory
            ?? env["CLAUDELIGHTS_HELPER_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/ClaudeLights")
        self.bundledHelperURL = bundledHelperURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(Self.helperName)")
    }

    private var installedHelperURL: URL {
        helperDirectory.appendingPathComponent(Self.helperName)
    }

    /// The settings file this installer reads and writes (for "open in editor").
    var settingsFileURL: URL { settingsURL }

    // MARK: - Status detection

    /// Does this hook command belong to us (current helper wiring)?
    private func isOurCommand(_ command: String) -> Bool {
        command.contains(Self.helperName)
    }

    /// Does this hook command point at the deprecated shell scripts shipped in
    /// the repository (`…/claude-lights/hooks/*.sh`)?
    private func isLegacyCommand(_ command: String) -> Bool {
        command.contains("claude-lights/hooks/") && command.contains(".sh")
    }

    func refreshStatus() {
        status = detectStatus()
    }

    private func detectStatus() -> HookInstallStatus {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return .notInstalled }
        let settings: [String: Any]
        do {
            settings = try readSettings()
        } catch {
            return .settingsUnreadable(error.localizedDescription)
        }

        var ourCommands: [String] = []
        var wiredEvents: Set<String> = []
        var hasLegacy = false
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            for group in value as? [[String: Any]] ?? [] {
                for hook in group["hooks"] as? [[String: Any]] ?? [] {
                    guard let command = hook["command"] as? String else { continue }
                    if isOurCommand(command) {
                        ourCommands.append(command)
                        wiredEvents.insert(event)
                    } else if isLegacyCommand(command) {
                        hasLegacy = true
                    }
                }
            }
        }

        if ourCommands.isEmpty {
            return hasLegacy ? .legacyShellHooks : .notInstalled
        }
        if hasLegacy { return .legacyShellHooks }

        if !ourCommands.allSatisfy({ $0.contains(installedHelperURL.path) }) {
            return .needsRepair(.wrongPath)
        }
        if wiredEvents != Set(Self.wirings.map(\.event)) {
            return .needsRepair(.partialWiring)
        }
        guard fileManager.fileExists(atPath: installedHelperURL.path) else {
            return .needsRepair(.helperMissing)
        }
        if let bundled = sha256(of: bundledHelperURL),
           sha256(of: installedHelperURL) != bundled {
            return .needsRepair(.helperOutdated)
        }
        return .installed
    }

    // MARK: - Helper binary self-heal

    /// Copies the bundled helper to the stable install location when it is
    /// missing or differs (i.e. after every app update). Safe to call on every
    /// launch; does nothing when there is no bundled helper (dev builds
    /// without the Helpers folder) or nothing to update.
    func ensureHelperCurrent() {
        guard fileManager.fileExists(atPath: bundledHelperURL.path) else { return }
        let installed = installedHelperURL
        if let bundled = sha256(of: bundledHelperURL), sha256(of: installed) == bundled {
            return
        }
        do {
            try fileManager.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: installed.path) {
                try fileManager.removeItem(at: installed)
            }
            try fileManager.copyItem(at: bundledHelperURL, to: installed)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path)
        } catch {
            NSLog("ClaudeLights: failed to install hook helper: \(error.localizedDescription)")
        }
    }

    private func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Install / uninstall

    /// Installs (or repairs/migrates) the hook wiring. Idempotent: existing
    /// ClaudeLights entries — current helper or legacy shell scripts — are
    /// replaced; everything else in settings.json is preserved.
    func install() throws {
        guard fileManager.fileExists(atPath: bundledHelperURL.path) else {
            throw HookInstallError.bundledHelperMissing
        }
        ensureHelperCurrent()

        var settings = try readSettingsOrEmpty()
        try backupSettingsIfPresent()

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for wiring in Self.wirings {
            var groups = removingOurEntries(from: hooks[wiring.event])
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": "'\(installedHelperURL.path)' \(wiring.verb)"]],
            ]
            if let matcher = wiring.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[wiring.event] = groups
        }
        settings["hooks"] = hooks

        try writeSettings(settings)
        refreshStatus()
    }

    /// Removes only ClaudeLights' hook entries (current and legacy), cleaning
    /// up structures that become empty. Leaves the helper binary in place.
    func uninstall() throws {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            refreshStatus()
            return
        }
        var settings = try readSettings()
        try backupSettingsIfPresent()

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in hooks.keys {
            let groups = removingOurEntries(from: hooks[event])
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeSettings(settings)
        refreshStatus()
    }

    /// Strips our commands (current helper and legacy scripts) out of one
    /// event's matcher groups, dropping groups left with no hooks.
    private func removingOurEntries(from value: Any?) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for var group in value as? [[String: Any]] ?? [] {
            let kept = (group["hooks"] as? [[String: Any]] ?? []).filter { hook in
                guard let command = hook["command"] as? String else { return true }
                return !isOurCommand(command) && !isLegacyCommand(command)
            }
            if kept.isEmpty { continue }
            group["hooks"] = kept
            result.append(group)
        }
        return result
    }

    // MARK: - settings.json I/O

    private func readSettings() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookInstallError.settingsUnreadable("top level is not an object")
            }
            return object
        } catch let error as HookInstallError {
            throw error
        } catch {
            // Strict JSON only: comments or trailing commas land here, and we
            // must never rewrite (and thereby mangle) such a file.
            throw HookInstallError.settingsUnreadable(error.localizedDescription)
        }
    }

    private func readSettingsOrEmpty() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return [:] }
        return try readSettings()
    }

    /// The file we actually write: symlinks are resolved so dotfiles setups
    /// keep their link instead of having it replaced by a plain file.
    private var writeTargetURL: URL {
        settingsURL.resolvingSymlinksInPath()
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw HookInstallError.writeFailed(error.localizedDescription)
        }
        let target = writeTargetURL
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = target.deletingLastPathComponent()
                .appendingPathComponent(".\(target.lastPathComponent).claudelights.tmp")
            try data.write(to: tmp)
            guard rename(tmp.path, target.path) == 0 else {
                try? fileManager.removeItem(at: tmp)
                throw HookInstallError.writeFailed(String(cString: strerror(errno)))
            }
        } catch let error as HookInstallError {
            throw error
        } catch {
            throw HookInstallError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Backups

    private func backupSettingsIfPresent() throws {
        let target = writeTargetURL
        guard fileManager.fileExists(atPath: target.path) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let backup = target.deletingLastPathComponent()
            .appendingPathComponent(Self.backupPrefix + formatter.string(from: Date()))
        if fileManager.fileExists(atPath: backup.path) {
            try? fileManager.removeItem(at: backup)
        }
        try fileManager.copyItem(at: target, to: backup)
        pruneBackups(in: target.deletingLastPathComponent())
    }

    private func pruneBackups(in directory: URL) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        let backups = names.filter { $0.hasPrefix(Self.backupPrefix) }.sorted()
        guard backups.count > Self.keptBackups else { return }
        for name in backups.dropLast(Self.keptBackups) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
