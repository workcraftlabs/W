import Foundation

public struct TaskProperty: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    public let value: String
    public var defaultVisible: Bool {
        let words = name.lowercased().filter { $0.isLetter }
        return words == "due" || words == "duedate" || words.contains("estimate") || words == "timeest"
    }
    public static let supported: Set<String> = ["date", "number", "select", "multi_select", "status", "checkbox", "rich_text", "people", "url", "email", "phone_number", "formula", "rollup", "created_time", "last_edited_time", "unique_id"]
    public static func parse(_ properties: [String: [String: Any]]) -> [TaskProperty] {
        properties.compactMap { name, property in
            guard let type = property["type"] as? String, supported.contains(type) else { return nil }
            let text = format(property)
            let preview = text.count > 240 ? String(text.prefix(240)) + "…" : text
            return TaskProperty(id: property["id"] as? String ?? name, name: name, type: type, value: preview)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private static func format(_ property: [String: Any], depth: Int = 0) -> String {
        guard depth < 4, let type = property["type"] as? String else { return "" }
        let value = property[type]
        switch type {
        case "number": return (value as? NSNumber)?.stringValue ?? ""
        case "string", "url", "email", "phone_number", "created_time", "last_edited_time": return value as? String ?? ""
        case "checkbox", "boolean": return (value as? Bool).map { $0 ? "Yes" : "No" } ?? ""
        case "select", "status": return (value as? [String: Any])?["name"] as? String ?? ""
        case "multi_select", "people": return (value as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
        case "rich_text": return (value as? [[String: Any]] ?? []).map { $0["plain_text"] as? String ?? (($0["text"] as? [String: Any])?["content"] as? String ?? "") }.joined()
        case "date":
            guard let date = value as? [String: Any], let start = date["start"] as? String else { return "" }
            // Keep date-only values and explicit time zones intact; never shift a due day.
            let end = date["end"] as? String
            let zone = date["time_zone"] as? String
            return start + (end.map { " → " + $0 } ?? "") + (zone.map { " · " + $0 } ?? "")
        case "formula", "rollup":
            guard let nested = value as? [String: Any] else { return "" }
            if nested["type"] as? String == "array" {
                return (nested["array"] as? [[String: Any]] ?? []).map { format($0, depth: depth + 1) }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
            if ["incomplete", "unsupported"].contains(nested["type"] as? String ?? "") { return "Unavailable" }
            return format(nested, depth: depth + 1)
        case "unique_id":
            guard let unique = value as? [String: Any], let number = unique["number"] as? NSNumber else { return "" }
            let prefix = unique["prefix"] as? String ?? ""
            return (prefix.isEmpty ? "" : prefix + "-") + number.stringValue
        default: return ""
        }
    }
}
