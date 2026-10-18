import SwiftUI
import WCore
import Security
import UserNotifications

@MainActor final class Store: ObservableObject {
    @Published var state = SavedState()
    @Published var query = ""
    @Published var message = ""
    @Published var busy = false
    @Published var syncing = false
    @Published var showSettings = false
    @Published var now = Date()
    @Published var checkIn = false
    @Published var compact = false
    @Published var token = ""
    var file: URL
    var timer: Timer?
    var persistenceOK = true
    var verifiedSettings: NotionSettings?
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("W")
        file = directory.appendingPathComponent("state.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file)) }
        } catch { persistenceOK = false; message = "Cannot load saved sessions. Your file was preserved: \(error.localizedDescription)" }
        token = Keychain.read() ?? ""
        verifiedSettings = state.validatedSettings
        if state.active != nil {
            // Recovery never counts unattended time after the last durable heartbeat.
            state.active?.runningSince = nil
            message = "Recovered your session, paused. Resume when ready."
            save()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    var matches: [(task: WorkTask, score: Double)] { Matcher.ranked(query, tasks: state.tasks) }
    var elapsed: TimeInterval { state.active?.elapsed(at: now) ?? 0 }
    var timeText: String { let seconds = Int(elapsed); return String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    func save() {
        guard persistenceOK else { return }
        do { try JSONEncoder().encode(state).write(to: file, options: .atomic) }
        catch { message = "Could not save session: \(error.localizedDescription)" }
    }
    func tick() {
        now = Date()
        if state.active?.runningSince != nil {
            state.active?.accumulated = elapsed
            state.active?.runningSince = now
            if state.checkIns, let target = state.active?.checkInAt, elapsed >= target {
                state.active?.checkInAt = nil; checkIn = true
                let content = UNMutableNotificationContent()
                content.title = "Time for a check-in"
                content.body = "Done, taking a break, or need more time? Your timer is still running."
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
            save()
        }
    }
    func start(_ task: WorkTask) {
        guard state.active == nil, persistenceOK else { return }
        if task.remote && verifiedSettings != state.settings { message = "Refresh and validate Settings before starting a Notion task."; return }
        let session = WorkSession(task: task)
        state.active = session; query = ""; now = Date(); checkIn = false; compact = true
        if task.remote { state.pending.append(PendingUpdate(pageID: task.id, status: state.settings.inProgress, start: session.startedAt, settings: state.settings)) }
        save()
        if state.checkIns { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        Task { await flush() }
    }
    func pause() { state.active?.pause(); save() }
    func resume() { state.active?.resume(); save() }
    func stop(done: Bool) {
        guard var session = state.active else { return }
        session.stop(done: done); state.sessions.insert(session, at: 0); state.active = nil; checkIn = false; compact = false
        if done {
            if let index = state.tasks.firstIndex(where: { $0.id == session.task.id }) { state.tasks[index].done = true }
            if session.task.remote { state.pending.append(PendingUpdate(pageID: session.task.id, status: state.settings.done, settings: state.settings)) }
        }
        save(); Task { await flush() }
    }
    func extend() { state.active?.extend(minutes: state.extensionMinutes); checkIn = false; save() }
    func keepGoing() { checkIn = false; state.active?.checkInAt = nil; save() }
    func connect() async {
        guard !busy, !syncing else { return }
        if let previous = state.validatedSettings, previous != state.settings, (state.active != nil || !state.pending.isEmpty) { message = "Stop the active session and sync pending updates before changing the connection."; return }
        busy = true; defer { busy = false }
        do {
            try Keychain.write(token)
            let result = try await NotionClient(token: token).fetch(state.settings)
            state.tasks = state.tasks.filter { !$0.remote } + result.0; state.projects = result.1
            verifiedSettings = state.settings; state.validatedSettings = state.settings
            save(); message = "Connected. \(result.0.count) tasks indexed."
            await flush()
        } catch { verifiedSettings = nil; message = error.localizedDescription }
    }
    func create(title: String, projectID: String) async {
        guard !busy, state.active == nil, persistenceOK else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 500 else { message = "Use a task title between 1 and 500 characters."; return }
        busy = true; defer { busy = false }
        let project = state.projects.first { $0.id == projectID }
        do {
            let task: WorkTask
            if state.settings.taskSource.isEmpty {
                task = WorkTask(title: name)
            } else {
                guard verifiedSettings == state.settings else { throw NotionError("Refresh and validate your Notion connection before creating a task.") }
                task = try await NotionClient(token: token).create(title: name, project: project, settings: state.settings)
            }
            state.tasks.insert(task, at: 0); save(); start(task)
        } catch {
            // Never retry a create automatically: a timed-out POST may have succeeded.
            message = "\(error.localizedDescription) If creation was attempted, refresh Notion before retrying to avoid duplicates."
            verifiedSettings = nil
        }
    }
    func flush() async {
        guard !syncing, !state.pending.isEmpty else { return }
        syncing = true; defer { syncing = false }
        while let update = state.pending.first {
            do {
                try await NotionClient(token: token).apply(update)
                state.pending.removeAll { $0.id == update.id }; save()
            } catch { message = "Saved locally; Notion sync pending. \(error.localizedDescription)"; return }
        }
        message = "Synced with Notion."
    }
}

enum Keychain {
    static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.workcraftlabs.W", kSecAttrAccount as String: "notion"]
    static func read() -> String? {
        var query = base; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base; query[kSecValueData as String] = data
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw NotionError("Keychain could not save your token (\(added)).") }
        } else if status != errSecSuccess { throw NotionError("Keychain could not save your token (\(status)).") }
    }
}
