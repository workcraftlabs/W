import SwiftUI
import WCore

extension Store {
    var defaultInterval: Int {
        let minutes = state.focusMinutes ?? 25
        return SessionTiming.intervals.contains(minutes) ? minutes : 25
    }
    var activeProjects: [Project] { state.projects.filter { $0.inProgress == true }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    func setSessionProject(_ id: String) {
        guard let session = state.active, session.task.remote, id.isEmpty || activeProjects.contains(where: { $0.id == id }) else { return }
        let settings = session.notionSettings ?? state.settings
        guard !settings.projectSource.isEmpty else { return }
        let project = activeProjects.first { $0.id == id }
        state.active?.task.projectID = project?.id
        state.active?.task.project = project?.title ?? ""
        if let index = state.tasks.firstIndex(where: { $0.id == session.task.id }) {
            state.tasks[index].projectID = project?.id
            state.tasks[index].project = project?.title ?? ""
        }
        state.pending.append(PendingUpdate(pageID: session.task.id, status: settings.inProgress, settings: settings, projectID: id))
        save(); Task { await flush() }
    }
    func queueSessionDate() {
        guard let session = state.active, session.task.remote, let date = session.sessionDate else { return }
        let settings = session.notionSettings ?? state.settings
        state.pending.append(PendingUpdate(pageID: session.task.id, status: settings.inProgress, settings: settings, dateValue: date))
        updateCachedDate(taskID: session.task.id, date: date, settings: settings)
    }
    func updateCachedDate(taskID: String, date: SessionDate, settings: NotionSettings) {
        guard let field = settings.sessionDateProperty, !field.isEmpty else { return }
        let old = state.tasks.first { $0.id == taskID }?.properties?.first { $0.name == field }
        let parsed = TaskProperty.parse([field: ["id": old?.id ?? field, "type": "date", "date": date.payload]])
        func updating(_ task: WorkTask) -> WorkTask {
            var result = task
            result.properties = (task.properties ?? []).filter { $0.name != field } + parsed
            return result
        }
        if let index = state.tasks.firstIndex(where: { $0.id == taskID }) { state.tasks[index] = updating(state.tasks[index]) }
        if let task = state.active?.task, task.id == taskID { state.active?.task = updating(task) }
    }
}

struct SessionProjectPicker: View {
    @ObservedObject var store: Store
    var body: some View {
        if let task = store.state.active?.task, task.remote, !store.state.settings.projectSource.isEmpty {
            Picker("Project", selection: Binding(get: { store.state.active?.task.projectID ?? "" }, set: { store.setSessionProject($0) })) {
                Text("No project").tag("")
                if let id = task.projectID, !store.activeProjects.contains(where: { $0.id == id }) {
                    Text("\(task.project) · current").tag(id).disabled(true)
                }
                ForEach(store.activeProjects) { Text($0.title).tag($0.id) }
            }.font(.custom("Inter", size: 11))
                .help("Only projects with an In Progress status are available.")
        }
    }
}

struct SessionTimerContents: View {
    @ObservedObject var store: Store
    var compact: Bool
    var body: some View {
        if store.checkIn {
            VStack(spacing: compact ? 6 : 16) {
                Image(systemName: "stopwatch").font(.system(size: compact ? 20 : 38, weight: .light))
                Text("Interval complete").font(.custom("Inter", size: 12)).foregroundStyle(.secondary)
                Text(store.timeText).font(.custom("Inter", size: compact ? 28 : 52)).monospacedDigit()
                HStack {
                    Button("Keep going") { store.keepGoing() }.buttonStyle(PillStyle(primary: true))
                    Button("Stop") { store.stop(done: false) }.buttonStyle(PillStyle())
                }
            }.frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: compact ? 8 : 14) {
                SessionProjectPicker(store: store)
                if let task = store.state.active?.task { TaskPropertiesView(store: store, task: task, compact: compact) }
                HStack {
                    Text(store.timeText).font(.custom("Inter", size: compact ? 28 : 52)).fontWeight(.light).monospacedDigit()
                    Spacer()
                    Button { store.state.active?.runningSince == nil ? store.resume() : store.pause() } label: {
                        Image(systemName: store.state.active?.runningSince == nil ? "play.fill" : "pause.fill")
                    }.help(store.state.active?.runningSince == nil ? "Resume" : "Pause")
                    Button { store.stop(done: true) } label: { Image(systemName: "checkmark") }.help("Mark done")
                }.buttonStyle(.plain)
                if !compact {
                    Text("\(store.state.active?.intervalMinutes ?? store.defaultInterval)-minute interval").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                    Button("Stop for now") { store.stop(done: false) }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
    }
}
