import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationRequestInFlight = false

    /// Must land before the first scroll view exists, or the scroller switch shows as a flash.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCore.shared.prepareForTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let activation = AppCore.shared.activationPolicy
        if isQuitFromDock, activation.hasOpenWindows {
            activation.closeAll()
            return .terminateCancel
        }
        guard !terminationRequestInFlight else { return .terminateLater }
        terminationRequestInFlight = true
        Task { @MainActor [weak self] in
            await AppCore.shared.stopDictationForTermination()
            await AppCore.shared.flushNotesForTermination()
            self?.terminationRequestInFlight = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private var isQuitFromDock: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication,
            let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }
}
