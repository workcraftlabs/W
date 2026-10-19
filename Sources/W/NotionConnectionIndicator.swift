import SwiftUI

struct NotionConnectionIndicator: View {
    @ObservedObject var store: Store
    var body: some View {
        Group {
            if store.notionConnection == .checking {
                ProgressView().controlSize(.small).accessibilityLabel("Checking Notion connection")
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(store.notionConnected ? Color.primary : Color.secondary)
                    .accessibilityLabel(label)
                    .help(label)
            }
        }.frame(width: 20, height: 20)
    }
    private var symbol: String {
        if store.notionConnected { return "checkmark.circle.fill" }
        return store.notionConnection == .failed ? "xmark.circle" : "minus.circle"
    }
    private var label: String {
        if store.notionConnected { return "Notion connected" }
        return store.notionConnection == .failed ? "Connection failed. See details below." : "Not verified. Click Verify connection & refresh."
    }
}
