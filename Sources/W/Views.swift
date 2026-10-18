import SwiftUI
import WCore

private let accent = Color(red: 0.76, green: 0.95, blue: 0.44)
struct IslandView: View {
    @ObservedObject var store: Store
    @StateObject var speech = SpeechInput()
    @State private var creating = false
    @State private var newTitle = ""
    @State private var projectID = ""
    @FocusState private var focused: Bool
    let dock: () -> Void
    let hide: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("w.").font(.system(size: 29, weight: .heavy, design: .rounded)).foregroundStyle(accent)
                Spacer()
                Text(store.state.active == nil ? "A LITTLE SPACE TO FOCUS" : "ONE THING AT A TIME").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.8).foregroundStyle(.secondary)
                Spacer()
                Button { speech.stop(); store.showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }.help("Settings")
                Button { speech.stop(); hide() } label: { Image(systemName: "minus") }.help("Hide · ⇧⌘W to reopen")
            }.buttonStyle(.plain)
            if store.showSettings { SettingsView(store: store) }
            else if let session = store.state.active {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        Circle().fill(session.runningSince == nil ? Color.orange : accent).frame(width: 6, height: 6)
                        Text(session.runningSince == nil ? "PAUSED" : "IN PROGRESS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                        Spacer()
                        Button { store.compact = true } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }.buttonStyle(.plain).help("Compact timer")
                        Button(action: dock) { Image(systemName: "rectangle.topthird.inset.filled") }.buttonStyle(.plain).help("Dock at top of current screen")
                    }.foregroundStyle(.secondary)
                    Text(session.task.title).font(.system(size: 27, weight: .medium)).fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    Text(session.task.project.isEmpty ? (session.task.remote ? "Notion task" : "Local task") : session.task.project).foregroundStyle(.secondary)
                    Text(store.timeText).font(.system(size: 68, weight: .light, design: .monospaced)).tracking(-4).contentTransition(.numericText())
                    HStack {
                        Button(session.runningSince == nil ? "Resume" : "Pause") { session.runningSince == nil ? store.resume() : store.pause() }.buttonStyle(PillStyle())
                        Button("Done", systemImage: "checkmark") { store.stop(done: true) }.buttonStyle(PillStyle(primary: true))
                    }
                    if store.checkIn {
                        Text("You've made time. What's next?").font(.headline)
                        HStack {
                            Button("+\(store.state.extensionMinutes) min") { store.extend() }
                            Button("Keep going") { store.keepGoing() }
                        }.buttonStyle(PillStyle())
                    } else {
                        Button("+\(store.state.extensionMinutes) min until next check-in") { store.extend() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Button("Stop for now") { store.stop(done: false) }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            } else if creating {
                Text("Make room for this.").font(.system(size: 27, weight: .medium))
                TextField("Task title", text: $newTitle).textFieldStyle(.roundedBorder)
                if !store.state.settings.taskSource.isEmpty {
                    Picker("Project", selection: $projectID) {
                        Text("No project").tag("")
                        ForEach(store.state.projects) { Text($0.title).tag($0.id) }
                    }
                }
                Text(store.state.settings.taskSource.isEmpty ? "This task will be saved on this Mac. Connect Notion in Settings to create tasks there." : "Creates a Notion task and starts a work session. Only the title and selected project are added.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Back") { creating = false }.buttonStyle(PillStyle())
                    Button("Create & start") { Task { await store.create(title: newTitle, projectID: projectID); if store.state.active != nil { creating = false } } }.buttonStyle(PillStyle(primary: true)).disabled(store.busy || newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are you\nworking on?").font(.system(size: 34, weight: .medium)).tracking(-1)
                    Text("Say it. Find it. Give it your attention.").foregroundStyle(.secondary).font(.system(size: 13))
                }
                HStack {
                    TextField("A task, a project, a place to start…", text: $store.query).textFieldStyle(.plain).focused($focused).onSubmit { if let task = store.matches.first?.task { speech.stop(); store.start(task) } }
                    Button { if speech.listening { speech.stop() } else { Task { await speech.start { store.query = $0 } } } } label: { Image(systemName: speech.listening ? "stop.circle.fill" : "mic.fill").foregroundStyle(speech.listening ? Color.red : accent) }.buttonStyle(.plain).help("Dictate on device")
                }.padding(16).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                if !speech.error.isEmpty { Text(speech.error).font(.caption).foregroundStyle(.orange) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if store.query.isEmpty {
                            Text("READY WHEN YOU ARE").font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                            ForEach(Array(store.state.tasks.filter { !$0.done }.prefix(3))) { task in taskRow(task) }
                            if store.state.tasks.isEmpty { Text("Start with a local task, or connect your Notion workspace in Settings.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 12) }
                        } else {
                            Text(store.matches.isEmpty ? "NO CLEAR MATCH" : "POSSIBLE MATCHES · SELECT TO START").font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                            ForEach(store.matches, id: \.task.id) { match in taskRow(match.task) }
                        }
                        Button {
                            speech.stop(); newTitle = store.query; projectID = ""; creating = true
                        } label: { Label("Create a new task", systemImage: "plus").foregroundStyle(accent).padding(.vertical, 12) }.buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            if !store.message.isEmpty { Text(store.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
            HStack {
                Circle().fill(store.state.pending.isEmpty ? accent : Color.orange).frame(width: 5, height: 5)
                Text(store.state.pending.isEmpty ? (store.state.settings.taskSource.isEmpty ? "LOCAL MODE" : "NOTION CONFIGURED") : "\(store.state.pending.count) UPDATES PENDING").font(.system(size: 9, design: .monospaced)).tracking(1)
                Spacer()
                if !store.state.pending.isEmpty { Button("Retry") { Task { await store.flush() } }.buttonStyle(.plain).disabled(store.syncing) }
                Text("⇧⌘W").font(.system(size: 11, design: .monospaced))
            }.foregroundStyle(.secondary)
        }
        .padding(26).frame(width: 440, height: 570)
        .background(Color(red: 0.055, green: 0.06, blue: 0.055), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.12)))
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: store.state.active == nil)
        .onAppear { focused = true }
        .onDisappear { speech.stop() }
        .onExitCommand { speech.stop(); hide() }
    }
    func taskRow(_ task: WorkTask) -> some View {
        Button { speech.stop(); store.start(task) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).foregroundStyle(.white).lineLimit(2)
                    Text(task.project.isEmpty ? (task.remote ? "Notion" : "On this Mac") : task.project).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!store.persistenceOK)
    }
}
struct PillStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(primary ? accent : Color.white.opacity(0.09), in: Capsule()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct SettingsView: View {
    @ObservedObject var store: Store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your workspace.").font(.system(size: 26, weight: .medium))
                Text("Connect an internal Notion integration with access to your task and project databases. Tokens stay in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                SecureField("Notion integration token", text: $store.token)
                field("Tasks data source ID", text: $store.state.settings.taskSource)
                field("Projects data source ID (optional)", text: $store.state.settings.projectSource)
                HStack { field("Title field", text: $store.state.settings.titleProperty); field("Status field", text: $store.state.settings.statusProperty) }
                Picker("Status type", selection: $store.state.settings.statusType) { Text("Status").tag("status"); Text("Select").tag("select") }
                HStack { field("In-progress value", text: $store.state.settings.inProgress); field("Done value", text: $store.state.settings.done) }
                field("Project relation field", text: $store.state.settings.projectProperty)
                field("Start date field (optional)", text: $store.state.settings.startProperty)
                Text("The start date field records the latest session start. Full session history stays on this Mac.").font(.caption2).foregroundStyle(.secondary)
                Button(store.busy ? "Connecting…" : "Connect / refresh tasks") { Task { await store.connect() } }.buttonStyle(PillStyle(primary: true)).disabled(store.busy || store.syncing || store.state.settings.taskSource.isEmpty)
                Divider()
                Toggle("Check in after 25 minutes", isOn: $store.state.checkIns).onChange(of: store.state.checkIns) { _, _ in store.save() }
                Picker("More time", selection: $store.state.extensionMinutes) { ForEach([5, 10, 15], id: \.self) { Text("\($0) minutes").tag($0) } }.onChange(of: store.state.extensionMinutes) { _, _ in store.save() }
                Text("Shortcut: ⇧⌘W · Drag the panel to place it anywhere. Sleep pauses tracking automatically.").font(.caption).foregroundStyle(.secondary)
                if !store.state.sessions.isEmpty {
                    Divider(); Text("Recent sessions").font(.headline)
                    ForEach(Array(store.state.sessions.prefix(8))) { session in
                        HStack { Text(session.task.title).lineLimit(1); Spacer(); Text("\(Int(session.accumulated / 60))m"); Image(systemName: session.completed ? "checkmark.circle" : "pause.circle") }.font(.caption)
                    }
                }
                Button("Quit W") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
            .disabled(store.busy || store.syncing)
        }
    }
    func field(_ label: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption2).foregroundStyle(.secondary); TextField(label, text: text) } }
}

