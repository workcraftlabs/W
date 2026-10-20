import Foundation
import WCore

enum CaptureChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); count += 1; print("PASS: \(name)") }
        let id = "11111111-2222-4333-8444-555555555555"
        check(try CaptureContent.notionID("https://app.notion.com/p/team/11111111222243338444555555555555?v=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") == id, "Capture location uses database ID rather than view ID")
        check(try CaptureContent.notionID(id) == id, "Capture accepts data source IDs")
        do { _ = try CaptureContent.notionID("not a database"); preconditionFailure("Accepted invalid location") }
        catch { count += 1; print("PASS: Invalid capture location rejected") }
        var draft = CaptureDraft(); draft.title = "A thought"; draft.body = "First line\nSecond line"
        var destination = CaptureDestination(); destination.sourceID = id; destination.titleProperty = "Name"; destination.dateProperty = "Date"
        let payload = try CaptureContent.payload(draft: draft, kind: .notes, destination: destination)
        check((payload["parent"] as? [String: String])?["data_source_id"] == id, "Capture writes to selected destination")
        let props = payload["properties"] as! [String: Any]
        check(props["Name"] != nil && props["Date"] != nil && props["Status"] == nil, "Capture writes title and optional date without task status")
        draft.body = String(repeating: "Text 📝\n", count: 1000)
        let long = try CaptureContent.payload(draft: draft, kind: .notes, destination: destination)
        let blocks = long["children"] as! [[String: Any]]
        let contents = blocks.map { block -> String in
            let p = block["paragraph"] as! [String: Any]
            let texts = p["rich_text"] as! [[String: Any]]
            return (texts[0]["text"] as! [String: String])["content"]!
        }
        check(contents.allSatisfy { $0.unicodeScalars.count <= 2000 } && contents.joined() == draft.body, "Capture chunks long content without dropping Unicode or newlines")
        var empty = CaptureDraft()
        do { _ = try CaptureContent.payload(draft: empty, kind: .journal, destination: destination); preconditionFailure("Accepted empty draft") }
        catch { count += 1; print("PASS: Empty capture rejected before write") }
        empty.body = "A useful thought\nMore detail"
        check(CaptureContent.title(for: empty, kind: .notes) == "A useful thought", "Untitled note uses first line")
        check(CaptureContent.title(for: empty, kind: .journal).hasPrefix("Journal · "), "Journal defaults to dated title")
        var state = SavedState(); state.captureDrafts = ["notes": draft, "journal": empty]; state.captureDestinations = ["notes": destination]
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        check(restored.captureDrafts?["notes"] == draft && restored.captureDrafts?["journal"] == empty && restored.captureDestinations?["notes"] == destination, "Capture drafts and separate destinations survive restart")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        legacy.removeValue(forKey: "captureDrafts"); legacy.removeValue(forKey: "captureDestinations"); legacy.removeValue(forKey: "captureRecords")
        check(try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: legacy)).captureDrafts == nil, "Old saved state loads without capture fields")
        let start = Date(timeIntervalSince1970: 1000)
        var first = WorkSession(task: WorkTask(id: "one", title: "One"), now: start); first.stop(done: true, at: start.addingTimeInterval(20))
        var second = WorkSession(task: WorkTask(id: "two", title: "Two"), now: start); second.stop(done: true, at: start.addingTimeInterval(50))
        var duplicate = WorkSession(task: first.task, now: start); duplicate.stop(done: true, at: start.addingTimeInterval(80))
        var stopped = WorkSession(task: WorkTask(id: "three", title: "Stopped"), now: start); stopped.stop(done: false, at: start.addingTimeInterval(100))
        let history = CompletionHistory.latest([first, second, stopped, duplicate])
        check(history.map(\.task.id) == ["one", "two"] && history.first?.endedAt == duplicate.endedAt, "History sorts latest completion first, deduplicates tasks, excludes unfinished sessions")
        return count
    }
}
