import SwiftUI
import AppKit
import Carbon
import CoreText
import Combine
import QuartzCore
import UserNotifications

@main struct WApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
final class IslandPanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = Store()
    var panel: IslandPanel!
    var statusItem: NSStatusItem!
    var hotKeys: [EventHotKeyRef] = []
    private let droplet = DropletTransition()
    var handler: EventHandlerRef?
    private var transitioning = false
    private var visibilitySubscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let fontBundle = Bundle.main.url(forResource: "W_W", withExtension: "bundle").flatMap { Bundle(url: $0) } ?? Bundle.module
        if let font = fontBundle.url(forResource: "Inter", withExtension: "ttf") { CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil) }
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 489, height: 570), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelRoot(store: store, dock: { [weak self] in self?.dock() }, hide: { [weak self] in self?.hide() }, resize: { [weak self] compact in self?.resize(compact) }))
        visibilitySubscription = store.$showInMenuBar.combineLatest(store.$showInDock)
            .sink { [weak self] menuBar, dock in self?.updateVisibility(menuBar: menuBar, dock: dock) }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return noErr }
            let id = identifier.id
            Task { @MainActor in delegate.openShortcut(id) }; return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for (index, key) in [kVK_ANSI_W, kVK_ANSI_N, kVK_ANSI_J].enumerated() {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x57415050, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotKeys.append(reference) }
            else { store.message = "A W shortcut is unavailable. Open W from the menu bar." }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        UNUserNotificationCenter.current().delegate = self
        show()
        Task { await store.restoreNotionConnection() }
    }
    private func updateVisibility(menuBar: Bool, dock: Bool) {
        if menuBar && statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "W"
            statusItem.button?.target = self
            statusItem.button?.action = #selector(toggle)
        } else if !menuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }
    func show() {
        guard !transitioning else { return }
        if panel.isVisible { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let destination = anchoredFrame(size: panel.frame.size)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(destination, display: false)
        panel.alphaValue = 0
        transitioning = true
        if !reducedMotion { droplet.present(destination: destination, appearance: panel.effectiveAppearance) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !reducedMotion { try? await Task.sleep(for: .milliseconds(320)) }
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reducedMotion ? 0.15 : 0.08
                self.panel.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.droplet.dismiss()
                    self.transitioning = false
                    self.panel.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    func hide() {
        guard panel.isVisible, !transitioning else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { panel.orderOut(nil); return }
        transitioning = true
        let destination = panel.frame.offsetBy(dx: 0, dy: 40)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(destination, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
                self?.transitioning = false
            }
        }
    }
    func openShortcut(_ id: UInt32) {
        guard !transitioning else { return }
        let route: WNavigation = id == 2 ? .notes : (id == 3 ? .journal : .tasks)
        if panel.isVisible && store.navigation == route && !store.compact { hide(); return }
        store.compact = false
        store.navigation = route
        resize(false)
        show()
    }
    @objc func toggle() { panel.isVisible ? hide() : show() }
    private func anchoredFrame(size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return NSRect(origin: panel.frame.origin, size: size) }
        let visible = screen.visibleFrame
        let anchorX = screen.frame.midX
        let x = min(max(anchorX - size.width / 2, visible.minX + 12), visible.maxX - size.width - 12)
        return NSRect(x: x, y: visible.maxY - size.height - 10, width: size.width, height: size.height)
    }
    func resize(_ compact: Bool) {
        let old = panel.frame
        let size = compact ? NSSize(width: 360, height: 220) : NSSize(width: 489, height: 570)
        panel.setFrame(NSRect(x: old.midX - size.width / 2, y: old.maxY - size.height, width: size.width, height: size.height), display: true, animate: panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func dock() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 10))
    }
    @objc func sleep() { if store.state.active?.runningSince != nil { store.pause(); store.message = "Paused when your Mac went to sleep." } }
    func applicationWillTerminate(_ notification: Notification) { store.pause(); droplet.dismiss(); hotKeys.forEach { UnregisterEventHotKey($0) } }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) { Task { @MainActor in self.show() }; completionHandler() }
}