struct PanelRoot: View {
    @ObservedObject var store: Store
    let dock: () -> Void
    let hide: () -> Void
    let resize: (Bool) -> Void
    var isCompact: Bool { store.compact && store.state.active != nil }
    var body: some View {
        Group {
            if isCompact, let session = store.state.active {
                VStack(spacing: 14) {
                    HStack {
                        Circle().fill(session.runningSince == nil ? Color.orange : accent).frame(width: 6, height: 6)
                        Text(session.task.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer()
                        Button { store.compact = false } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Expand timer")
                    }
                    HStack(spacing: 16) {
                        Text(store.timeText).font(.system(size: 30, weight: .light, design: .monospaced)).foregroundStyle(accent)
                        Spacer()
                        Button { session.runningSince == nil ? store.resume() : store.pause() } label: { Image(systemName: session.runningSince == nil ? "play.fill" : "pause.fill") }.help(session.runningSince == nil ? "Resume" : "Pause")
                        Button { store.extend() } label: { Text("+\(store.state.extensionMinutes)m").font(.caption) }.help("More time")
                        Button { store.stop(done: true) } label: { Image(systemName: "checkmark") }.help("Mark done")
                    }
                    if store.checkIn { Button("Time to check in →") { store.compact = false }.font(.caption).foregroundStyle(accent) }
                    else if !store.state.pending.isEmpty { Text("Notion sync pending · expand for details").font(.system(size: 9)).foregroundStyle(.orange) }
                }.buttonStyle(.plain).padding(20).frame(width: 360, height: 145)
                    .background(Color(red: 0.055, green: 0.06, blue: 0.055), in: RoundedRectangle(cornerRadius: 25))
                    .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Color.white.opacity(0.12)))
                    .preferredColorScheme(.dark)
            } else { IslandView(store: store, dock: dock, hide: hide) }
        }.onChange(of: isCompact) { _, compact in resize(compact) }
    }
}
