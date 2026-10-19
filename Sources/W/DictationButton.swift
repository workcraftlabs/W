import SwiftUI
import AppKit

// Use AppKit target/action to avoid the SwiftUI _ButtonGesture actor check
// seen in the macOS 26 crash reports when activating dictation.
struct DictationButton: NSViewRepresentable {
    var active: Bool
    var action: @MainActor () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        let label = active ? "Stop dictation" : "Dictate on device"
        button.image = NSImage(systemSymbolName: active ? "stop.circle.fill" : "mic.fill", accessibilityDescription: label)
        button.contentTintColor = .labelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }
    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func performAction() { action() }
    }
}
