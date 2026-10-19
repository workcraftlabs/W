import AppKit
import QuartzCore

/// A disposable visual surface. The real editor stays at its final size throughout.
@MainActor final class DropletTransition {
    private var overlay: NSPanel?

    func present(destination: NSRect, appearance: NSAppearance?) {
        dismiss()
        let bounds = destination.insetBy(dx: -8, dy: -8)
        let window = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.appearance = appearance
        let view = NSView(frame: NSRect(origin: .zero, size: bounds.size))
        view.wantsLayer = true
        window.contentView = view
        let shape = CAShapeLayer()
        view.layer?.addSublayer(shape)
        let end = NSRect(x: 8, y: 8, width: destination.width, height: destination.height)
        let center = end.midX
        let top = end.maxY + 8
        func path(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        // A bead stretches just below the menu bar, then softly opens into the panel.
        let bead = path(CGRect(x: center - 12, y: top - 10, width: 24, height: 10), 5)
        let drop = path(CGRect(x: center - 10, y: top - 36, width: 20, height: 32), 10)
        let bloom = path(CGRect(x: center - end.width * 0.31, y: end.midY, width: end.width * 0.62, height: end.height * 0.5), 28)
        let final = path(end, 18)
        let resolved = appearance ?? NSApp.effectiveAppearance
        resolved.performAsCurrentDrawingAppearance {
            shape.fillColor = NSColor.windowBackgroundColor.cgColor
            shape.strokeColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }
        shape.lineWidth = 1
        shape.path = final
        let morph = CAKeyframeAnimation(keyPath: "path")
        morph.values = [bead, drop, bloom, final]
        morph.keyTimes = [0, 0.2, 0.62, 1]
        morph.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1), CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)]
        morph.duration = 0.32
        shape.add(morph, forKey: "droplet")
        overlay = window
        window.orderFrontRegardless()
    }

    func dismiss() {
        overlay?.orderOut(nil)
        overlay = nil
    }
}
