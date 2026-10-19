import SwiftUI
import WCore

extension Store {
    private var displayPropertiesKey: String { "taskDisplayProperties." + state.settings.taskSource.replacingOccurrences(of: "-", with: "").lowercased() }
    var availableTaskProperties: [TaskProperty] {
        guard state.settings.taskSource == state.validatedSettings?.taskSource else { return [] }
        return state.tasks.first { $0.remote && $0.properties != nil }?.properties ?? []
    }
    var selectedTaskPropertyIDs: [String] {
        UserDefaults.standard.stringArray(forKey: displayPropertiesKey) ?? availableTaskProperties.filter(\.defaultVisible).prefix(4).map(\.id)
    }
    func setTaskProperty(_ id: String, visible: Bool) {
        var selection = selectedTaskPropertyIDs.filter { $0 != id }
        if visible && selection.count < 4 { selection.append(id) }
        objectWillChange.send()
        UserDefaults.standard.set(selection, forKey: displayPropertiesKey)
    }
    func displayedProperties(for task: WorkTask) -> [TaskProperty] {
        guard task.remote else { return [] }
        let latest = state.tasks.first { $0.id == task.id } ?? task
        let properties = latest.properties ?? []
        return selectedTaskPropertyIDs.compactMap { id in properties.first { $0.id == id } }
    }
}

struct TaskPropertiesView: View {
    @ObservedObject var store: Store
    let task: WorkTask
    var compact = false
    var body: some View {
        let properties = store.displayedProperties(for: task)
        if !properties.isEmpty {
            if compact {
                Text(properties.map { "\($0.name): \($0.value.isEmpty ? "—" : $0.value)" }.joined(separator: "  ·  "))
                    .font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    .help(properties.map { "\($0.name): \($0.value.isEmpty ? "—" : $0.value)" }.joined(separator: "\n"))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(properties) { property in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(property.name).font(.custom("Inter", size: 9)).foregroundStyle(.secondary)
                                Text(property.value.isEmpty ? "—" : property.value).font(.custom("Inter", size: 11)).lineLimit(1)
                            }.padding(9).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                .help(property.value.isEmpty ? "Not set in Notion" : property.value)
                        }
                    }
                }.frame(height: 48)
            }
        }
    }
}

struct TaskPropertySettings: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Task details").font(.custom("Inter", size: 13)).fontWeight(.semibold)
            Text("Choose up to 4 properties to show in results and timers. Due dates and estimates are selected by default. Values update when you refresh tasks.")
                .font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
            if store.availableTaskProperties.isEmpty {
                Text("Connect / refresh tasks to load your database properties.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Visible properties (\(store.selectedTaskPropertyIDs.count)/4)") {
                    ForEach(store.availableTaskProperties) { property in
                        Toggle(property.name, isOn: Binding(get: { store.selectedTaskPropertyIDs.contains(property.id) }, set: { store.setTaskProperty(property.id, visible: $0) }))
                            .disabled(!store.selectedTaskPropertyIDs.contains(property.id) && store.selectedTaskPropertyIDs.count >= 4)
                    }
                }
            }
        }
    }
}
