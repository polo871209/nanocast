# Draw on Screen

`Draw on Screen` is a launcher command that puts a transparent canvas over every display, so you can draw on the live screen with rectangles, ellipses, arrows, lines, a pen, a highlighter and text in six inks. A bar in the bottom-right corner shows every tool with its key. Ending the mode clears every mark.

## Invariants

- **Nothing runs until the command runs.** `ScreenDrawCoordinator` is `lazy` on `AppCore` and holds at most one `ScreenDrawController`. Running the command again ends the mode, so its shortcut is a start and stop key.
- **Ending always clears.** Esc, the ✗ button, the command and a display change all close the controller, which holds the only `ScreenDrawSession` and its board. No mark outlives the mode.
- **The canvas never activates Nanocast.** Each canvas is a `LiveCapturePanel`, a `.nonactivatingPanel` that takes the keyboard, so the app you were in stays frontmost. The bar never takes key, and its buttons take the first click through `FirstMouseHostingView`.
- **A press always draws.** The canvas calls `AnnotationBoard.beginStroke` or `beginText`, never `press`, so a drag that starts on a mark draws a new mark instead of moving the old one. Marks cannot be selected, moved or resized. The one exception is a text tool click on a text, which types into that text again.
- **Typing owns the keyboard.** While a text is open, every plain key goes to its `TextEditOverlay`, so the tool letters type instead of switching tools. ⌘Z, ⌘⇧Z, ⌘X, ⌘C, ⌘V and ⌘A go to the text view, because the panel has no Edit menu. Esc or a click outside the text ends it, and an empty text leaves no mark.
- **The eraser removes whole marks.** `AnnotationBoard.beginErasing` removes every mark the drag passes over, sampled every `hitSlop` along the path, so a fast drag cannot skip a stroke. One drag is one undo step.

## Screen sharing shows the bar

macOS 27 has no public API that hides a window from another app's capture. `NSWindow.sharingType = .none` is a legacy constant that ScreenCaptureKit ignores, and Zoom, Meet, Teams and QuickTime all capture through ScreenCaptureKit. So people who watch your share see the bar. Tab hides the bar, and every tool and ink has a key, so you can draw with no bar on screen.

Nanocast's own `Record Screen` records the canvas and leaves the bar out. The recording passes the canvas windows to `ScreenRecordingRunner` with the camera bubble, as the windows it shows. A segment's content filter fixes its windows when it starts, so starting or ending the mode during a recording starts a new segment through `ScreenRecordingCoordinator.drawingChanged()`. A recording of one window with the camera off uses `SCContentFilter(desktopIndependentWindow:)`, which cannot show the canvas.

## How it is put together

| Piece                            | Holds                                                                      |
| -------------------------------- | -------------------------------------------------------------------------- |
| `Model/DrawTool.swift`           | the eight tools, their keys and symbols, and the annotation each one makes |
| `Model/DrawKey.swift`            | what a typed character picks: a tool by its letter, or an ink by its digit |
| `UI/ScreenDrawCoordinator.swift` | the command, at most one controller, and the recording handoff             |
| `UI/ScreenDrawController.swift`  | one canvas panel per display, the bar panel, and the keys                  |
| `UI/ScreenDrawSession.swift`     | the `@Observable` tool, ink and undo state over one `AnnotationBoard`      |
| `UI/ScreenDrawCanvasView.swift`  | mouse input, the open text's view, and the marks layer of one display      |
| `UI/ScreenDrawToolbar.swift`     | the SwiftUI bar, with each key printed in the corner of its button         |

The drawing reuses the screenshot feature's annotation code: `AnnotationBoard`, `AnnotationPainter`, `AnnotationLayer`, `AnnotationStyle` and its inks. One board holds the marks of every display in top-left global points, with `AnnotationMetrics` at scale 1, so a stroke can cross from one display to the next and undo spans every display. Each canvas draws only the marks that touch its display, in an `AnnotationLayer` as big as those marks, with `contentsScale` set to the display's backing scale.

Text uses `AnnotationText.Face.rounded`, the medium weight of SF Pro Rounded at 20 pt, which is close to the Nunito face that Excalidraw calls Normal. The screenshot tool keeps `.standard`, semibold SF Pro. The face goes into the painter, the text measure in `AnnotationMetrics` and the text view, so the typed text and the drawn text line up.

The canvas panels sit at `.screenshot`, above the menu bar and the Dock. The bar sits one level higher, so a click on a canvas never orders it above the bar. Each canvas sets `ignoresMouseEvents = false`, because a transparent window otherwise lets a click on a clear pixel through to the app below.

## Keys

| Key     | Result                                     |
| ------- | ------------------------------------------ |
| R       | rectangle. Shift makes a square            |
| O       | ellipse. Shift makes a circle              |
| A       | arrow, head at the release. Shift snaps 45° |
| L       | line. Shift snaps 45°                       |
| P       | pen                                        |
| H       | highlighter, freehand and half transparent |
| T       | text. Click, then type                      |
| E       | eraser                                     |
| 1 to 6  | red, yellow, green, blue, black, white     |
| Delete  | clear every mark. ⌘Z brings them back      |
| ⌘Z, ⌘⇧Z | undo, redo                                 |
| Tab     | hide or show the bar                       |
| Esc     | end the mode and clear every mark          |

The letters match the screenshot tool's keys, and every letter but H matches Excalidraw, and `ScreenDrawTests` checks that they stay the same. Picking an ink while the eraser is on switches to the pen. Stroke widths are fixed at `AnnotationStyle`'s defaults, so there is no options bar.

## Where it is reachable from

The launcher, as `CommandID.drawOnScreen`, which takes aliases and a global shortcut like any other command. There is no default shortcut. The Screen pane in Settings lists the command with `Capture Screenshot` and `Record Screen`, and its shortcut is under `screen.commands` in `settings.json`. Tools and inks are not preferences, so each run starts with the red pen.
