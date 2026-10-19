import Foundation
import WCore

enum TaskPropertyChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ value: Bool, _ label: String) { precondition(value, label); count += 1; print("PASS: \(label)") }
        let parsed = TaskProperty.parse([
            "Due": ["id": "due", "type": "date", "date": ["start": "2026-10-18", "end": "2026-10-20"]],
            "Time Est": ["id": "est", "type": "number", "number": 0],
            "Empty": ["id": "empty", "type": "number", "number": NSNull()],
            "Priority": ["id": "priority", "type": "select", "select": ["name": "High"]],
            "Computed": ["id": "formula", "type": "formula", "formula": ["type": "number", "number": 1.5]],
            "Total": ["id": "rollup", "type": "rollup", "rollup": ["type": "array", "array": [["type": "number", "number": 10], ["type": "number", "number": 20]]]],
            "Flag": ["id": "flag", "type": "checkbox", "checkbox": false],
            "Start button": ["id": "button", "type": "button", "button": [:]],
            "Notes": ["id": "notes", "type": "rich_text", "rich_text": [["plain_text": String(repeating: "a", count: 300)]]]
        ])
        func value(_ id: String) -> String? { parsed.first { $0.id == id }?.value }
        check(value("due") == "2026-10-18 → 2026-10-20", "Preserve due date ranges without timezone shifts")
        check(value("est") == "0" && value("empty") == "", "Distinguish zero estimates from missing values")
        check(value("priority") == "High" && value("flag") == "No", "Format select and unchecked properties")
        check(value("formula") == "1.5" && value("rollup") == "10, 20", "Format computed property values")
        check(parsed.filter(\.defaultVisible).map(\.id) == ["due", "est"], "Default to actual Due and Time Est fields")
        check(value("button") == nil && value("notes")?.count == 241, "Skip action properties and bound text previews")
        let legacy = try JSONDecoder().decode(WorkTask.self, from: Data(#"{"id":"old","title":"Old task","project":"","done":false,"remote":true}"#.utf8))
        check(legacy.properties == nil, "Existing task and session caches remain readable")
        let task = WorkTask(title: "Task", remote: true, properties: parsed)
        let restored = try JSONDecoder().decode(WorkTask.self, from: JSONEncoder().encode(task))
        check(restored.properties == parsed, "Property IDs and values survive persistence")
        return count
    }
}
