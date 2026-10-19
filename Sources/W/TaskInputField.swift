import AppKit
import SwiftUI

// Wrap and grow with the text, then scroll instead of clipping long dictation.
struct TaskInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let field = InputView(frame: NSRect(x: 0, y: 0, width: 320, height: 22), textContainer: container)
        field.isEditable = true
        field.isSelectable = true
        field.isRichText = false
        field.allowsUndo = true
        field.drawsBackground = false
        field.font = NSFont(name: "Inter", size: 13) ?? .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.insertionPointColor = .labelColor
        field.textContainerInset = NSSize(width: 0, height: 2)
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.autoresizingMask = [.width]
        field.minSize = NSSize(width: 0, height: 22)
        field.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        field.setAccessibilityLabel("Task description")
        field.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = field
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let field = scroll.documentView as? InputView else { return }
        context.coordinator.parent = self
        if field.string != text {
            let selection = field.selectedRange()
            field.string = text
            field.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            field.needsDisplay = true
        }
        if context.coordinator.requestedFocus != focused {
            context.coordinator.requestedFocus = focused
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, let coordinator, let window = field.window else { return }
                if coordinator.parent.focused {
                    window.makeKey()
                    window.makeFirstResponder(field)
                } else if window.firstResponder === field {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let field = scroll.documentView as? InputView else { return nil }
        let proposedWidth = proposal.width ?? 320
        let width = proposedWidth.isFinite ? max(1, proposedWidth) : 320
        return CGSize(width: width, height: field.measuredHeight(for: width))
    }
    final class InputView: NSTextView {
        func measuredHeight(for width: CGFloat) -> CGFloat {
            // SwiftUI probes several widths, including zero, before placing the view.
            // Measuring must never resize the live editor or change its scroll offset.
            let storage = NSTextStorage(attributedString: attributedString())
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            let used = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentUsedRect.maxY)
            return min(112, max(22, ceil(used + textContainerInset.height * 2)))
        }

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            super.mouseDown(with: event)
        }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty {
                ("A task, a project, a place to start…" as NSString).draw(
                    at: NSPoint(x: 0, y: textContainerInset.height),
                    withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor])
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaskInputField
        var requestedFocus: Bool?
        init(_ parent: TaskInputField) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let field = notification.object as? InputView else { return }
            parent.text = field.string
            field.needsDisplay = true
        }
        func textDidBeginEditing(_ notification: Notification) { parent.focused = true; requestedFocus = true }
        func textDidEndEditing(_ notification: Notification) { parent.focused = false; requestedFocus = false }
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                guard !textView.hasMarkedText(), NSApp.currentEvent?.modifierFlags.contains(.shift) != true else { return false }
                parent.submit()
                return true
            }
            return false
        }
    }
}
