import Foundation
import WCore

enum AssigneeChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); count += 1; print("PASS: \(name)") }
        let person = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let other = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let users = NotionPerson.parse([
            ["id": person, "type": "person", "name": "Dave", "person": ["email": "dave@example.com"]],
            ["id": other, "type": "bot", "name": "Integration"]
        ])
        check(users.count == 1 && users[0].id == person, "Assignee picker excludes integration bots")
        check(users[0].label.contains("dave@example.com"), "Email distinguishes duplicate member names")
        let fields = CreationField.parse(["Assigned to": ["id": "assigned", "type": "people"], "Created by": ["id": "creator", "type": "created_by"]], settings: NotionSettings())
        check(fields.count == 1 && fields[0].id == "assigned", "Assignment excludes immutable Created by")
        let defaults = CreationValue.assigningDefault([:], fieldID: "assigned", personID: person)
        check(defaults["assigned"]?.options == [person], "New tasks inherit configured default assignee")
        var changed = CreationValue(); changed.options = [other]
        check(CreationValue.assigningDefault(["assigned": changed], fieldID: "assigned", personID: person)["assigned"]?.options == [other], "Per-task choice overrides default")
        let cleared = CreationValue.assigningDefault(["assigned": CreationValue()], fieldID: "assigned", personID: person)
        check(cleared["assigned"]?.options == [], "Explicit unassigned choice is not replaced by default")
        let payload = try CreationField.payload(fields: fields, values: defaults)
        let people = (payload["assigned"] as? [String: Any])?["people"] as? [[String: String]]
        check(people?.first?["id"] == person, "Notion payload assigns a person by ID")
        let empty = try CreationField.payload(fields: fields, values: cleared)
        check(((empty["assigned"] as? [String: Any])?["people"] as? [[String: String]])?.isEmpty == true, "Cleared assignee overrides template assignment")
        return count
    }
}
