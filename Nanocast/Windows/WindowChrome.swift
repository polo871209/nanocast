import AppKit

@MainActor
protocol WindowChrome: AnyObject {
    func install(in window: NSWindow)
}
