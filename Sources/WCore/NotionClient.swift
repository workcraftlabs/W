import Foundation

public struct NotionError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
public struct NotionClient {
    let token: String
    public init(token: String) { self.token = token }
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard !token.isEmpty else { throw NotionError("Add your Notion integration token in Settings.") }
        guard let url = URL(string: "https://api.notion.com/v1/" + path) else { throw NotionError("Invalid Notion ID.") }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2025-09-03", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotionError("No response from Notion.") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            throw NotionError("Notion \(http.statusCode): \(json["message"] as? String ?? "Request failed")")
        }
        return json
    }
    public func discover(_ settings: NotionSettings) async throws -> NotionSchema {
        let schema = try await request("data_sources/\(settings.taskSource)")
        return try NotionSchema(properties: schema["properties"] as? [String: [String: Any]] ?? [:], settings: settings)
    }
    public func validate(_ settings: NotionSettings) async throws {
        let schema = try await request("data_sources/\(settings.taskSource)")
        let props = schema["properties"] as? [String: [String: Any]] ?? [:]
        guard props[settings.titleProperty]?["type"] as? String == "title" else {
            let titles = props.filter { $0.value["type"] as? String == "title" }.keys.sorted().joined(separator: ", ")
            throw NotionError("Title field ‘\(settings.titleProperty)’ does not match this database. Set Title field to: \(titles).")
        }
        guard props[settings.statusProperty]?["type"] as? String == settings.statusType else { throw NotionError("Status field type does not match Settings.") }
        let status = props[settings.statusProperty]?[settings.statusType] as? [String: Any]
        let names = (status?["options"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        guard names.contains(settings.inProgress), names.contains(settings.done) else { throw NotionError("Status values are case-sensitive. Set In-progress and Done to exact options from: \(names.joined(separator: ", ")).") }
        if !settings.startProperty.isEmpty, props[settings.startProperty]?["type"] as? String != "date" { throw NotionError("Start time property must be a date field.") }
        if !settings.projectSource.isEmpty {
            guard props[settings.projectProperty]?["type"] as? String == "relation" else { throw NotionError("Project property must be a relation.") }
            let relation = props[settings.projectProperty]?["relation"] as? [String: Any]
            let linked = relation?["data_source_id"] as? String ?? ""
            guard linked.replacingOccurrences(of: "-", with: "") == settings.projectSource.replacingOccurrences(of: "-", with: "") else { throw NotionError("Project data source must match the task's project relation.") }
        }
    }
    func allPages(_ source: String) async throws -> [[String: Any]] {
        var pages: [[String: Any]] = [], cursor: String?
        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            let result = try await request("data_sources/\(source)/query", method: "POST", body: body)
            pages += result["results"] as? [[String: Any]] ?? []
            cursor = result["has_more"] as? Bool == true ? result["next_cursor"] as? String : nil
        } while cursor != nil
        return pages
    }
    func title(_ property: [String: Any]) -> String {
        (property["title"] as? [[String: Any]] ?? []).map { $0["plain_text"] as? String ?? (($0["text"] as? [String: Any])?["content"] as? String ?? "") }.joined()
    }
    public func fetch(_ settings: NotionSettings) async throws -> ([WorkTask], [Project]) {
        try await validate(settings)
        var projects: [Project] = []
        if !settings.projectSource.isEmpty {
            for page in try await allPages(settings.projectSource) {
                let props = page["properties"] as? [String: [String: Any]] ?? [:]
                let name = props.values.first { $0["type"] as? String == "title" }.map(title) ?? "Untitled"
                if let id = page["id"] as? String { projects.append(Project(id: id, title: name)) }
            }
        }
        var tasks: [WorkTask] = []
        for page in try await allPages(settings.taskSource) {
            guard let id = page["id"] as? String else { continue }
            let props = page["properties"] as? [String: [String: Any]] ?? [:]
            let projectID = (props[settings.projectProperty]?["relation"] as? [[String: Any]])?.first?["id"] as? String
            let status = (props[settings.statusProperty]?[settings.statusType] as? [String: Any])?["name"] as? String
            tasks.append(WorkTask(id: id, title: title(props[settings.titleProperty] ?? [:]), projectID: projectID, project: projects.first { $0.id == projectID }?.title ?? "", done: status == settings.done, remote: true, properties: TaskProperty.parse(props)))
        }
        return (tasks, projects)
    }
    public func create(title: String, project: Project?, settings: NotionSettings, values: [String: CreationValue] = [:]) async throws -> WorkTask {
        let fields = values.isEmpty ? [] : try await creationFields(settings)
        let peopleIDs = fields.filter { $0.type == "people" }.flatMap { values[$0.id]?.options ?? [] }
        if !peopleIDs.isEmpty {
            let members = try await people()
            guard peopleIDs.allSatisfy({ id in members.contains { $0.id == id } }) else { throw NotionError("The selected assignee is no longer available. Refresh members in W Settings.") }
        }
        var properties = try CreationField.payload(fields: fields, values: values)
        properties[settings.titleProperty] = ["title": [["text": ["content": title]]]]
        if let project { properties[settings.projectProperty] = ["relation": [["id": project.id]]] }
        let page = try await request("pages", method: "POST", body: ["parent": ["type": "data_source_id", "data_source_id": settings.taskSource], "properties": properties])
        guard let id = page["id"] as? String else { throw NotionError("Notion did not return the new task ID. Refresh before trying again.") }
        return WorkTask(id: id, title: title, projectID: project?.id, project: project?.title ?? "", remote: true, properties: TaskProperty.parse(page["properties"] as? [String: [String: Any]] ?? [:]))
    }
    public func apply(_ update: PendingUpdate) async throws {
        let s = update.settings
        var properties: [String: Any] = [s.statusProperty: [s.statusType: ["name": update.status]]]
        if let start = update.start, !s.startProperty.isEmpty { properties[s.startProperty] = ["date": ["start": ISO8601DateFormatter().string(from: start)]] }
        _ = try await request("pages/\(update.pageID)", method: "PATCH", body: ["properties": properties])
    }
}
