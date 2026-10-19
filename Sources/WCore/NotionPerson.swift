import Foundation

public struct NotionPerson: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let email: String?
    public var label: String { email.map { "\(name) · \($0)" } ?? "\(name) · \(id.suffix(6))" }
    public static func parse(_ users: [[String: Any]]) -> [NotionPerson] {
        users.compactMap { user in
            guard user["type"] as? String == "person", let id = user["id"] as? String, UUID(uuidString: id) != nil else { return nil }
            return NotionPerson(id: id, name: user["name"] as? String ?? "Workspace member", email: (user["person"] as? [String: Any])?["email"] as? String)
        }
    }
}
public extension NotionClient {
    func people() async throws -> [NotionPerson] {
        var people: [NotionPerson] = []
        var cursor: String?
        repeat {
            var query = URLComponents()
            query.queryItems = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { query.queryItems?.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            let response = try await request("users?" + (query.percentEncodedQuery ?? ""))
            people += NotionPerson.parse(response["results"] as? [[String: Any]] ?? [])
            cursor = response["has_more"] as? Bool == true ? response["next_cursor"] as? String : nil
        } while cursor != nil
        return people.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}
public extension CreationValue {
    static func assigningDefault(_ values: [String: CreationValue], fieldID: String, personID: String) -> [String: CreationValue] {
        guard !fieldID.isEmpty, !personID.isEmpty, values[fieldID] == nil else { return values }
        var result = values
        var value = CreationValue(); value.options = [personID]
        result[fieldID] = value
        return result
    }
}
