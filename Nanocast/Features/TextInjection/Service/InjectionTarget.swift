import AppKit

enum InjectionTarget {
    case external(NSRunningApplication)
    case ownEditor(any InjectableTextView)

    @MainActor
    static func current() -> InjectionTarget? {
        guard let keyWindow = NSApp.keyWindow else {
            return NSWorkspace.shared.frontmostApplication.map(InjectionTarget.external)
        }
        return (keyWindow.firstResponder as? any InjectableTextView).map(InjectionTarget.ownEditor)
    }

    @MainActor
    func restoreFocus() {
        switch self {
        case .external(let app):
            guard !app.isTerminated else { return }
            app.activate()
        case .ownEditor(let editor):
            editor.window?.makeFirstResponder(editor)
        }
    }

    var externalApp: NSRunningApplication? {
        guard case .external(let app) = self else { return nil }
        return app
    }

    var ownEditor: (any InjectableTextView)? {
        guard case .ownEditor(let editor) = self else { return nil }
        return editor
    }
}
