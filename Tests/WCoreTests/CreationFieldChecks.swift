import Foundation
import WCore

enum CreationFieldChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); count += 1; print("PASS: \(name)") }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { count += 1; print("PASS: \(name)") }
        }
        let fields = CreationField.parse([
            "Description": ["id": "text", "type": "rich_text"],
            "Time Est": ["id": "number", "type": "number"],
            "Priority": ["id": "select", "type": "select", "select": ["options": [["name": "High"], ["name": "Low"]]]],
            "Tags": ["id": "multi", "type": "multi_select", "multi_select": ["options": [["name": "A"], ["name": "B"]]]],
            "Due": ["id": "date", "type": "date"],
            "Formula": ["id": "formula", "type": "formula"],
            "Rollup": ["id": "rollup", "type": "rollup"],
            "Status": ["id": "status", "type": "status"],
            "Locked": ["id": "locked", "type": "rich_text", "readOnly": true]
        ], settings: NotionSettings())
        check(fields.count == 5, "Creation fields exclude computed, locked and managed status properties")
        check(fields.first { $0.id == "select" }?.options == ["High", "Low"], "Creation picker preserves database options")
        var text = CreationValue(); text.text = "Notes"
        var number = CreationValue(); number.text = "0"
        var select = CreationValue(); select.options = ["High"]
        var multi = CreationValue(); multi.options = ["A", "B"]
        var date = CreationValue(); date.date = "2026-10-18"
        let payload = try CreationField.payload(fields: fields, values: ["text": text, "number": number, "select": select, "multi": multi, "date": date])
        check((payload["number"] as? [String: Double])?["number"] == 0, "Creation sends numeric zero without dropping it")
        check(((payload["date"] as? [String: Any])?["date"] as? [String: String])?["start"] == "2026-10-18", "Creation sends a date-only Notion value")
        check(((payload["multi"] as? [String: Any])?["multi_select"] as? [[String: String]])?.count == 2, "Creation sends multiple selected options")
        check(try CreationField.payload(fields: fields, values: ["text": CreationValue(), "number": CreationValue(), "date": CreationValue()]).isEmpty, "Unset creation values preserve Notion defaults")
        number.text = "banana"
        rejects("Reject invalid number before a page write") { _ = try CreationField.payload(fields: fields, values: ["number": number]) }
        number.text = "nan"
        rejects("Reject nonfinite number") { _ = try CreationField.payload(fields: fields, values: ["number": number]) }
        select.options = ["New option"]
        rejects("Never create unknown select options") { _ = try CreationField.payload(fields: fields, values: ["select": select]) }
        rejects("Reject fields removed from the live schema") { _ = try CreationField.payload(fields: fields, values: ["formula": text]) }
        date.date = "2026-02-30"
        rejects("Reject impossible dates") { _ = try CreationField.payload(fields: fields, values: ["date": date]) }
        let today = CreationValue.dayFormatter.string(from: Date())
        check(CreationValue.dayFormatter.date(from: today) != nil && today.count == 10, "Today defaults use local date-only format")
        return count
    }
}
