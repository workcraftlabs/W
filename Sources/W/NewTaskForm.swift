import SwiftUI
import WCore

struct NewTaskForm: View {
    @ObservedObject var store: Store
    @Binding var title: String
    @Binding var projectID: String
    let back: () -> Void
    @State private var values: [String: CreationValue] = [:]
    @State private var loading = true
    @State private var error = ""
    var fields: [CreationField] { store.creationFields.filter { store.enabledCreationIDs.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New task").font(.custom("Inter", size: 27)).fontWeight(.medium)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Task title", text: $title)
                    if !store.state.settings.taskSource.isEmpty {
                        Picker("Project", selection: $projectID) {
                            Text("No project").tag("")
                            ForEach(store.state.projects) { Text($0.title).tag($0.id) }
                        }
                        ForEach(fields) { field in editor(field) }
                    }
                    if loading { ProgressView().controlSize(.small) }
                    if !error.isEmpty { Text(error).font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }
                }.textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Back", action: back).buttonStyle(PillStyle())
                Button(store.busy ? "Creating…" : "Create & start") {
                    Task {
                        let selected = values.filter { store.enabledCreationIDs.contains($0.key) }
                        do {
                            _ = try CreationField.payload(fields: fields, values: selected)
                            error = ""
                            await store.create(title: title, projectID: projectID, values: selected)
                        } catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(PillStyle(primary: true)).disabled(loading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.disabled(store.busy)
        .task {
            do {
                try await store.refreshCreationFields()
                for field in fields where field.type == "date" && store.todayCreationIDs.contains(field.id) && values[field.id] == nil {
                    var value = values[field.id] ?? CreationValue()
                    value.date = CreationValue.dayFormatter.string(from: Date())
                    values[field.id] = value
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    private func value(_ field: CreationField) -> Binding<CreationValue> {
        Binding(get: { values[field.id] ?? CreationValue() }, set: { values[field.id] = $0 })
    }
    @ViewBuilder private func editor(_ field: CreationField) -> some View {
        let binding = value(field)
        VStack(alignment: .leading, spacing: 5) {
            Text(field.name).font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
            switch field.type {
            case "select":
                Picker(field.name, selection: Binding(get: { binding.wrappedValue.options.first ?? "" }, set: { binding.wrappedValue.options = $0.isEmpty ? [] : [$0] })) {
                    Text("Not set").tag("")
                    ForEach(field.options, id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
            case "multi_select":
                ForEach(field.options, id: \.self) { option in
                    Toggle(option, isOn: Binding(get: { binding.wrappedValue.options.contains(option) }, set: { selected in
                        var options = binding.wrappedValue.options.filter { $0 != option }
                        if selected { options.append(option) }
                        binding.wrappedValue.options = options
                    }))
                }
                if field.options.isEmpty { Text("No options in Notion").foregroundStyle(.secondary) }
            case "date":
                Toggle("Set date", isOn: Binding(get: { binding.wrappedValue.date != nil }, set: { binding.wrappedValue.date = $0 ? CreationValue.dayFormatter.string(from: Date()) : nil }))
                if binding.wrappedValue.date != nil {
                    DatePicker(field.name, selection: Binding(get: { CreationValue.dayFormatter.date(from: binding.wrappedValue.date ?? "") ?? Date() }, set: { binding.wrappedValue.date = CreationValue.dayFormatter.string(from: $0) }), displayedComponents: .date).labelsHidden()
                }
            case "checkbox": Toggle(field.name, isOn: Binding(get: { binding.wrappedValue.checked ?? false }, set: { binding.wrappedValue.checked = $0 }))
            default: TextField(field.type == "number" ? "Number, e.g. 30" : field.name, text: binding.text)
            }
        }
    }
}
