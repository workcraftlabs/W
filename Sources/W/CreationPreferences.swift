import SwiftUI
import WCore

extension Store {
    var creationKey: String { "creation." + state.settings.taskSource.replacingOccurrences(of: "-", with: "").lowercased() }
    var creationFields: [CreationField] {
        guard let data = UserDefaults.standard.data(forKey: creationKey + ".schema") else { return [] }
        return (try? JSONDecoder().decode([CreationField].self, from: data)) ?? []
    }
    var enabledCreationIDs: [String] {
        UserDefaults.standard.stringArray(forKey: creationKey + ".enabled") ?? creationFields.filter {
            let name = $0.name.lowercased().filter(\.isLetter)
            return name == "due" || name == "duedate" || name == "timeest" || name.contains("estimate")
        }.map(\.id)
    }
    var todayCreationIDs: [String] { UserDefaults.standard.stringArray(forKey: creationKey + ".today") ?? [] }
    func setCreationPreference(_ id: String, enabled: Bool, today: Bool = false) {
        var values = today ? todayCreationIDs : enabledCreationIDs
        values.removeAll { $0 == id }
        if enabled { values.append(id) }
        objectWillChange.send()
        UserDefaults.standard.set(values, forKey: creationKey + (today ? ".today" : ".enabled"))
    }
    func refreshCreationFields() async throws {
        guard !state.settings.taskSource.isEmpty else { return }
        let source = state.settings.taskSource
        let key = creationKey
        let fields = try await NotionClient(token: token).creationFields(state.settings)
        guard source == state.settings.taskSource else { return }
        objectWillChange.send()
        UserDefaults.standard.set(try JSONEncoder().encode(fields), forKey: key + ".schema")
    }
}

struct CreationPreferences: View {
    @ObservedObject var store: Store
    @State private var error = ""
    var body: some View {
        DisclosureGroup("New task fields") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose fields to edit before creating a task. Title and project are shown separately; W manages status. Formulas and rollups are excluded.")
                    .font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                AssigneePreferences(store: store)
                Divider()
                ForEach(store.creationFields) { field in
                    Toggle(field.name, isOn: Binding(get: { store.enabledCreationIDs.contains(field.id) }, set: { store.setCreationPreference(field.id, enabled: $0) }))
                    if field.type == "date", store.enabledCreationIDs.contains(field.id) {
                        Toggle("Default \(field.name) to today", isOn: Binding(get: { store.todayCreationIDs.contains(field.id) }, set: { store.setCreationPreference(field.id, enabled: $0, today: true) }))
                            .font(.custom("Inter", size: 11)).padding(.leading, 16)
                    }
                }
                if store.creationFields.isEmpty { Text("Connect Notion to load editable fields.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }
                if !error.isEmpty { Text(error).font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }
            }
        }.task(id: store.state.settings.taskSource) {
            do { try await store.refreshCreationFields(); error = "" } catch { self.error = error.localizedDescription }
        }
    }
}
