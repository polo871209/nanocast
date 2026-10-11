# Navigation

Two features sit behind one switch. The **window switcher** replaces the macOS app switcher with a panel of live window previews. **Search Menu Bar Items** presses any item in the front app's menu bar, and has its own page, [menu-search.md](menu-search.md), because its internals are a menu walk. This page owns the switcher and the pane the two share.

Ships **off**. Settings › Navigation is the switch. While it is off, the event tap is not installed and ⌘Tab belongs to macOS. The trigger is ⌘Tab by default, and Settings › Navigation › Window Switcher › Shortcut records another one.

The switcher follows [BetterCmdTab](https://github.com/rokartur/BetterCmdTab) with one configuration fixed in code: the previews layout, live previews, no animation, hidden from screen sharing, opened on the display of the focused window, and no search, letter hints, tab drill-down or per-app rules beyond an exclusion list. None of its other settings exist here.

## Invariants

- **The tap is the only input path.** The panel never becomes key, so every key the switcher reacts to reaches it through `WindowSwitchTap`, and `WindowSwitchChord` decides what each event means. While a switch is in progress, the tap swallows every key down and key up, so ⌘Q or ⌘W never reach the front app. Modifier changes always pass through.
- **The trigger is a key combination.** `HotKeyAction.windowSwitcher` is a built-in hotkey action, so the recorder, the conflict check and `settings.json` treat it like any other shortcut. It has no Carbon registration, because the tap reads it, and `acceptsModifierOnly` is false, because the tap needs a key to step. Clearing it restores ⌘Tab through `HotKeyManager.defaultBindings`. While any shortcut records, `applyTrigger` lifts the trigger so the recorder can capture the chord.
- **The tap sits at the head of the HID stream** (`.cghidEventTap`, `.headInsertEventTap`). Later in the stream, the Dock has already taken ⌘Tab. Nanocast does not call `CGSSetSymbolicHotKeyEnabled`, because that change outlives a crash. The cost is that while another app holds Secure Event Input (a focused password field), the tap sees no keys and the macOS switcher opens instead.
- **Chord state lives behind a `Mutex` in `WindowSwitchTap.Relay`.** The C callback runs on the main run loop but outside actor isolation. Actions reach `WindowSwitchCoordinator` through main-actor tasks, in the order the tap produced them.
- **A live `AXUIElement` never outlives one switch.** The pure entry carries a `handle`, and `WindowSwitchSession` keeps the `handle → Element` table `@ObservationIgnored`. Every commit and cancel calls `reset()`, and every ⌘Tab sweeps anew.
- **Nothing in `Model/` knows what a window is.** `WindowSwitchEntry`, `WindowSwitchOrder`, `WindowSwitchChord` and `WindowSwitchGrid` are Foundation-only, so the harness compiles the shipped sources.
- **A preview frame never lands in the wrong switch.** The capture loop is a task the coordinator cancels on close, and `setPreview` drops any window ID that is not in the current entries.

## What it lists

The sweep takes every window with the `AXStandardWindow` subrole from every regular app, on every Space. It drops minimized windows, every window of a hidden app, and every app in `windowSwitcherExcludedApps`. An app with no window is not listed.

The app list is `NSWorkspace.runningApplications` plus every regular app that owns a window but is missing from that list. Xcode's Device Hub respawns itself at launch, so the workspace lists it with pid -1 and never lists the process that owns its windows. `WindowInventory.owningProcess` maps that pid -1 entry to the real process for recency, the frontmost app and the active display.

Apps sort by recency, then each app's windows keep their own AX front-to-back order. `AppRecencyMonitor` seeds the order from the on-screen window list when the switch turns on, then moves an app to the front on every `didActivateApplication`. An app it has never seen sorts after the known ones, by name.

⌘Tab selects the first window of another app, because the macOS switcher lands on the previous app rather than on a sibling window. ⌘⇧Tab selects the last window.

## Keys

The keys below assume the default ⌘Tab. With another trigger, its key replaces Tab and its modifiers replace ⌘. If the trigger itself includes ⇧, only ← steps back.

While ⌘ is held:

- Tab and → step forward, ⇧Tab and ← step back, with wraparound.
- Releasing ⌘ or pressing Return switches to the selection.
- Escape closes the panel and switches nothing.
- A click on a tile switches to it.

## The panel

The panel appears 100 ms after ⌘Tab. If ⌘ is released before that, the switch happens without the panel, so a quick ⌘Tab flips to the previous app with nothing drawn.

The panel opens on the display that holds the frontmost app's focused window, and falls back to the display under the cursor. Tiles wrap at 92% of the visible width. If the rows are taller than 85% of the visible height, every tile shrinks, down to half size. The panel sets `sharingType = .none`, so screen sharing and recordings do not show it.

Each tile is the window preview with its app icon in the top-left corner. The tile draws no text, and `WindowSwitchEntry.label` is only the accessibility label.

## Previews

`WindowPreviewCapture` takes one-shot `SCScreenshotManager` captures of every listed window, then repeats them every 100 ms while the panel shows. It uses one-shot captures, not an `SCStream`, because a stream marks each captured window with the system recording indicator. It calls the completion-handler overload, because the async overload traps when ScreenCaptureKit returns no image, which it does for DRM video.

Previews need Screen Recording. Turning navigation on asks once through `CGRequestScreenCaptureAccess`. Without the grant, each tile shows its app icon.

## Raising

`commit` calls `AXWindowAccess.focus`: raise the window, set `AXFrontmost` on its app, then `NSRunningApplication.activate()`. A window on another Space pulls that Space forward with the macOS slide animation. There is no instant Space switch.

## Wiring

- **`navigationEnabled`** (off) is the switch. `AppCore.observeFeatureSwitches` calls `WindowSwitchCoordinator.applyEnabled`, which installs the tap, starts `AppRecencyMonitor`, asks for Screen Recording and subscribes to `HealthTicker`. If the tap fails to install, it asks for Accessibility through `Permissions.ensureAccessibility`, so a missing or stale grant does not fail silently. The ticker installs the tap once Accessibility is granted and removes it when the grant is revoked.
- **`hotkey.windowSwitcher`** (⌘Tab) is the trigger. It is in `settings.json` as `navigation.windowSwitcherShortcut`, and like Dictation's shortcut it does not ride in backups. `AppCore` tracks `HotKeyManager.revision` and `recordingAction` and calls `applyTrigger`.
- **`windowSwitcherExcludedApps`** (empty) is the exclusion list, in Settings › Navigation › Window Switcher. It rides in backups and in `settings.json` as `navigation.windowSwitcherExcludedApps`.
- **`menuSearchDisabledApps`** (empty) and **`menuSearchShowsAppleMenu`** (off) belong to menu search. [menu-search.md](menu-search.md) owns how they apply.
- `CommandID.searchMenuItems` is the one command `SettingsTab.navigation.ownedCommands` names. The switcher is not a command and has no palette screen.

## Testing

`Tests/window-switch-test.swift` covers the pure half: the tile label, the recency order and its independence from sweep order, the first selection, the chord state machine with the default and a recorded trigger, and the grid fit.

The tap, the sweep, the captures and the raise have no automated coverage. Verify these by hand after a change:

1. A quick ⌘Tab flips to the previous app and draws no panel.
2. A held ⌘Tab shows the panel on the display of the focused window, and the macOS switcher never appears.
3. Escape closes the panel, and the ⌘ release after it switches nothing.
4. A window on another Space is listed, and switching to it pulls that Space forward.
5. Without Screen Recording, tiles show app icons.
