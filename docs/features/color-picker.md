# Color picker

`Pick Color` is a launcher command that copies the hex of one pixel on screen. It opens the system eyedropper, the user clicks a pixel, and Nanocast copies its color as `#RRGGBB` and shows "Copied #RRGGBB" in the HUD.

## Invariants

- **The system draws the eyedropper.** `ColorPickerCoordinator.pick()` calls `NSColorSampler().sample()`, so the loupe, the cursor and Esc belong to macOS. The sampler needs no Screen Recording grant.
- **The hex is sRGB.** The sampled `NSColor` is converted with `usingColorSpace(.sRGB)` before `ColorFormat.hex` formats it, so the hex matches design tools and web pages.
- **Esc copies nothing.** If the user cancels, `sample()` returns `nil` and the pasteboard and HUD stay as they were.

## Where it is reachable from

The launcher, as `CommandID.pickColor`, which takes aliases and a global shortcut like any other command. There is no default shortcut. No feature pane owns it, so Settings › Commands lists it and its shortcut is under `commands.builtIn` in `settings.json`. The copy goes to the general pasteboard as a string, so clipboard history records it.
