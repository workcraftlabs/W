import Foundation

public struct CreationField: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let type: String
    public let options: [String]
    public static func parse(_ properties: [String: [String: Any]], settings: NotionSettings) -> [CreationField] {
        let supported: Set<String> = ["rich_text", "number", "select", "multi_select", "date", "checkbox", "url", "email", "phone_number"]
        return properties.compactMap { name, property in
            guard name != settings.statusProperty, name != settings.titleProperty, name != settings.projectProperty,
                  let type = property["type"] as? String, supported.contains(type), property["readOnly"] as? Bool != true else { return nil }
            let config = property[type] as? [String: Any] ?? [:]
            return CreationField(id: property["id"] as? String ?? name, name: name, type: type,
                options: (config["options"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func payload(fields: [CreationField], values: [String: CreationValue]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for (id, value) in values {
            guard let field = fields.first(where: { $0.id == id }) else { throw NotionError("A selected field is no longer editable. Refresh the new-task form.") }
            let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch field.type {
            case "rich_text":
                if !text.isEmpty {
                    guard text.count <= 2000 else { throw NotionError("\(field.name) must be 2,000 characters or fewer.") }
                    result[id] = ["rich_text": [["text": ["content": text]]]]
                }
            case "number":
                if !text.isEmpty {
                    guard let number = Double(text), number.isFinite else { throw NotionError("Enter a valid number for \(field.name), such as 30 or 1.5.") }
                    result[id] = ["number": number]
                }
            case "select", "multi_select":
                guard value.options.allSatisfy(field.options.contains), field.type != "select" || value.options.count <= 1 else { throw NotionError("Choose existing options for \(field.name). Refresh if the options changed.") }
                if !value.options.isEmpty {
                    result[id] = field.type == "select" ? ["select": ["name": value.options[0]]] : ["multi_select": value.options.map { ["name": $0] }]
                }
            case "date":
                if let day = value.date {
                    guard let parsed = CreationValue.dayFormatter.date(from: day), CreationValue.dayFormatter.string(from: parsed) == day else { throw NotionError("Choose a valid date for \(field.name).") }
                    result[id] = ["date": ["start": day]]
                }
            case "checkbox": if let checked = value.checked { result[id] = ["checkbox": checked] }
            case "url", "email", "phone_number": if !text.isEmpty { result[id] = [field.type: text] }
            default: throw NotionError("\(field.name) is not editable in W.")
            }
        }
        return result
    }
}
public struct CreationValue: Codable, Equatable {
    public var text = ""
    public var options: [String] = []
    public var date: String?
    public var checked: Bool?
    public init() {}
    public static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
public extension NotionClient {
    func creationFields(_ settings: NotionSettings) async throws -> [CreationField] {
        let schema = try await request("data_sources/\(settings.taskSource)")
        return CreationField.parse(schema["properties"] as? [String: [String: Any]] ?? [:], settings: settings)
    }
}
