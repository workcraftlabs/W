import SwiftUI
import WCore

extension Store {
    func destination(_ kind: CaptureKind) -> CaptureDestination { state.captureDestinations?[kind.rawValue] ?? CaptureDestination() }
    func draft(_ kind: CaptureKind) -> CaptureDraft { state.captureDrafts?[kind.rawValue] ?? CaptureDraft() }
    func destinationReady(_ kind: CaptureKind) -> Bool {
        let location = destination(kind)
        return location.configured && location.tokenFingerprint == tokenFingerprint && !token.isEmpty
    }
    func setDraft(_ kind: CaptureKind, _ value: CaptureDraft) {
        if state.captureDrafts == nil { state.captureDrafts = [:] }
        state.captureDrafts?[kind.rawValue] = value; save()
    }
    func setDestination(_ kind: CaptureKind, _ value: CaptureDestination) {
        if state.captureDestinations == nil { state.captureDestinations = [:] }
        state.captureDestinations?[kind.rawValue] = value; save()
    }
    func verifyCapture(_ kind: CaptureKind) async {
        guard captureBusy == nil else { return }
        captureBusy = kind; defer { captureBusy = nil }
        let input = destination(kind)
        let fingerprint = tokenFingerprint
        do {
            let credential = token.trimmingCharacters(in: .whitespacesAndNewlines)
            var verified = try await NotionClient(token: credential).captureDestination(location: input.location)
            guard destination(kind).location == input.location, tokenFingerprint == fingerprint else { return }
            if (input.configured && input.dateProperty.isEmpty) || verified.dateFields.contains(input.dateProperty) { verified.dateProperty = input.dateProperty }
            try Keychain.write(credential)
            verified.tokenFingerprint = fingerprint
            setDestination(kind, verified)
            captureMessages[kind] = "Location verified."
        } catch {
            if destination(kind).location == input.location {
                var failed = destination(kind); failed.verifiedAt = nil; setDestination(kind, failed)
            }
            captureMessages[kind] = error.localizedDescription
        }
    }
    func saveCapture(_ kind: CaptureKind) async {
        guard captureBusy == nil, persistenceOK, destinationReady(kind) else { return }
        captureBusy = kind; defer { captureBusy = nil }
        let submitted = draft(kind)
        do {
            let record = try await NotionClient(token: token).createCapture(draft: submitted, kind: kind, destination: destination(kind))
            if state.captureRecords == nil { state.captureRecords = [] }
            state.captureRecords?.insert(record, at: 0)
            if draft(kind) == submitted { setDraft(kind, CaptureDraft()) }
            save()
            captureMessages[kind] = "Saved to Notion."
        } catch {
            captureMessages[kind] = "\(error.localizedDescription) Draft kept. If saving timed out, check Notion before retrying to avoid a duplicate."
        }
    }
}

struct CaptureEditorView: View {
    @ObservedObject var store: Store
    let kind: CaptureKind
    private func text(_ path: WritableKeyPath<CaptureDraft, String>) -> Binding<String> {
        Binding(get: { store.draft(kind)[keyPath: path] }, set: { text in
            var draft = store.draft(kind); draft[keyPath: path] = text; store.setDraft(kind, draft)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.title).font(.custom("Inter", size: 26)).fontWeight(.medium)
            Text(kind == .journal ? Date().formatted(date: .complete, time: .omitted) : "A place for a thought, an idea, or a detail.")
                .font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
            if !store.destinationReady(kind) {
                HStack {
                    Text("Choose a \(kind.title.lowercased()) database in Settings.").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Set location") { store.navigation = .settings }.buttonStyle(.plain)
                }
            }
            TextField(kind == .journal ? "Title (defaults to today)" : "Title (optional)", text: text(\.title)).textFieldStyle(.plain)
                .font(.custom("Inter", size: 16)).padding(.vertical, 6)
            ZStack(alignment: .topLeading) {
                if store.draft(kind).body.isEmpty {
                    Text(kind == .journal ? "What’s on your mind?" : "Write a note…")
                        .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false)
                }
                TextEditor(text: text(\.body)).scrollContentBackground(.hidden).font(.custom("Inter", size: 13))
                    .accessibilityLabel(kind == .journal ? "Journal entry" : "Note body")
            }.padding(8).frame(minHeight: 120, maxHeight: .infinity)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("Draft saved on this Mac").font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(store.captureBusy == kind ? "Saving…" : "Save to Notion") { Task { await store.saveCapture(kind) } }
                    .buttonStyle(PillStyle(primary: true))
                    .disabled(store.captureBusy != nil || !store.destinationReady(kind) || store.draft(kind).body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.persistenceOK)
            }
            if let message = store.captureMessages[kind] {
                Text(message).font(.custom("Inter", size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            let recent = Array((store.state.captureRecords ?? []).filter { $0.kind == kind }.prefix(3))
            if !recent.isEmpty {
                Divider()
                Text("RECENTLY SAVED").font(.custom("Inter", size: 9)).foregroundStyle(.secondary)
                ForEach(recent) { record in
                    TaskTitleView(task: WorkTask(id: record.id, title: record.title, remote: true), compact: true)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .disabled(store.captureBusy == kind)
    }
}

struct CaptureLocationSettings: View {
    @ObservedObject var store: Store
    let kind: CaptureKind
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(kind.title) database").font(.custom("Inter", size: 12)).fontWeight(.medium)
            TextField("Database link or data source ID", text: Binding(get: { store.destination(kind).location }, set: { location in
                var value = CaptureDestination(); value.location = location
                store.setDestination(kind, value); store.captureMessages[kind] = nil
            })).accessibilityLabel("\(kind.title) database location")
            HStack {
                Button(store.captureBusy == kind ? "Checking…" : "Verify location") { Task { await store.verifyCapture(kind) } }
                    .disabled(store.captureBusy != nil || store.destination(kind).location.isEmpty || store.token.isEmpty)
                if store.destinationReady(kind) { Label("Verified", systemImage: "checkmark.circle").font(.custom("Inter", size: 11)).foregroundStyle(.secondary) }
            }
            if store.destinationReady(kind) {
                Picker("Date field", selection: Binding(get: { store.destination(kind).dateProperty }, set: { name in
                    var value = store.destination(kind); value.dateProperty = name; store.setDestination(kind, value)
                })) {
                    Text("None").tag("")
                    ForEach(store.destination(kind).dateFields, id: \.self) { Text($0).tag($0) }
                }
                Text("Title: \(store.destination(kind).titleProperty) · Body saved as page content. Selected date defaults to today.")
                    .font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
            }
            if let message = store.captureMessages[kind] { Text(message).font(.custom("Inter", size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.disabled(store.captureBusy != nil)
    }
}
