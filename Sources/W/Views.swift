import SwiftUI
import WCore

private let accent = Color.primary
private let surface = Color(nsColor: .windowBackgroundColor)
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
                Text("W").font(.custom("Inter", size: 19)).fontWeight(.heavy).foregroundStyle(accent)
                Spacer()
                Text(store.state.active == nil ? "FOCUS" : "SESSION").font(.custom("Inter", size: 9)).fontWeight(.semibold).tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                Button { speech.stop(); store.showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }.help("Settings")
                Button { speech.stop(); hide() } label: { Image(systemName: "minus") }.help("Hide · ⇧⌘W to reopen")
            }.buttonStyle(.plain)
            if store.showSettings { SettingsView(store: store) }
            else if let session = store.state.active {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        Circle().fill(session.runningSince == nil ? Color.secondary : accent).frame(width: 6, height: 6)
                        Text(session.runningSince == nil ? "PAUSED" : "IN PROGRESS").font(.custom("Inter", size: 10)).fontWeight(.medium).tracking(0.5)
                        Spacer()
                        Button { store.compact = true } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }.buttonStyle(.plain).help("Compact timer")
                        Button(action: dock) { Image(systemName: "rectangle.topthird.inset.filled") }.buttonStyle(.plain).help("Dock at top of current screen")
                    }.foregroundStyle(.secondary)
                    Text(session.task.title).font(.custom("Inter", size: 27)).fontWeight(.medium).fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    Text(session.task.project.isEmpty ? (session.task.remote ? "Notion task" : "Local task") : session.task.project).foregroundStyle(.secondary)
                    Text(store.timeText).font(.custom("Inter", size: 60)).fontWeight(.light).monospacedDigit().contentTransition(.numericText())
                    HStack {
                        Button(session.runningSince == nil ? "Resume" : "Pause") { session.runningSince == nil ? store.resume() : store.pause() }.buttonStyle(PillStyle())
                        Button("Done", systemImage: "checkmark") { store.stop(done: true) }.buttonStyle(PillStyle(primary: true))
                    }
                    if store.checkIn {
                        Text("You've made time. What's next?").font(.custom("Inter", size: 13)).fontWeight(.semibold)
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
                Text("Make room for this.").font(.custom("Inter", size: 27)).fontWeight(.medium)
                TextField("Task title", text: $newTitle).textFieldStyle(.roundedBorder)
                if !store.state.settings.taskSource.isEmpty {
                    Picker("Project", selection: $projectID) {
                        Text("No project").tag("")
                        ForEach(store.state.projects) { Text($0.title).tag($0.id) }
                    }
                }
                Text(store.state.settings.taskSource.isEmpty ? "This task will be saved on this Mac. Connect Notion in Settings to create tasks there." : "Creates a Notion task and starts a work session. Only the title and selected project are added.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Back") { creating = false }.buttonStyle(PillStyle())
                    Button("Create & start") { Task { await store.create(title: newTitle, projectID: projectID); if store.state.active != nil { creating = false } } }.buttonStyle(PillStyle(primary: true)).disabled(store.busy || newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are you working on?").font(.custom("Inter", size: 25)).fontWeight(.medium).tracking(-1)
                    Text("Find a task. Start a session.").foregroundStyle(.secondary).font(.custom("Inter", size: 13))
                }
                HStack {
                    TextField("A task, a project, a place to start…", text: $store.query).textFieldStyle(.plain).focused($focused).onSubmit { if let task = store.matches.first?.task { speech.stop(); store.start(task) } }
                    Button { if speech.listening { speech.stop() } else { Task { await speech.start { store.query = $0 } } } } label: { Image(systemName: speech.listening ? "stop.circle.fill" : "mic.fill").foregroundStyle(speech.listening ? Color.primary : accent) }.buttonStyle(.plain).help("Dictate on device")
                }.padding(16).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                ChatMatchView(chat: store.chat, store: store) { proposal in
                    speech.stop(); newTitle = proposal.title; projectID = proposal.projectID ?? ""; creating = true
                }
                if !speech.error.isEmpty { Text(speech.error).font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if store.query.isEmpty {
                            Text("READY WHEN YOU ARE").font(.custom("Inter", size: 10)).tracking(0.5).foregroundStyle(.secondary)
                            ForEach(Array(store.state.tasks.filter { !$0.done }.prefix(3))) { task in taskRow(task) }
                            if store.state.tasks.isEmpty { Text("Start with a local task, or connect your Notion workspace in Settings.").font(.custom("Inter", size: 13)).foregroundStyle(.secondary).padding(.vertical, 12) }
                        } else {
                            Text(store.matches.isEmpty ? "NO CLEAR MATCH" : "POSSIBLE MATCHES · SELECT TO START").font(.custom("Inter", size: 10)).tracking(1).foregroundStyle(.secondary)
                            ForEach(store.matches, id: \.task.id) { match in taskRow(match.task) }
                        }
                        Button {
                            speech.stop(); newTitle = store.query; projectID = ""; creating = true
                        } label: { Label("Create a new task", systemImage: "plus").foregroundStyle(accent).padding(.vertical, 12) }.buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            if !store.message.isEmpty { Text(store.message).font(.custom("Inter", size: 11)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
            HStack {
                Circle().fill(store.state.pending.isEmpty ? accent : Color.secondary).frame(width: 5, height: 5)
                Text(store.state.pending.isEmpty ? (store.state.settings.taskSource.isEmpty ? "LOCAL MODE" : "NOTION CONFIGURED") : "\(store.state.pending.count) UPDATES PENDING").font(.custom("Inter", size: 9)).tracking(1)
                Spacer()
                if !store.state.pending.isEmpty { Button("Retry") { Task { await store.flush() } }.buttonStyle(.plain).disabled(store.syncing) }
                Text("⇧⌘W").font(.custom("Inter", size: 11))
            }.foregroundStyle(.secondary)
        }
        .font(.custom("Inter", size: 13))
        .padding(26).frame(width: 440, height: 570)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.12)))

        .animation(.easeInOut(duration: 0.22), value: store.state.active == nil)
        .onAppear { focused = true }
        .onDisappear { speech.stop() }
        .onExitCommand { speech.stop(); hide() }
    }
    func taskRow(_ task: WorkTask) -> some View {
        Button { speech.stop(); store.start(task) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).foregroundStyle(.primary).lineLimit(2)
                    Text(task.project.isEmpty ? (task.remote ? "Notion" : "On this Mac") : task.project).font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!store.persistenceOK)
    }
}
struct PillStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.custom("Inter", size: 13)).fontWeight(.medium).padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(primary ? surface : Color.primary)
            .background(primary ? accent : Color.primary.opacity(0.09), in: Capsule()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct SettingsView: View {
    @ObservedObject var store: Store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.custom("Inter", size: 26)).fontWeight(.medium)
                ChatSettingsView(chat: store.chat)
                Divider()
                Text("Notion").font(.custom("Inter", size: 13)).fontWeight(.semibold)
                Text("Connect an internal Notion integration with access to your task and project databases. Tokens stay in macOS Keychain.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                SecureField("Notion integration token", text: $store.token)
                field("Tasks data source ID", text: $store.state.settings.taskSource)
                field("Projects data source ID (optional)", text: $store.state.settings.projectSource)
                HStack { field("Title field", text: $store.state.settings.titleProperty); field("Status field", text: $store.state.settings.statusProperty) }
                Picker("Status type", selection: $store.state.settings.statusType) { Text("Status").tag("status"); Text("Select").tag("select") }
                HStack { field("In-progress value", text: $store.state.settings.inProgress); field("Done value", text: $store.state.settings.done) }
                field("Project relation field", text: $store.state.settings.projectProperty)
                field("Start date field (optional)", text: $store.state.settings.startProperty)
                Text("The start date field records the latest session start. Full session history stays on this Mac.").font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                Button(store.busy ? "Connecting…" : "Connect / refresh tasks") { Task { await store.connect() } }.buttonStyle(PillStyle(primary: true)).disabled(store.busy || store.syncing || store.state.settings.taskSource.isEmpty)
                Divider()
                Toggle("Check in after 25 minutes", isOn: $store.state.checkIns).onChange(of: store.state.checkIns) { _, _ in store.save() }
                Picker("More time", selection: $store.state.extensionMinutes) { ForEach([5, 10, 15], id: \.self) { Text("\($0) minutes").tag($0) } }.onChange(of: store.state.extensionMinutes) { _, _ in store.save() }
                Text("Shortcut: ⇧⌘W · Drag the panel to place it anywhere. Sleep pauses tracking automatically.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                if !store.state.sessions.isEmpty {
                    Divider(); Text("Recent sessions").font(.custom("Inter", size: 13)).fontWeight(.semibold)
                    ForEach(Array(store.state.sessions.prefix(8))) { session in
                        HStack { Text(session.task.title).lineLimit(1); Spacer(); Text("\(Int(session.accumulated / 60))m"); Image(systemName: session.completed ? "checkmark.circle" : "pause.circle") }.font(.custom("Inter", size: 11))
                    }
                }
                Button("Quit W") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
            .disabled(store.busy || store.syncing)
        }
    }
    func field(_ label: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 4) { Text(label).font(.custom("Inter", size: 10)).foregroundStyle(.secondary); TextField(label, text: text) } }
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
                        Circle().fill(session.runningSince == nil ? Color.secondary : accent).frame(width: 6, height: 6)
                        Text(session.task.title).font(.custom("Inter", size: 13)).fontWeight(.medium).lineLimit(1)
                        Spacer()
                        Button { store.compact = false } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Expand timer")
                    }
                    HStack(spacing: 16) {
                        Text(store.timeText).font(.custom("Inter", size: 28)).fontWeight(.light).foregroundStyle(accent)
                        Spacer()
                        Button { session.runningSince == nil ? store.resume() : store.pause() } label: { Image(systemName: session.runningSince == nil ? "play.fill" : "pause.fill") }.help(session.runningSince == nil ? "Resume" : "Pause")
                        Button { store.extend() } label: { Text("+\(store.state.extensionMinutes)m").font(.custom("Inter", size: 11)) }.help("More time")
                        Button { store.stop(done: true) } label: { Image(systemName: "checkmark") }.help("Mark done")
                    }
                    if store.checkIn { Button("Time to check in →") { store.compact = false }.font(.custom("Inter", size: 11)).foregroundStyle(accent) }
                    else if !store.state.pending.isEmpty { Text("Notion sync pending · expand for details").font(.custom("Inter", size: 9)).foregroundStyle(.secondary) }
                }.buttonStyle(.plain).padding(20).frame(width: 360, height: 145)
                    .background(surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12)))

            } else { IslandView(store: store, dock: dock, hide: hide) }
        }.font(.custom("Inter", size: 13)).tint(.primary).onChange(of: isCompact) { _, compact in resize(compact) }
    }
}

