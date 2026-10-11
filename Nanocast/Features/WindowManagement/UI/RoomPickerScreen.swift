// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import SwiftUI

enum RoomPickerRow: Identifiable {
    case window(RoomLiveWindow)
    case app(RoomSession.App)

    var id: String {
        switch self {
        case .window(let window): "window:\(window.handle)"
        case .app(let app): "app:" + app.bundleID
        }
    }

    var pick: RoomSession.Pick {
        switch self {
        case .window(let window): .window(handle: window.handle)
        case .app(let app): .app(app)
        }
    }
}

struct RoomPickerScreen: PaletteScreen {
    let coordinator: RoomCoordinator
    let session: RoomSession
    let vm: PaletteState

    var rows: [RoomPickerRow] { coordinator.pickerRows(for: vm.query) }

    private var primaryActionTitle: String {
        let rows = rows
        let name = session.roomName
        let add = "Add to “\(name)”"
        guard rows.indices.contains(vm.selection) else { return add }
        return session.picked.contains(rows[vm.selection].pick)
            ? "Remove from “\(name)”" : add
    }

    func activate(at selection: Int) {
        let rows = rows
        guard rows.indices.contains(selection) else { return }
        coordinator.togglePick(rows[selection].pick)
    }

    func secondary(at selection: Int) -> Bool {
        coordinator.savePicked()
        return true
    }

    func tab(at selection: Int, backwards: Bool) -> Bool { true }

    func actions(at selection: Int) -> PopoverMenuContent? {
        PopoverMenuContent(
            header: session.roomName,
            items: [
                PopoverMenuItem(
                    title: primaryActionTitle, systemImage: "checkmark.circle", shortcut: "↵"
                ) {
                    activate(at: selection)
                },
                PopoverMenuItem(
                    title: "Save Room", systemImage: Room.sfSymbol, shortcut: "⌘↵"
                ) {
                    coordinator.savePicked()
                }
            ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        let selectedID = rows.indices.contains(selection) ? rows[selection].id : nil
        return AnyView(
            Group {
                if rows.isEmpty {
                    EmptyResults(text: emptyText)
                } else {
                    RoomPickerList(
                        rows: rows, picked: session.picked, selectedID: selectedID,
                        scroll: scroll, onActivate: { coordinator.togglePick($0.pick) })
                }
            }
            .onChange(of: session.revision, initial: true) { coordinator.previewPicked() })
    }

    private var emptyText: String {
        guard session.isLoaded else { return "Reading windows…" }
        return vm.query.isEmpty
            ? "No open windows — type an app's name to add it"
            : "No windows or apps found"
    }
}
