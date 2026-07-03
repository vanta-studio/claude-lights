import Foundation

// Headless tests for SessionLabels: persistence, trimming, pruning, and
// resilience against corrupt files.

var failures = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name) \(detail)")
        failures += 1
    }
}

let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("labels-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let fileURL = dir.appendingPathComponent("labels.json")

// --- set / get / trim ---------------------------------------------------------
let labels = SessionLabels(url: fileURL)
check("empty initially", labels.labels.isEmpty)
labels.setLabel("  API server  ", for: "s1")
check("label set + trimmed", labels.label(for: "s1") == "API server")
labels.setLabel("Frontend", for: "s2")

// --- persistence across instances ----------------------------------------------
let second = SessionLabels(url: fileURL)
check("persisted", second.label(for: "s1") == "API server" && second.label(for: "s2") == "Frontend")

// --- blank removes ---------------------------------------------------------------
labels.setLabel("   ", for: "s1")
check("blank clears label", labels.label(for: "s1") == nil)
labels.setLabel(nil, for: "s2")
check("nil clears label", labels.label(for: "s2") == nil)

// --- prune ------------------------------------------------------------------------
labels.setLabel("A", for: "live-1")
labels.setLabel("B", for: "dead-1")
labels.prune(keeping: ["live-1"])
check("prune drops dead sessions", labels.label(for: "dead-1") == nil && labels.label(for: "live-1") == "A")
labels.prune(keeping: [])
check("prune with empty live set is a no-op", labels.label(for: "live-1") == "A")

// --- reload picks up external writes ------------------------------------------------
try! #"{"ext-1":"written externally"}"#.data(using: .utf8)!.write(to: fileURL)
labels.reload()
check("reload picks up external writes", labels.label(for: "ext-1") == "written externally")

// --- corrupt file -> no labels, and writing recovers ---------------------------------
try! "not json".data(using: .utf8)!.write(to: fileURL)
labels.reload()
check("corrupt file yields no labels", labels.labels.isEmpty)
labels.setLabel("recovered", for: "s3")
check("write after corruption recovers", SessionLabels(url: fileURL).label(for: "s3") == "recovered")

print(failures == 0 ? "\nAll label tests passed." : "\n\(failures) test(s) failed.")
exit(failures == 0 ? 0 : 1)
