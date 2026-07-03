import Foundation

/// User-assigned names for sessions, keyed by `session_id` and persisted in
/// `~/.claude/claudelights-labels.json`.
///
/// The file deliberately lives next to the status file in `~/.claude` (not
/// Application Support) so external tooling — e.g. a future `/name-session`
/// slash command — can write it too. Writes are atomic and serialized through
/// the same `<file>.lock` flock convention the hook helper uses.
final class SessionLabels: ObservableObject {
    @Published private(set) var labels: [String: String] = [:]

    private let url: URL

    /// Exposed so the app can watch the file for external writes.
    var fileURL: URL { url }

    init(url: URL? = nil) {
        let env = ProcessInfo.processInfo.environment
        self.url = url
            ?? env["CLAUDELIGHTS_LABELS_FILE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/claudelights-labels.json")
        reload()
    }

    func label(for sessionId: String) -> String? {
        labels[sessionId]
    }

    /// Re-reads the file (called on launch and by the file watcher).
    /// A missing or corrupt file simply yields no labels.
    func reload() {
        guard let data = try? Data(contentsOf: url),
              let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
        else {
            labels = [:]
            return
        }
        labels = map
    }

    /// Sets (or, for nil/blank, removes) the label of one session.
    func setLabel(_ label: String?, for sessionId: String) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateFile { map in
            if let trimmed, !trimmed.isEmpty {
                map[sessionId] = trimmed
            } else {
                map.removeValue(forKey: sessionId)
            }
        }
    }

    /// Drops labels of sessions that no longer exist. Only called with a
    /// non-empty live set so a transiently unreadable status file can never
    /// wipe every label.
    func prune(keeping liveSessionIds: Set<String>) {
        guard !liveSessionIds.isEmpty else { return }
        guard labels.keys.contains(where: { !liveSessionIds.contains($0) }) else { return }
        mutateFile { map in
            map = map.filter { liveSessionIds.contains($0.key) }
        }
    }

    // MARK: - File I/O

    private func mutateFile(_ transform: (inout [String: String]) -> Void) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Same lock convention as the hook helper, so external writers (a
        // slash-command script) and the app never interleave read-modify-write.
        let lockFD = open(url.path + ".lock", O_CREAT | O_RDWR, 0o644)
        if lockFD >= 0 { flock(lockFD, LOCK_EX) }
        defer {
            if lockFD >= 0 {
                flock(lockFD, LOCK_UN)
                close(lockFD)
            }
        }

        var map: [String: String] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            map = existing
        }
        transform(&map)

        guard let data = try? JSONSerialization.data(
            withJSONObject: map, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        do {
            try data.write(to: tmp)
            if rename(tmp.path, url.path) != 0 {
                try? FileManager.default.removeItem(at: tmp)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
        labels = map
    }
}
