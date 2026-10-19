import SwiftUI
import WCore

struct SearchRequest: Identifiable {
    let id = UUID()
    let query: String
}

struct SearchChoicesView: View {
    @ObservedObject var chat: ChatGPT
    @ObservedObject var store: Store
    let request: SearchRequest?
    let editing: Bool
    @Binding var searching: Bool
    let search: () -> Void
    let edit: (AIProposal) -> Void
    @State private var resultID: UUID?
    @State private var matches: [WorkTask] = []
    @State private var proposal: AIProposal?
    @State private var source = ""
    @State private var notice = ""

    private var ready: Bool { request != nil && resultID == request?.id && !searching }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if searching {
                    ProgressView().controlSize(.small)
                    Text("Finding your task…").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                } else {
                    Text(ready ? source : (chat.connected ? "ChatGPT · uses your plan" : "Basic matching · no AI needed"))
                        .font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: search) {
                        HStack(spacing: 5) {
                            Text(ready ? "Try again" : "Search")
                            Image(systemName: "return").font(.system(size: 10))
                        }.font(.custom("Inter", size: 11))
                    }.buttonStyle(.plain).help("Press Enter to search")
                        .disabled(store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if ready, let proposal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let first = matches.first {
                            Button { store.start(first) } label: {
                                choice("1", title: first.title, detail: "Start existing task" + (first.project.isEmpty ? "" : " · \(first.project)"), task: first)
                            }.buttonStyle(.plain)
                                .choiceShortcut("1", enabled: !editing)
                        } else {
                            Text("No matching task found").font(.custom("Inter", size: 13)).foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await store.create(title: proposal.title, projectID: proposal.projectID ?? "") }
                        } label: {
                            choice("2", title: proposal.title, detail: "Create & start · \(projectName(proposal.projectID))")
                        }.buttonStyle(.plain)
                            .choiceShortcut("2", enabled: !editing)
                        Button("Edit new task details") { edit(proposal) }
                            .buttonStyle(.plain).font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                        if !proposal.explanation.isEmpty {
                            Text(proposal.explanation).font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                        }
                        if matches.count > 1 {
                            Text("OTHER MATCHES").font(.custom("Inter", size: 9)).foregroundStyle(.secondary)
                            ForEach(Array(matches.dropFirst())) { task in
                                Button { store.start(task) } label: {
                                    choice("·", title: task.title, detail: task.project.isEmpty ? "Start existing task" : task.project, task: task)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.disabled(store.busy || !store.persistenceOK)
                }
                if !notice.isEmpty { Text(notice).font(.custom("Inter", size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            }
        }
        .task(id: request?.id) { await runSearch() }
    }

    private func choice(_ key: String, title: String, detail: String, task: WorkTask? = nil) -> some View {
        HStack(spacing: 12) {
            Text(key).font(.custom("Inter", size: 12)).frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.custom("Inter", size: 13)).lineLimit(2)
                Text(detail).font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                if let task { TaskPropertiesView(store: store, task: task, compact: true) }
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }
    private func projectName(_ id: String?) -> String {
        store.state.projects.first { $0.id == id }?.title ?? (store.state.settings.taskSource.isEmpty ? "On this Mac" : "No project")
    }
    @MainActor private func runSearch() async {
        resultID = nil; proposal = nil; matches = []; notice = ""
        guard let request else { searching = false; return }
        searching = true
        defer { if self.request?.id == request.id { searching = false } }
        let basic = Matcher.ranked(request.query, tasks: store.state.tasks).map(\.task)
        var found = basic
        var suggestion = AIProposal(taskID: basic.first?.id, title: request.query.trimmingCharacters(in: .whitespacesAndNewlines), projectID: nil, explanation: "")
        var label = "Choose a task"
        if chat.connected {
            do {
                let rest = store.state.tasks.filter { task in !basic.contains { $0.id == task.id } }
                suggestion = try await chat.match(query: request.query, tasks: basic + rest, projects: store.state.projects)
                try Task.checkCancellation()
                if let id = suggestion.taskID, let task = store.state.tasks.first(where: { $0.id == id && !$0.done }) {
                    found = [task] + basic.filter { $0.id != id }
                } else { found = basic }
                label = "ChatGPT · choose to start"
            } catch {
                guard !Task.isCancelled else { return }
                notice = "ChatGPT unavailable. Showing basic matches."
            }
        }
        guard !Task.isCancelled, self.request?.id == request.id, store.query == request.query else { return }
        matches = found; proposal = suggestion; source = label; resultID = request.id
    }
}

private extension View {
    @ViewBuilder func choiceShortcut(_ key: KeyEquivalent, enabled: Bool) -> some View {
        if enabled { keyboardShortcut(key, modifiers: []) } else { self }
    }
}
