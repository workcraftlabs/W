import AppKit
import SwiftUI

// A native field takes first-responder ownership even inside the floating,
// nonactivating panel. Background window dragging must not consume its clicks.
struct TaskInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> InputField {
        let field = InputField()
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont(name: "Inter", size: 13) ?? .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.placeholderString = "A task, a project, a place to start…"
        field.setAccessibilityLabel("Task description")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: InputField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        // Only transfer focus on a requested change, never on every timer tick.
        if context.coordinator.requestedFocus != focused {
            context.coordinator.requestedFocus = focused
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, let coordinator, let window = field.window else { return }
                if coordinator.parent.focused {
                    window.makeKey()
                    window.makeFirstResponder(field)
                } else if field.currentEditor() != nil {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }
    final class InputField: NSTextField {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            super.mouseDown(with: event)
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TaskInputField
        var requestedFocus: Bool?
        init(_ parent: TaskInputField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true; requestedFocus = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false; requestedFocus = false }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                guard !textView.hasMarkedText() else { return false }
                parent.submit()
                return true
            }
            return false
        }
    }
}
