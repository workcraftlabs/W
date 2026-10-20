import Foundation

public enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case notes, journal
    public var id: String { rawValue }
    public var title: String { self == .notes ? "Notes" : "Journal" }
}
public struct CaptureDraft: Codable, Equatable {
    public var title = ""
    public var body = ""
    public init() {}
}
public struct CaptureDestination: Codable, Equatable {
    public var location = ""
    public var sourceID = ""
    public var titleProperty = ""
    public var dateProperty = ""
    public var dateFields: [String] = []
    public var verifiedAt: Date?
    public var tokenFingerprint: String?
    public init() {}
    public var configured: Bool { !sourceID.isEmpty && !titleProperty.isEmpty && verifiedAt != nil }
}
public struct CaptureRecord: Codable, Identifiable {
    public var id: String
    public var kind: CaptureKind
    public var title: String
    public var createdAt: Date
    public init(id: String, kind: CaptureKind, title: String, createdAt: Date = Date()) {
        self.id = id; self.kind = kind; self.title = title; self.createdAt = createdAt
    }
}
public enum CaptureContent {
    public static func notionID(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ignore view IDs in query parameters; extract only the last path component.
        let candidate = value.contains("://") ? (URLComponents(string: value)?.path.split(separator: "/").last.map(String.init) ?? "") : value
        let compact = candidate.replacingOccurrences(of: "-", with: "")
        let suffix = String(compact.suffix(32))
        guard suffix.count == 32, suffix.allSatisfy({ $0.isHexDigit }) else { throw NotionError("Paste a Notion database link or a database / data source ID.") }
        let formatted = "\(suffix.prefix(8))-\(suffix.dropFirst(8).prefix(4))-\(suffix.dropFirst(12).prefix(4))-\(suffix.dropFirst(16).prefix(4))-\(suffix.suffix(12))"
        guard let id = UUID(uuidString: formatted) else { throw NotionError("Invalid Notion ID.") }
        return id.uuidString.lowercased()
    }
    public static func title(for draft: CaptureDraft, kind: CaptureKind, at date: Date = Date()) -> String {
        let entered = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty { return entered }
        if kind == .journal { return "Journal · " + date.formatted(date: .abbreviated, time: .omitted) }
        return String((draft.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled note").prefix(80))
    }
    public static func payload(draft: CaptureDraft, kind: CaptureKind, destination: CaptureDestination, at date: Date = Date()) throws -> [String: Any] {
        let name = title(for: draft, kind: kind, at: date)
        guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NotionError("Write something before saving.") }
        guard name.count <= 500 else { throw NotionError("Keep the title under 500 characters.") }
        guard draft.body.count <= 100_000 else { throw NotionError("Keep entries under 100,000 characters.") }
        // Each block holds up to 2,000 Unicode scalars. Preserve all text and line breaks.
        let scalars = Array(draft.body.unicodeScalars)
        let blocks: [[String: Any]] = stride(from: 0, to: scalars.count, by: 2000).map { offset in
            let text = String(String.UnicodeScalarView(scalars[offset..<min(offset + 2000, scalars.count)]))
            return ["object": "block", "type": "paragraph", "paragraph": ["rich_text": [["type": "text", "text": ["content": text]]]]]
        }
        guard blocks.count <= 100 else { throw NotionError("This entry is too long. Split it into two entries.") }
        var properties: [String: Any] = [destination.titleProperty: ["title": [["text": ["content": name]]]]]
        if !destination.dateProperty.isEmpty { properties[destination.dateProperty] = ["date": SessionDate.today(at: date).payload] }
        return ["parent": ["type": "data_source_id", "data_source_id": destination.sourceID], "properties": properties, "children": blocks]
    }
}
public extension NotionClient {
    func captureDestination(location: String) async throws -> CaptureDestination {
        let id = try CaptureContent.notionID(location)
        var source: [String: Any]
        do { source = try await request("data_sources/\(id)") }
        catch {
            let database = try await request("databases/\(id)")
            let sources = database["data_sources"] as? [[String: Any]] ?? []
            guard sources.count == 1, let sourceID = sources.first?["id"] as? String else {
                throw NotionError("This database has multiple data sources. Paste the specific data source ID.")
            }
            source = try await request("data_sources/\(sourceID)")
        }
        let properties = source["properties"] as? [String: [String: Any]] ?? [:]
        guard let sourceID = source["id"] as? String, let title = properties.first(where: { $0.value["type"] as? String == "title" })?.key else { throw NotionError("Choose a database with a title property.") }
        var result = CaptureDestination()
        result.location = location; result.sourceID = sourceID; result.titleProperty = title
        result.dateFields = properties.filter { $0.value["type"] as? String == "date" }.keys.sorted()
        result.dateProperty = result.dateFields.contains("Date") ? "Date" : ""
        result.verifiedAt = Date()
        return result
    }
    func createCapture(draft: CaptureDraft, kind: CaptureKind, destination: CaptureDestination) async throws -> CaptureRecord {
        // Validate before POST. Creation is never automatically retried.
        let schema = try await request("data_sources/\(destination.sourceID)")
        let props = schema["properties"] as? [String: [String: Any]] ?? [:]
        guard props[destination.titleProperty]?["type"] as? String == "title", destination.dateProperty.isEmpty || props[destination.dateProperty]?["type"] as? String == "date" else { throw NotionError("Database fields changed. Verify this location again in Settings.") }
        let payload = try CaptureContent.payload(draft: draft, kind: kind, destination: destination)
        let page = try await request("pages", method: "POST", body: payload)
        guard let id = page["id"] as? String else { throw NotionError("Notion did not confirm the new page. Check the database before retrying.") }
        return CaptureRecord(id: id, kind: kind, title: CaptureContent.title(for: draft, kind: kind))
    }
}
public enum CompletionHistory {
    public static func latest(_ sessions: [WorkSession]) -> [WorkSession] {
        var seen: Set<String> = []
        return sessions.filter { $0.completed && $0.endedAt != nil }
            .sorted { $0.endedAt! > $1.endedAt! }
            .filter { seen.insert($0.task.id).inserted }
    }
}
