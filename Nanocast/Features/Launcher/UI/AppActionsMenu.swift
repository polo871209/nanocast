import SwiftUI

@MainActor
enum AppActionsMenu {
    @MainActor
    struct FavoriteActions {
        let isFavorite: Bool
        let canMoveUp: Bool
        let canMoveDown: Bool
        let toggle: () -> Void
        let move: (Int) -> Void
    }

    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, running: Bool,
        favorites: FavoriteActions, onResetRanking: @escaping () -> Void,
        onHideFromSearch: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items = leadingItems(app: app, searchQuery: searchQuery, core: core)
        let isPersistent = !CommandCatalog.isQueryDriven(app)
        if isPersistent {
            items.append(
                PopoverMenuItem(
                    title: favorites.isFavorite
                        ? String(localized: "Remove from Favorites")
                        : String(localized: "Add to Favorites"),
                    systemImage: favorites.isFavorite ? "star.slash" : "star", startsSection: true,
                    shortcut: "⇧⌘F", action: favorites.toggle))
        }
        if favorites.canMoveUp {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move Favorite Up"), systemImage: "arrow.up",
                    shortcut: "⌥⌘↑"
                ) {
                    favorites.move(-1)
                })
        }
        if favorites.canMoveDown {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move Favorite Down"), systemImage: "arrow.down",
                    shortcut: "⌥⌘↓"
                ) {
                    favorites.move(1)
                })
        }
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Reset Ranking"), systemImage: "arrow.counterclockwise"
                ) {
                    onResetRanking()
                })
        }
        let hidesFromRoot = app.kind == .customCommand
        if isPersistent, app.canHideFromSearch || hidesFromRoot {
            let title =
                hidesFromRoot
                ? String(localized: "Hide from Root Search") : String(localized: "Hide from Search")
            items.append(
                PopoverMenuItem(
                    title: title, systemImage: "eye.slash", shortcut: "⇧⌘H", action: onHideFromSearch))
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Restart Application"), systemImage: "arrow.clockwise",
                    startsSection: true, shortcut: "⌘R"
                ) {
                    core.launcherCoordinator.restart(app)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Quit Application"), systemImage: "power", shortcut: "⌃⇧Q"
                ) {
                    core.launcherCoordinator.quit(app)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Force Quit Application"), systemImage: "xmark.circle",
                    shortcut: "⌃⌥⇧Q"
                ) {
                    core.launcherCoordinator.quit(app, force: true)
                })
        }
        if app.kind == .application, app.primaryInstallationID == nil {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Uninstall Application"), systemImage: "trash",
                    startsSection: true, isDestructive: true
                ) {
                    core.uninstallCoordinator.beginUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    private static func leadingItems(
        app: AppEntry, searchQuery: String, core: AppCore
    ) -> [PopoverMenuItem] {
        if app.kind == .customCommand, let command = core.customCommands.command(entryID: app.id) {
            return CustomCommandActionsMenu.leadingItems(
                command: command, coordinator: core.customCommandCoordinator
            ) {
                core.launcherCoordinator.launch(app, searchQuery: searchQuery)
            }
        }
        let primarySymbol =
            switch app.kind {
            case .application, .command: "list.dash.header.rectangle"
            default: "list.bullet.rectangle"
            }
        var items = [
            PopoverMenuItem(
                title: String(localized: app.kind.descriptor.openVerb), systemImage: primarySymbol,
                shortcut: "↵"
            ) { core.launcherCoordinator.launch(app, searchQuery: searchQuery) }
        ]
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "folder", shortcut: "⌘↵"
                ) {
                    core.launcherCoordinator.showInFinder(app)
                })
        }
        return items
    }
}
