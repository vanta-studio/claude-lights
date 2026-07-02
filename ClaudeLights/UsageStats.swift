import Foundation

/// Aggregated token counts.
struct TokenTotals: Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheCreation = 0

    var total: Int { input + output + cacheRead + cacheCreation }
}

/// Reads Claude Code's transcript files and aggregates today's token usage.
///
/// Claude Code records per-message token counts under
/// `~/.claude/projects/<project>/<session>.jsonl` (`.message.usage`). This scans
/// those files read-only — no `claude` process is spawned. Scanning happens off
/// the main thread; results publish back on main.
final class UsageStats: ObservableObject {
    @Published private(set) var today = TokenTotals()
    @Published private(set) var lastUpdated: Date?

    private let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    private let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Recomputes today's totals in the background.
    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let totals = self.scan(now: Date())
            DispatchQueue.main.async {
                self.today = totals
                self.lastUpdated = Date()
            }
        }
    }

    // MARK: - Scanning

    private func scan(now: Date) -> TokenTotals {
        let startOfToday = Calendar.current.startOfDay(for: now)
        var totals = TokenTotals()
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return totals
        }

        for dir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                // Skip files not touched today — cheap early filter.
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let modified, modified < startOfToday { continue }

                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for line in content.split(separator: "\n") {
                    accumulate(line: line, startOfToday: startOfToday, into: &totals)
                }
            }
        }
        return totals
    }

    private func accumulate(line: Substring, startOfToday: Date, into totals: inout TokenTotals) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Filter by per-line timestamp when present; include if unparseable.
        if let ts = object["timestamp"] as? String, let date = parseDate(ts), date < startOfToday {
            return
        }

        guard let message = object["message"] as? [String: Any] else { return }
        // Synthetic messages are internal and carry no real usage.
        if let model = message["model"] as? String, model == "<synthetic>" { return }
        guard let usage = message["usage"] as? [String: Any] else { return }

        totals.input += usage["input_tokens"] as? Int ?? 0
        totals.output += usage["output_tokens"] as? Int ?? 0
        totals.cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
        totals.cacheCreation += usage["cache_creation_input_tokens"] as? Int ?? 0
    }

    private func parseDate(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }
}
