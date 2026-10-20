import SwiftUI
import WCore

private let accent = Color.primary
private let surface = Color(nsColor: .windowBackgroundColor)
struct IslandView: View {
    @ObservedObject var store: Store
    @StateObject var speech = SpeechInput()
    @State private var searchRequest: SearchRequest?
    @State private var searching = false
    @State private var creating = false
    @State private var newTitle = ""
    @State private var projectID = ""
    @State private var focused = false
    let dock: () -> Void
    let hide: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("W").font(.custom("Inter", size: 19)).fontWeight(.heavy).foregroundStyle(accent)
                Spacer()
                Text(store.navigation == .tasks ? (store.state.active == nil ? "FOCUS" : "SESSION") : store.navigation.title.uppercased()).font(.custom("Inter", size: 9)).fontWeight(.semibold).tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                Button { speech.stop(); hide() } label: { Image(systemName: "minus") }.help("Hide · ⌃⌥W to reopen")
            }.buttonStyle(.plain)
            if store.showSettings { SettingsView(store: store) }
            else if store.navigation == .history { CompletionHistoryView(store: store) }
            else if store.navigation == .notes { CaptureEditorView(store: store, kind: .notes) }
            else if store.navigation == .journal { CaptureEditorView(store: store, kind: .journal) }
            else if let session = store.state.active {
                ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 7) {
                        Circle().fill(session.runningSince == nil ? Color.secondary : accent).frame(width: 6, height: 6)
                        Text(session.runningSince == nil ? "PAUSED" : "IN PROGRESS").font(.custom("Inter", size: 10)).fontWeight(.medium).tracking(0.5)
                        Spacer()
                        Button { store.compact = true } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }.buttonStyle(.plain).help("Compact timer")
                        Button(action: dock) { Image(systemName: "rectangle.topthird.inset.filled") }.buttonStyle(.plain).help("Dock at top of current screen")
                    }.foregroundStyle(.secondary)
                    TaskTitleView(task: session.task, compact: false)
                    SessionTimerContents(store: store, compact: false)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if creating {
                NewTaskForm(store: store, title: $newTitle, projectID: $projectID) { creating = false }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are you working on?").font(.custom("Inter", size: 25)).fontWeight(.medium).tracking(-1)
                    Text("Find a task. Start a session.").foregroundStyle(.secondary).font(.custom("Inter", size: 13))
                }
                HStack {
                    TaskInputField(text: $store.query, focused: $focused, submit: submitSearch)
                        .transaction { $0.animation = nil }
                    DictationButton(active: speech.listening || speech.starting) {
                        if speech.listening || speech.starting { speech.stop() }
                        else { Task { await speech.start { store.query = $0 } } }
                    }.frame(width: 24, height: 24)
                }.padding(16).background {
                    RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture { focused = true }
                }
                SearchChoicesView(chat: store.chat, store: store, request: searchRequest, editing: focused, searching: $searching, search: submitSearch) { proposal in
                    speech.stop(); newTitle = proposal.title; projectID = proposal.projectID ?? ""; creating = true
                }
                if !speech.error.isEmpty { Text(speech.error).font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }

            }
            if store.state.active == nil && store.navigation == .tasks { Spacer(minLength: 0) }
            if !store.message.isEmpty && store.navigation == .tasks { Text(store.message).font(.custom("Inter", size: 11)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
            HStack {
                Circle().fill(store.state.pending.isEmpty ? accent : Color.secondary).frame(width: 5, height: 5)
                Text(store.state.pending.isEmpty ? (store.state.settings.taskSource.isEmpty ? "LOCAL MODE" : store.notionStatusLabel) : "\(store.state.pending.count) UPDATES PENDING").font(.custom("Inter", size: 9)).tracking(1)
                Spacer()
                if !store.state.pending.isEmpty { Button("Retry") { Task { await store.flush() } }.buttonStyle(.plain).disabled(store.syncing) }
                Text("⌃⌥W").font(.custom("Inter", size: 11))
            }.foregroundStyle(.secondary)
        }
        .font(.custom("Inter", size: 13))
        .padding(26).frame(width: 440, height: 570)

        .animation(.easeInOut(duration: 0.22), value: store.state.active == nil)
        .onAppear { focused = true }
        .onChange(of: store.query) { _, _ in searchRequest = nil }
        .onChange(of: store.navigation) { _, route in
            speech.stop(); searchRequest = nil; focused = route == .tasks
        }
        .onDisappear { speech.stop() }
        .onExitCommand { speech.stop(); hide() }
    }
    func submitSearch() {
        guard !searching, !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        speech.stop()
        focused = false
        searchRequest = SearchRequest(query: store.query)
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
                Toggle("Show in menu bar", isOn: $store.showInMenuBar)
                Toggle("Show in Dock", isOn: $store.showInDock)
                Text("Open W anytime with Control–Option–W, even with both icons hidden.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                Divider()
                ChatSettingsView(chat: store.chat)
                Divider()
                HStack {
                    Text("Notion").font(.custom("Inter", size: 13)).fontWeight(.semibold)
                    Spacer()
                    NotionConnectionIndicator(store: store)
                }
                Text("Connect an internal Notion integration with access to your task and project databases. Tokens stay in macOS Keychain.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                SecureField("Notion integration token", text: $store.token)
                HStack {
                    field("Tasks data source ID", text: $store.state.settings.taskSource)
                    NotionConnectionIndicator(store: store)
                }
                HStack {
                    field("Projects data source ID (optional)", text: $store.state.settings.projectSource)
                    if !store.state.settings.projectSource.isEmpty { NotionConnectionIndicator(store: store) }
                }
                if let schema = store.notionSchema {
                    Picker("Title field", selection: $store.state.settings.titleProperty) {
                        ForEach(schema.titles, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Status field", selection: $store.state.settings.statusProperty) {
                        ForEach(schema.statusFields.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    }.onChange(of: store.state.settings.statusProperty) { _, name in
                        store.state.settings.statusType = schema.statusTypes[name] ?? "status"
                    }
                    statusPicker("In progress", selection: $store.state.settings.inProgress, options: schema.statusFields[store.state.settings.statusProperty] ?? [])
                    statusPicker("Done", selection: $store.state.settings.done, options: schema.statusFields[store.state.settings.statusProperty] ?? [])
                    Picker("Project relation", selection: $store.state.settings.projectProperty) {
                        ForEach(Array(Set(schema.relations + [store.state.settings.projectProperty])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Session Due / Date field", selection: Binding(get: { store.state.settings.sessionDateProperty ?? "" }, set: { store.state.settings.sessionDateProperty = $0 })) {
                        Text("None").tag("")
                        ForEach(schema.dates, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Start date field", selection: $store.state.settings.startProperty) {
                        Text("None").tag("")
                        ForEach(schema.dates, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    Text("Connect to auto-detect fields and choose from your database’s status options.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                    DisclosureGroup("Manual field mapping") {
                        field("Title field", text: $store.state.settings.titleProperty)
                        field("Status field", text: $store.state.settings.statusProperty)
                        Picker("Status type", selection: $store.state.settings.statusType) { Text("Status").tag("status"); Text("Select").tag("select") }
                        field("In-progress value", text: $store.state.settings.inProgress)
                        field("Done value", text: $store.state.settings.done)
                        field("Project relation field", text: $store.state.settings.projectProperty)
                        field("Session Due / Date field", text: Binding(get: { store.state.settings.sessionDateProperty ?? "" }, set: { store.state.settings.sessionDateProperty = $0 }))
                        field("Start date field (optional)", text: $store.state.settings.startProperty)
                    }
                }
                Text("Session dates start at the previous 5-minute mark. Stop resets the chosen field to today without a time.").font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                Text("The start date field records the latest session start. Full session history stays on this Mac.").font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                Button(store.busy ? "Connecting…" : "Verify connection & refresh") { Task { await store.connect() } }.buttonStyle(PillStyle(primary: true)).disabled(store.busy || store.syncing || store.state.settings.taskSource.isEmpty)
                if !store.notionConnectionMessage.isEmpty {
                    Text(store.notionConnectionMessage).font(.custom("Inter", size: 11))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let verification = store.state.notionVerification {
                    Text("Last verified: \(verification.verifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                }
                Text("Connection settings are saved on this Mac. W checks access automatically when it opens.")
                    .font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                Divider()
                Text("Capture locations").font(.custom("Inter", size: 13)).fontWeight(.semibold)
                Text("Share each database with the same Notion integration. Notes and Journal can use separate locations.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                CaptureLocationSettings(store: store, kind: .notes)
                CaptureLocationSettings(store: store, kind: .journal)
                Divider()
                CreationPreferences(store: store)
                Divider()
                TaskPropertySettings(store: store)
                Divider()
                Toggle("Notify when the interval ends", isOn: $store.state.checkIns).onChange(of: store.state.checkIns) { _, _ in store.save() }
                Picker("Default interval", selection: Binding(get: { store.defaultInterval }, set: { store.state.focusMinutes = $0; store.save() })) {
                    ForEach(SessionTiming.intervals, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Text("The timer pauses at each interval. Keep going adds another interval; Stop keeps the task In Progress.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                Text("Shortcut: ⌃⌥W · Drag the panel to place it anywhere. Sleep pauses tracking automatically.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                if !store.state.sessions.isEmpty {
                    Divider(); Text("Recent sessions").font(.custom("Inter", size: 13)).fontWeight(.semibold)
                    ForEach(Array(store.state.sessions.prefix(8))) { session in
                        HStack { Text(session.task.title).lineLimit(1); Spacer(); Text("\(Int(session.accumulated / 60))m"); Image(systemName: session.completed ? "checkmark.circle" : "pause.circle") }.font(.custom("Inter", size: 11))
                    }
                }
                Button("Quit W") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
            .onChange(of: store.state.settings) { _, _ in store.notionSettingsChanged() }
            .disabled(store.busy || store.syncing)
        }
    }
    func statusPicker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        Picker(label, selection: selection) {
            if !options.contains(selection.wrappedValue) { Text("Choose a status…").tag(selection.wrappedValue) }
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }
    func field(_ label: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 4) { Text(label).font(.custom("Inter", size: 10)).foregroundStyle(.secondary); TextField(label, text: text) } }
}

struct PanelRoot: View {
    @ObservedObject var store: Store
    let dock: () -> Void
    let hide: () -> Void
    let resize: (Bool) -> Void
    var isCompact: Bool { store.compact && store.state.active != nil && store.navigation == .tasks }
    var body: some View {
        Group {
            if isCompact, let session = store.state.active {
                VStack(spacing: 8) {
                    HStack {
                        Circle().fill(session.runningSince == nil ? Color.secondary : accent).frame(width: 6, height: 6)
                        TaskTitleView(task: session.task, compact: true)
                        Spacer()
                        Button { store.compact = false } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Expand timer")
                    }
                    SessionTimerContents(store: store, compact: true)
                    if !store.state.pending.isEmpty && !store.checkIn { Text("Notion sync pending").font(.custom("Inter", size: 9)).foregroundStyle(.secondary) }
                }.buttonStyle(.plain).padding(20).frame(width: 360, height: 220)
                    .background(surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12)))

            } else {
                HStack(spacing: 0) {
                    WSidebar(store: store)
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1).padding(.vertical, 16)
                    IslandView(store: store, dock: dock, hide: hide)
                }.frame(width: 489, height: 570)
                    .background(surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.12)))
            }
        }.font(.custom("Inter", size: 13)).tint(.primary).onChange(of: isCompact) { _, compact in resize(compact) }
    }
}

struct ChatSettingsView: View {
    @ObservedObject var chat: ChatGPT
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ChatGPT").font(.custom("Inter", size: 13)).fontWeight(.semibold)
            Text("Use your ChatGPT plan for smarter task matching. Your request and up to 80 task and project names are sent to OpenAI when you press Enter or Search. If ChatGPT is unavailable, W uses basic matching.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
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
