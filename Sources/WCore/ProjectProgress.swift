import Foundation

public struct ProjectProgress {
    public let field: String?
    private let type: String
    private let activeIDs: Set<String>
    public init(properties: [String: [String: Any]]) {
        let candidates = properties.filter { ["status", "select"].contains($0.value["type"] as? String ?? "") }
        let native = candidates.filter { $0.value["type"] as? String == "status" }
        field = candidates["Status"] != nil ? "Status" : (native.count == 1 ? native.keys.first : nil)
        let property = field.flatMap { properties[$0] } ?? [:]
        type = property["type"] as? String ?? "status"
        let config = property[type] as? [String: Any] ?? [:]
        let groups = config["groups"] as? [[String: Any]] ?? []
        let group = groups.first { Self.normalized($0["name"] as? String ?? "") == "inprogress" }
        activeIDs = Set(group?["option_ids"] as? [String] ?? [])
    }
    public func contains(_ properties: [String: [String: Any]]) -> Bool {
        guard let field, let value = properties[field]?[type] as? [String: Any] else { return false }
        if !activeIDs.isEmpty { return activeIDs.contains(value["id"] as? String ?? "") }
        return Self.normalized(value["name"] as? String ?? "") == "inprogress"
    }
    private static func normalized(_ value: String) -> String { value.lowercased().filter(\.isLetter) }
}
