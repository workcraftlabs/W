import Foundation

public struct NotionSchema {
    public var titles: [String]
    public var statusFields: [String: [String]]
    public var statusTypes: [String: String]
    public var relations: [String]
    public var dates: [String]
    public var suggested: NotionSettings

    public init(properties: [String: [String: Any]], settings: NotionSettings) throws {
        titles = properties.filter { $0.value["type"] as? String == "title" }.keys.sorted()
        relations = properties.filter { $0.value["type"] as? String == "relation" }.keys.sorted()
        dates = properties.filter { $0.value["type"] as? String == "date" }.keys.sorted()
        statusFields = [:]; statusTypes = [:]
        for (name, property) in properties {
            guard let type = property["type"] as? String, ["status", "select"].contains(type) else { continue }
            let config = property[type] as? [String: Any] ?? [:]
            statusFields[name] = (config["options"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            statusTypes[name] = type
        }
        var result = settings
        if result.sessionDateProperty == nil {
            result.sessionDateProperty = dates.contains("Due") ? "Due" : (dates.contains("Date") ? "Date" : "")
        }
        guard let title = titles.first else { throw NotionError("This data source has no title field.") }
        if !titles.contains(result.titleProperty) { result.titleProperty = title }
        if statusFields[result.statusProperty] == nil {
            let native = statusTypes.filter { $0.value == "status" }.keys.sorted()
            let choices = native.isEmpty ? statusFields.keys.sorted() : native
            guard choices.count == 1, let name = choices.first else {
                throw NotionError("Choose a Status field in Settings. Available fields: \(choices.joined(separator: ", ")).")
            }
            result.statusProperty = name
        }
        result.statusType = statusTypes[result.statusProperty] ?? "status"
        let config = properties[result.statusProperty]?[result.statusType] as? [String: Any] ?? [:]
        let options = config["options"] as? [[String: Any]] ?? []
        let groups = config["groups"] as? [[String: Any]] ?? []
        let names = statusFields[result.statusProperty] ?? []
        func normalized(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
        func resolve(_ current: String, groupName: String) -> String {
            if names.contains(current) { return current }
            if let equivalent = names.first(where: { normalized($0) == normalized(current) }) { return equivalent }
            let group = groups.first { normalized($0["name"] as? String ?? "") == normalized(groupName) }
            let ids = group?["option_ids"] as? [String] ?? []
            // Auto-select only an unambiguous group; preserve the value for manual correction otherwise.
            let candidates = options.filter { ids.contains($0["id"] as? String ?? "") }.compactMap { $0["name"] as? String }
            return candidates.count == 1 ? candidates[0] : current
        }
        result.inProgress = resolve(result.inProgress, groupName: "In progress")
        result.done = resolve(result.done, groupName: "Complete")
        if !result.projectSource.isEmpty {
            let linked = relations.filter { name in
                let relation = properties[name]?["relation"] as? [String: Any] ?? [:]
                return (relation["data_source_id"] as? String ?? "").replacingOccurrences(of: "-", with: "").lowercased() == result.projectSource.replacingOccurrences(of: "-", with: "").lowercased()
            }
            if !linked.contains(result.projectProperty), linked.count == 1 { result.projectProperty = linked[0] }
        }
        suggested = result
    }
}
