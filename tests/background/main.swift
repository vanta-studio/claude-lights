import Foundation

// Headless tests for SessionStatus.backgroundTasks: decoding, summary
// formatting/state-gating, and Codable round-trip (the store re-encodes the
// status file on prune/remove; the field must survive that).

var failures = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name) \(detail)")
        failures += 1
    }
}

func decode(_ json: String) -> SessionStatus? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(SessionStatus.self, from: Data(json.utf8))
}

func session(state: String, tasks: [String]?) -> String {
    var extra = ""
    if let tasks {
        let list = tasks.map { "\"\($0)\"" }.joined(separator: ",")
        extra = ",\"background_tasks\":[\(list)]"
    }
    return #"{"state":"\#(state)","session_id":"s1","project":"demo","timestamp":"2026-07-04T10:00:00Z"\#(extra)}"#
}

// --- decoding -----------------------------------------------------------------
let without = decode(session(state: "needs_input", tasks: nil))
check("decodes without field", without != nil)
check("absent field -> nil", without?.backgroundTasks == nil)
check("absent field -> no summary", without?.backgroundTasksSummary == nil)

let one = decode(session(state: "needs_input", tasks: ["Sleep then reply done"]))
check("decodes list", one?.backgroundTasks == ["Sleep then reply done"])

// --- summary formatting ---------------------------------------------------------
check("singular summary", one?.backgroundTasksSummary == "1 task still running: Sleep then reply done")

let two = decode(session(state: "done", tasks: ["First", "Second"]))
check("plural summary counts and shows first", two?.backgroundTasksSummary == "2 tasks still running: First, …")

let empty = decode(session(state: "needs_input", tasks: []))
check("empty list -> no summary", empty?.backgroundTasksSummary == nil)

// --- state gating ------------------------------------------------------------------
let working = decode(session(state: "working", tasks: ["X"]))
check("working -> no summary", working?.backgroundTasksSummary == nil)
let compacting = decode(session(state: "compacting", tasks: ["X"]))
check("compacting -> no summary", compacting?.backgroundTasksSummary == nil)
check("done -> summary", decode(session(state: "done", tasks: ["X"]))?.backgroundTasksSummary != nil)

// --- Codable round-trip (mutateFile re-encode must not drop the field) -------------
if let one {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(one)
    let reencoded = String(data: data, encoding: .utf8) ?? ""
    check("round-trip keeps background_tasks", reencoded.contains("\"background_tasks\""))
    let roundtripDecoder = JSONDecoder()
    roundtripDecoder.dateDecodingStrategy = .iso8601
    let back = try! roundtripDecoder.decode(SessionStatus.self, from: data)
    check("round-trip keeps values", back.backgroundTasks == ["Sleep then reply done"])
} else {
    check("round-trip (decode failed)", false)
}

print()
if failures > 0 {
    print("\(failures) check(s) failed.")
    exit(1)
}
print("All background-model checks passed.")
