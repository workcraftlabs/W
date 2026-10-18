import SwiftUI
import AppKit
import Carbon
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
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 570), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelRoot(store: store, dock: { [weak self] in self?.dock() }, hide: { [weak self] in self?.panel.orderOut(nil) }, resize: { [weak self] compact in self?.resize(compact) }))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "W"; statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.toggle() }; return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x57415050, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { store.message = "Shortcut unavailable. Open W from the menu bar." }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        UNUserNotificationCenter.current().delegate = self
        dock(); show()
    }
    func show() { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggle() { panel.isVisible ? panel.orderOut(nil) : show() }
    func resize(_ compact: Bool) {
        let old = panel.frame
        let size = compact ? NSSize(width: 360, height: 145) : NSSize(width: 440, height: 570)
        panel.setFrame(NSRect(x: old.midX - size.width / 2, y: old.maxY - size.height, width: size.width, height: size.height), display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func dock() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 10))
    }
    @objc func sleep() { if store.state.active?.runningSince != nil { store.pause(); store.message = "Paused when your Mac went to sleep." } }
    func applicationWillTerminate(_ notification: Notification) { store.pause(); if let hotKey { UnregisterEventHotKey(hotKey) } }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) { Task { @MainActor in self.show() }; completionHandler() }
}
