import Foundation

public struct WorkTask: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var projectID: String?
    public var project: String
    public var done: Bool
    public var remote: Bool
    public var properties: [TaskProperty]?
    public init(id: String = UUID().uuidString, title: String, projectID: String? = nil, project: String = "", done: Bool = false, remote: Bool = false, properties: [TaskProperty]? = nil) {
        self.id = id; self.title = title; self.projectID = projectID; self.project = project; self.done = done; self.remote = remote; self.properties = properties
    }
}
public extension WorkTask {
    var notionWebURL: URL? {
        guard remote, let pageID = UUID(uuidString: id.count == 32 ? "\(id.prefix(8))-\(id.dropFirst(8).prefix(4))-\(id.dropFirst(12).prefix(4))-\(id.dropFirst(16).prefix(4))-\(id.suffix(12))" : id) else { return nil }
        return URL(string: "https://www.notion.so/\(pageID.uuidString.replacingOccurrences(of: "-", with: "").lowercased())")
    }
    var notionAppURL: URL? {
        guard let web = notionWebURL, var parts = URLComponents(url: web, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "notion"
        return parts.url
    }
}
public struct Project: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}
public struct WorkSession: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var task: WorkTask
    public var startedAt: Date
    public var runningSince: Date?
    public var accumulated: TimeInterval = 0
    public var endedAt: Date?
    public var completed = false
    public var checkInAt: TimeInterval? = 25 * 60
    public init(task: WorkTask, now: Date = Date()) { self.task = task; startedAt = now; runningSince = now }
    public func elapsed(at now: Date = Date()) -> TimeInterval { accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    public mutating func pause(at now: Date = Date()) { accumulated = elapsed(at: now); runningSince = nil }
    public mutating func resume(at now: Date = Date()) { guard endedAt == nil, runningSince == nil else { return }; runningSince = now }
    public mutating func stop(done: Bool, at now: Date = Date()) { pause(at: now); endedAt = now; completed = done }
    public mutating func extend(minutes: Int, at now: Date = Date()) { checkInAt = elapsed(at: now) + Double(minutes * 60) }
}
public struct NotionSettings: Codable, Equatable {
    public var taskSource = ""
    public var projectSource = ""
    public var titleProperty = "Name"
    public var statusProperty = "Status"
    public var statusType = "status"
    public var inProgress = "In progress"
    public var done = "Done"
    public var projectProperty = "Project"
    public var startProperty = ""
    public init() {}
}
public struct PendingUpdate: Identifiable, Codable {
    public var id = UUID()
    public var pageID: String
    public var status: String
    public var start: Date?
    public var settings: NotionSettings
    public init(pageID: String, status: String, start: Date? = nil, settings: NotionSettings) { self.pageID = pageID; self.status = status; self.start = start; self.settings = settings }
}
public struct SavedState: Codable {
    public var tasks: [WorkTask] = []
    public var projects: [Project] = []
    public var sessions: [WorkSession] = []
    public var active: WorkSession?
    public var pending: [PendingUpdate] = []
    public var settings = NotionSettings()
    public var validatedSettings: NotionSettings?
    public var extensionMinutes = 5
    public var checkIns = true
    public init() {}
}