struct ChatSettingsView: View {
    @ObservedObject var chat: ChatGPT
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ChatGPT").font(.custom("Inter", size: 13)).fontWeight(.semibold)
            Text("Use your ChatGPT plan for smarter task matching. Your request and up to 80 task and project names are sent to OpenAI only when you choose Find with ChatGPT.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
            if !chat.accounts.isEmpty {
                Picker("Account", selection: $chat.selected) { ForEach(chat.accounts) { Text($0.label).tag($0.id) } }
                    .disabled(chat.working).onChange(of: chat.selected) { _, _ in Task { await chat.selectAccount() } }
            }
            if chat.connected {
                if !chat.models.isEmpty { Picker("Model", selection: $chat.model) { ForEach(chat.models) { Text($0.name).tag($0.id) } }.disabled(chat.working) }
                Text("Using ChatGPT plan").font(.custom("Inter", size: 11))
                HStack {
                    Button("Sign out") { Task { await chat.signOut() } }
                    Button("Add account") { Task { await chat.signIn() } }
                }.disabled(chat.working)
            } else {
                Button("Continue with ChatGPT") { Task { await chat.signIn(existing: chat.active) } }.buttonStyle(PillStyle(primary: true)).disabled(chat.working)
                if chat.active != nil { Button("Use a different account") { Task { await chat.signIn() } }.disabled(chat.working) }
            }
            if chat.working { ProgressView().controlSize(.small); Button("Cancel sign-in") { chat.cancelLogin() } }
            Link("Manage usage ↗", destination: URL(string: "https://chatgpt.com/settings/usage")!).font(.custom("Inter", size: 11))
            if !chat.message.isEmpty { Text(chat.message).font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }
        }.alert("You're using your ChatGPT plan", isPresented: $chat.welcome) {
            Button("Got it") { UserDefaults.standard.set(true, forKey: "chatgptWelcomeSeen") }
        } message: { Text("Eligible AI requests in W use your ChatGPT plan. Manage W's access and limits in ChatGPT Settings → Usage.") }
    }
}
struct ChatMatchView: View {
    @ObservedObject var chat: ChatGPT
    @ObservedObject var store: Store
    @State var proposal: AIProposal?
    @State var error = ""
    let create: (AIProposal) -> Void
    var body: some View {
        if chat.connected && !store.query.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(chat.working ? "Finding…" : "Find with ChatGPT") {
                        let query = store.query
                        proposal = nil; error = ""
                        Task {
                            do {
                                let ranked = store.matches.map(\.task)
                                let rest = store.state.tasks.filter { task in !ranked.contains(where: { $0.id == task.id }) }
                                let result = try await chat.match(query: query, tasks: ranked + rest, projects: store.state.projects)
                                if store.query == query { proposal = result }
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(chat.working)
                    Spacer()
                    Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!).font(.custom("Inter", size: 10))
                }
                Text("Using ChatGPT plan").font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                if let proposal {
                    if let id = proposal.taskID, let task = store.state.tasks.first(where: { $0.id == id && !$0.done }) {
                        Button("Start: \(task.title)") { store.start(task) }.buttonStyle(PillStyle(primary: true))
                    } else { Button("Review new task: \(proposal.title)") { create(proposal) }.buttonStyle(.plain) }
                    Text(proposal.explanation).font(.custom("Inter", size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                if !error.isEmpty { Text(error).font(.custom("Inter", size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            }.onChange(of: store.query) { _, _ in proposal = nil; error = "" }
        }
    }
}
