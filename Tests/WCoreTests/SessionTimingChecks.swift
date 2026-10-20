import Foundation
import WCore

enum SessionTimingChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); count += 1; print("PASS: \(name)") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 6, minute: 42, second: 17))!
        let rounded = SessionTiming.roundedStart(now, calendar: calendar)
        check(calendar.component(.minute, from: rounded) == 40 && calendar.component(.second, from: rounded) == 0, "6:42:17 rounds down to 6:40")
        check(SessionTiming.roundedStart(rounded, calendar: calendar) == rounded, "Exact five-minute boundary remains unchanged")
        var settings = NotionSettings(); settings.sessionDateProperty = "Due"; settings.inProgress = "In Progress"
        for minutes in SessionTiming.intervals {
            var session = WorkSession(task: WorkTask(title: "Test"), now: now)
            session.configure(minutes: minutes, settings: settings, calendar: calendar)
            check(session.scheduledStart == rounded && session.scheduledEnd == now.addingTimeInterval(Double(minutes * 60)), "\(minutes)-minute interval uses full duration and five-minute start rounding")
        }
        var session = WorkSession(task: WorkTask(title: "Test"), now: now)
        session.configure(minutes: 25, settings: settings, calendar: calendar)
        check(!session.reachInterval(at: now.addingTimeInterval(1499)), "Timer stays running before boundary")
        check(session.reachInterval(at: now.addingTimeInterval(1503)), "Late callback stops at interval")
        check(session.elapsed(at: now.addingTimeInterval(2000)) == 1500 && session.awaitingDecision == true, "Stopped watch does not accumulate decision time")
        let restored = try JSONDecoder().decode(WorkSession.self, from: JSONEncoder().encode(session))
        check(restored.awaitingDecision == true && restored.scheduledStart == rounded, "Stopped watch and date range survive restart")
        session.continueInterval(at: now.addingTimeInterval(1800))
        check(session.runningSince != nil && session.checkInAt == 3000 && session.scheduledStart == rounded, "Keep going resumes with another interval and preserves start")
        check(session.scheduledEnd == now.addingTimeInterval(3300), "Keep going accounts for time spent deciding")
        session.pause(at: now.addingTimeInterval(1860))
        check(session.elapsed(at: now.addingTimeInterval(2200)) == 1560, "Manual pause excludes idle time")
        let date = SessionDate.today(at: now, calendar: calendar)
        let stop = PendingUpdate(pageID: "task", status: settings.inProgress, settings: settings, dateValue: date)
        let props = stop.properties
        let due = (props["Due"] as? [String: Any])?["date"] as? [String: Any]
        check(due?["start"] as? String == "2026-10-20" && due?["end"] is NSNull, "Stop replaces date range with local today and explicit null end")
        check((props["Status"] as? [String: Any])?["status"] as? [String: String] == ["name": "In Progress"], "Stop keeps task In Progress")
        let pending = try JSONDecoder().decode(PendingUpdate.self, from: JSONEncoder().encode(stop))
        check(pending.dateValue == date, "Date update survives offline queue persistence")
        let created = SessionTiming.creationProperties(settings: settings, at: now)
        check(created["Due"] != nil && created["Status"] != nil, "Create includes date and In Progress in the initial write")
        let moved = PendingUpdate(pageID: "task", status: settings.inProgress, settings: settings, projectID: "project")
        check(((moved.properties["Project"] as? [String: Any])?["relation"] as? [[String: String]])?.first?["id"] == "project", "Project change writes the relation")
        let schema: [String: [String: Any]] = ["Status": ["type": "status", "status": ["groups": [["name": "In progress", "option_ids": ["doing"]]]]]]
        let rule = ProjectProgress(properties: schema)
        check(rule.contains(["Status": ["status": ["id": "doing", "name": "Doing"]]]), "Project filter uses In Progress group even with custom option names")
        check(!rule.contains(["Status": ["status": ["id": "done", "name": "Done"]]]), "Completed projects are excluded")
        check(!rule.contains([:]), "Unknown project status is excluded")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
        for key in ["intervalMinutes", "awaitingDecision", "scheduledStart", "scheduledEnd", "notionSettings"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(WorkSession.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(old.intervalMinutes == nil, "Old sessions remain readable")
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 0, minute: 2))!
        check(SessionDate.today(at: midnight, calendar: calendar).start == "2026-10-21", "Date-only stop uses local day across midnight")
        let taskSchema: [String: [String: Any]] = ["Name": ["type": "title"], "Status": ["type": "status", "status": ["options": [["name": "In progress"], ["name": "Done"]]]], "Due": ["type": "date"], "Date": ["type": "date"]]
        let discovered = try NotionSchema(properties: taskSchema, settings: NotionSettings())
        check(discovered.suggested.sessionDateProperty == "Due", "Session date defaults to Due when available")
        var explicit = NotionSettings(); explicit.sessionDateProperty = "Date"
        check(try NotionSchema(properties: taskSchema, settings: explicit).suggested.sessionDateProperty == "Date", "Explicit Date selection is preserved")
        return count
    }
}
