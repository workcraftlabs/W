import Foundation

public struct SessionDate: Codable, Equatable {
    public var start: String
    public var end: String?
    public static func today(at date: Date = Date(), calendar: Calendar = .current) -> Self {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        return Self(start: formatter.string(from: date), end: nil)
    }
    public static func range(start: Date, end: Date) -> Self {
        let formatter = ISO8601DateFormatter()
        return Self(start: formatter.string(from: start), end: formatter.string(from: end))
    }
    public var payload: [String: Any] { ["start": start, "end": end as Any? ?? NSNull(), "time_zone": NSNull()] }
}

public enum SessionTiming {
    public static let intervals = [15, 25, 30, 24, 50, 60]
    public static func creationProperties(settings: NotionSettings, at now: Date = Date()) -> [String: Any] {
        var properties: [String: Any] = [settings.statusProperty: [settings.statusType: ["name": settings.inProgress]]]
        if let field = settings.sessionDateProperty, !field.isEmpty { properties[field] = ["date": SessionDate.today(at: now).payload] }
        return properties
    }
    /// Nearest five-minute mark; exact halfway points round forward.
    public static func roundedEnd(_ date: Date, calendar: Calendar = .current) -> Date {
        let lower = roundedStart(date, calendar: calendar)
        let upper = calendar.date(byAdding: .minute, value: 5, to: lower) ?? lower.addingTimeInterval(300)
        return date.timeIntervalSince(lower) < upper.timeIntervalSince(date) ? lower : upper
    }
    public static func roundedStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        return calendar.date(byAdding: .minute, value: -(minute % 5), to: minuteStart) ?? minuteStart
    }
}

public extension WorkSession {
    mutating func configure(minutes: Int, settings: NotionSettings, calendar: Calendar = .current) {
        intervalMinutes = minutes
        notionSettings = settings
        scheduledStart = SessionTiming.roundedStart(startedAt, calendar: calendar)
        scheduledEnd = startedAt.addingTimeInterval(Double(minutes * 60))
        checkInAt = Double(minutes * 60)
        awaitingDecision = false
    }
    /// Clamp to the boundary even if a timer callback arrives late.
    mutating func reachInterval(at now: Date) -> Bool {
        guard runningSince != nil, let target = checkInAt, elapsed(at: now) >= target else { return false }
        accumulated = target; runningSince = nil; checkInAt = nil; awaitingDecision = true
        return true
    }
    mutating func continueInterval(at now: Date = Date()) {
        let minutes = intervalMinutes ?? 25
        checkInAt = elapsed(at: now) + Double(minutes * 60)
        scheduledEnd = max(scheduledEnd ?? now, now).addingTimeInterval(Double(minutes * 60))
        awaitingDecision = false
        resume(at: now)
    }
    mutating func recordCompletion(at now: Date, calendar: Calendar = .current) {
        let start = scheduledStart ?? SessionTiming.roundedStart(startedAt, calendar: calendar)
        scheduledStart = start
        scheduledEnd = max(start, SessionTiming.roundedEnd(now, calendar: calendar))
    }
    var sessionDate: SessionDate? {
        guard let start = scheduledStart, let end = scheduledEnd else { return nil }
        return .range(start: start, end: end)
    }
}

public extension PendingUpdate {
    var properties: [String: Any] {
        let s = settings
        var result: [String: Any] = [s.statusProperty: [s.statusType: ["name": status]]]
        if let start, !s.startProperty.isEmpty { result[s.startProperty] = ["date": ["start": ISO8601DateFormatter().string(from: start)]] }
        if let dateValue, let field = s.sessionDateProperty, !field.isEmpty { result[field] = ["date": dateValue.payload] }
        if let projectID, !s.projectProperty.isEmpty { result[s.projectProperty] = ["relation": projectID.isEmpty ? [] : [["id": projectID]]] }
        return result
    }
}
