import SwiftUI
import WCore

extension Store {
    var notionPeople: [NotionPerson] {
        guard let data = UserDefaults.standard.data(forKey: creationKey + ".people") else { return [] }
        return (try? JSONDecoder().decode([NotionPerson].self, from: data)) ?? []
    }
    var assigneeFieldID: String {
        if let saved = UserDefaults.standard.string(forKey: creationKey + ".assigneeField") { return saved }
        let fields = creationFields.filter { $0.type == "people" }
        return fields.first { $0.name.lowercased().filter(\.isLetter) == "assignedto" }?.id ?? (fields.count == 1 ? fields[0].id : "")
    }
    var defaultAssigneeID: String { UserDefaults.standard.string(forKey: creationKey + ".assignee") ?? "" }
    func setAssignee(_ value: String, field: Bool = false) {
        objectWillChange.send()
        UserDefaults.standard.set(value, forKey: creationKey + (field ? ".assigneeField" : ".assignee"))
    }
    func refreshAssignees() async throws {
        guard !state.settings.taskSource.isEmpty else { return }
        let key = creationKey
        let people = try await NotionClient(token: token).people()
        guard key == creationKey else { return }
        objectWillChange.send()
        UserDefaults.standard.set(try JSONEncoder().encode(people), forKey: key + ".people")
    }
    var newTaskFields: [CreationField] {
        creationFields.filter { enabledCreationIDs.contains($0.id) || ($0.id == assigneeFieldID && !defaultAssigneeID.isEmpty) }
    }
}

struct AssigneePreferences: View {
    @ObservedObject var store: Store
    @State private var error = ""
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default assignee").font(.custom("Inter", size: 13)).fontWeight(.semibold)
            Picker("People field", selection: Binding(get: { store.assigneeFieldID }, set: { store.setAssignee($0, field: true) })) {
                Text("None").tag("")
                ForEach(store.creationFields.filter { $0.type == "people" }) { Text($0.name).tag($0.id) }
            }
            Picker("Assign new tasks to", selection: Binding(get: { store.defaultAssigneeID }, set: { store.setAssignee($0) })) {
                Text("No default").tag("")
                ForEach(store.notionPeople) { Text($0.label).tag($0.id) }
                if !store.defaultAssigneeID.isEmpty && !store.notionPeople.contains(where: { $0.id == store.defaultAssigneeID }) {
                    Text("Saved member · refresh members").tag(store.defaultAssigneeID)
                }
            }.disabled(store.assigneeFieldID.isEmpty)
            Text("Prefills new tasks. Change or clear it before creating. Notion’s Created by field still identifies the integration.")
                .font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
            Button(loading ? "Loading members…" : "Refresh members") { Task { await refresh() } }.disabled(loading)
            if !error.isEmpty { Text(error).font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }
        }.task(id: store.state.settings.taskSource) { await refresh() }
    }
    private func refresh() async {
        guard !loading, !store.state.settings.taskSource.isEmpty else { return }
        loading = true; defer { loading = false }
        do { try await store.refreshAssignees(); error = "" }
        catch { self.error = "Couldn’t load workspace members. Check that the Notion integration can read user information. \(error.localizedDescription)" }
    }
}
