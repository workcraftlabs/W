import SwiftUI
import AppKit
import WCore

struct TaskTitleView: View {
    let task: WorkTask
    let compact: Bool
    @State private var hovered = false
    @State private var openFailed = false

    var body: some View {
        Group {
            if task.notionWebURL != nil {
                Button(action: openTask) {
                    title.underline(hovered)
                }.buttonStyle(.plain)
                    .onHover { hovered = $0 }
                    .help("Open task in Notion")
                    .accessibilityLabel("Open \(task.title) in Notion")
            } else { title }
        }
        .lineLimit(compact ? 1 : 3)
        .fixedSize(horizontal: false, vertical: !compact)
        .alert("Couldn’t open this task", isPresented: $openFailed) {
            Button("OK", role: .cancel) { }
        } message: { Text("Try opening Notion directly.") }
    }
    private var title: Text {
        Text(task.title).font(.custom("Inter", size: compact ? 13 : 27)).fontWeight(.medium)
    }
    private func openTask() {
        guard let web = task.notionWebURL else { return }
        let workspace = NSWorkspace.shared
        guard let native = task.notionAppURL, let app = workspace.urlForApplication(toOpen: native) else {
            openFailed = !workspace.open(web)
            return
        }
        workspace.open([native], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                Task { @MainActor in openFailed = !NSWorkspace.shared.open(web) }
            }
        }
    }
}
