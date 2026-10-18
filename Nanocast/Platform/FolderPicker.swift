import AppKit

@MainActor
enum FolderPicker {
    static func choose(message: String, startingAt directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = message
        panel.directoryURL = directory
        // Nanocast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
