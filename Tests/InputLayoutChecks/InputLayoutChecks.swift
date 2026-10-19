import AppKit

// Compile alongside Sources/W/TaskInputField.swift; no window or task data needed.
@main struct InputLayoutChecks {
    @MainActor static func main() {
        let field = TaskInputField.InputView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        field.font = .systemFont(ofSize: 13)
        field.textContainerInset = NSSize(width: 0, height: 2)
        field.string = "One pager for Boardwalk All in a Days Work - Internal"
        field.setSelectedRange(NSRange(location: 8, length: 0))
        let originalFrame = field.frame
        let originalContainer = field.textContainer!.containerSize
        let originalSelection = field.selectedRange()
        for width: CGFloat in [1, 320, 10, 280, 1, 320] {
            let height = field.measuredHeight(for: width)
            precondition(height >= 22 && height <= 112)
            precondition(field.frame == originalFrame, "Measurement resized the live editor")
            precondition(field.textContainer!.containerSize == originalContainer, "Measurement changed the live text container")
            precondition(field.selectedRange() == originalSelection, "Measurement moved the caret")
        }
        field.string = "First line\nSecond line\nThird line"
        precondition(field.measuredHeight(for: 320) > 22, "Multiline input must grow")
        field.string = String(repeating: "A long line of dictation\n", count: 30)
        precondition(field.measuredHeight(for: 320) == 112, "Long input must cap its height and scroll")
        field.string = ""
        precondition(field.measuredHeight(for: 320) == 22, "Empty input returns to minimum height")
        print("PASS: width probes preserve editor geometry and caret; multiline grows; long text caps; empty input shrinks")
    }
}
