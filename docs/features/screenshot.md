# Screenshot

`Capture Screenshot` is a launcher command that freezes every display, lets the user pick an area or a window with pixel precision, annotate it, and then copy, save or pin it as PNG, or copy the text in it. The scroll button scrolls the content under the area and stitches a long image. The look follows Lark's screenshot tool and the precision follows Shottr.

## Invariants

- **Nothing runs until the command runs.** `ScreenshotCoordinator` is `lazy` on `AppCore`. No capture, window list read or Screen Recording check happens before `capture()`. If the grant is missing, a Nanocast dialog asks first and opens System Settings only on confirm.
- **The model works in device pixels with a top-left origin per display.** `CapturedDisplay` is the only converter between canvas points and pixels. `gridPoint` rounds, for edges and corners. `pixel` floors, for the loupe and the color under the cursor. Annotations are stored in the same pixels, so the copied PNG has the exact pixel size of the area and every mark sits where the overlay showed it.
- **One painter draws the canvas and the export.** `AnnotationPainter` paints the marks into the canvas's `AnnotationLayer` and into the export bitmap. Mosaic takes its shape from the painter's static `mosaicPath`, which the canvas composites as GPU layers and the export fills. A change to how a mark looks therefore lands in both places.
- **A window click captures the window's own pixels.** `WindowCapture` asks ScreenCaptureKit for that window alone, without its shadow, so a window covered by another one comes out whole and its rounded corners stay transparent. The canvas shows the shot over the frozen screen as soon as it lands, and copy, save and pin wait for it. Drawing a new area, ⌘A and a right-click that drops the area each drop the shot. Moving or resizing the area keeps it.
- **Nanocast's own chrome never lands in a capture.** `DisplayCapture` excludes every Nanocast window at `.paletteDropGuide` and above: the palette, HUDs, dialogs and the overlay. Settings, Notes, pins and other normal windows stay capturable.
- **Esc never throws away a marked-up area.** With an area, Esc copies like Return, so only the ✗ button discards. With no area, Esc cancels, because there is nothing to copy. While text is being typed, Esc first ends the edit.
- **A scrolling capture holds at most two frames in memory.** `ScrollStitchFile` writes the stitched rows to a temporary file and maps it as the image at the end, so a 20,000 px capture never sits in the footprint. The file goes away with the capture.
- **Every exit releases the frozen screen.** Copy, save, pin, copy color and cancel all go through `ScreenshotCoordinator.end()`. It cancels the capture tasks, closes the panels and drops the session, which holds the only references to the frozen images. A pin keeps only its rendered image, and closing the pin releases it.
- **No text recognition runs in the app process.** Copy Text writes the area to a temporary PNG and reads it in the bundled `ClipboardTextHelper`, so Vision's memory, about 55 MB after one read, leaves with the helper.
- **The overlay never activates Nanocast.** Each `ScreenshotPanel` and each `PinPanel` is a `.nonactivatingPanel`. The app that was frontmost stays frontmost, so a paste after the copy lands where the user was.

## How it is put together

| Piece                                   | Holds                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------- |
| `Model/SelectionEdit.swift`             | one press-to-release edit of the area: draw, move or resize, Shift square, Space pan   |
| `Model/WindowSnapPolicy.swift`          | the frontmost window under a pixel, its visible part and its whole frame               |
| `Model/AnnotationBoard.swift`           | the annotations, the draft, the selection, the text being typed, and undo history      |
| `Model/AnnotationGeometry.swift`        | Shift constraints, the arrow outline, step circles, frames and hit testing             |
| `Model/RowProfile.swift`                | each pixel row as a few column means, compared within a level                          |
| `Model/ScrollStitch.swift`              | where each settled frame's rows land in the long image                                 |
| `Model/ChromePlacement.swift`           | where the toolbar, options bar, size pill and loupe go around the area                 |
| `Service/DisplayCapture.swift`          | the ScreenCaptureKit freeze, one display at a time                                     |
| `Service/WindowCapture.swift`           | one window's own pixels, for a window click                                            |
| `Service/AnnotationPainter.swift`       | Core Graphics and Core Text drawing of every annotation                                |
| `Service/MosaicSource.swift`            | one display shrunk into mosaic blocks and a blur, built on the first mosaic            |
| `Service/ScreenshotRenderer.swift`      | the export bitmap: the screen, the window shot, then the annotations                   |
| `Service/ScrollFrameCapture.swift`      | one capture of the area during a scrolling capture, without Nanocast's windows         |
| `Service/ScrollFrame.swift`             | that capture as 32-bit rows and their `RowProfile`                                     |
| `Service/ScrollStitchFile.swift`        | the stitched rows in a temporary file, and the long image they map to                  |
| `Service/AutoScrollRunner.swift`        | one posted scroll-wheel event                                                          |
| `Service/ScreenshotOutputRunner.swift`  | PNG encoding, the pasteboard write, the file save and the PNG that Copy Text reads     |
| `Service/ScreenshotTextExtractor.swift` | Vision document recognition in tiles. It compiles into the helper, not the app         |
| `UI/ScreenshotCoordinator.swift`        | the command, the permission dialog, the session and pin lifetimes, and the output HUDs |
| `UI/ScreenshotSession.swift`            | the `@Observable` state of one open capture                                            |
| `UI/CaptureCanvasView.swift`            | mouse and key input, the layers, and the text view of a text being typed               |
| `UI/ScreenshotToolbar.swift`            | the SwiftUI toolbar, with `ToolOptionsBar` under it for the active tool                |
| `UI/ScrollCaptureController.swift`      | the scrolling capture's border, its bar, and the scroll-capture loop                   |
| `UI/PinController.swift`                | the open pins, each a `PinPanel` with a `PinView`                                      |

The capture starts with the display under the cursor and shows its panel as soon as its image lands. The other displays follow one by one, because `replayd` serializes concurrent requests. `DisplayCapture` and `WindowCapture` use the completion-handler form of `SCScreenshotManager`, because the async overload force-unwraps the nil image that ScreenCaptureKit returns for DRM video.

The canvas renders imperatively. Each input event mutates the session, then every canvas re-renders inside one `CATransaction` with actions off. The layers inside the area, from the bottom, are the window shot, the pixelate and blur layers masked to the mosaic shapes, and the marks. `AnnotationLayer` is only as big as the marks it holds, so a few marks on a 5K display never allocate a full-screen backing store. The toolbar, the options bar and the size pill are SwiftUI in their own `NSHostingView`s, sized to fit, because a full-canvas hosting view takes every click. The toolbar and the options bar draw at `Theme.Markup.chromeScale` times the interface size, and they always follow the area, with no grip to move them.

Window snap reads `CGWindowListCopyWindowInfo` once, at capture start. That list keeps z-order and needs no Screen Recording grant. Only layer-0 windows of other apps with a non-zero alpha count.

## Input

| When           | Input                                        | Result                                                 |
| -------------- | -------------------------------------------- | ------------------------------------------------------ |
| No area        | click                                        | take the window under the cursor, or the whole display |
| No area        | drag, Shift for a square, hold Space to move | draw the area                                          |
| No area        | Return                                       | restore the last area of this launch                   |
| No tool        | ⌘A                                           | take the whole display                                 |
| No tool        | C                                            | copy the hex color under the cursor and end            |
| No tool        | drag a handle, an edge or the inside         | resize or move the area                                |
| No tool        | arrows                                       | move by 1 px, or by 10 px with Shift                   |
| No tool        | ⌘ plus arrows                                | resize from the bottom-right corner, Shift for 10 px   |
| No tool        | double-click inside                          | copy and end                                           |
| No tool        | right-click                                  | drop the area, if nothing is drawn                     |
| An area exists | a tool's letter, or its toolbar button       | turn the tool on, or off if it is already on           |
| A tool is on   | drag inside the area                         | draw. Shift makes squares, circles and 45° lines       |
| A tool is on   | point at an annotation                       | outline it with a dashed box                           |
| A tool is on   | drag an annotation                           | select and move it, with any tool                      |
| Text tool      | click a text                                 | type into it again                                     |
| A tool is on   | Delete                                       | delete the selected annotation                         |
| A tool is on   | double-click a text                          | type into it again                                     |
| A tool is on   | right-click                                  | turn the tool off                                      |
| Typing         | drag the dashed box around the text          | move the text and keep typing                          |
| Typing         | Esc, or a click outside the box              | end the edit. Empty text is dropped                    |
| An area exists | ⌘Z, ⌘⇧Z                                      | undo, redo                                             |
| An area exists | Return, Esc or ⌘C                            | copy and end                                           |
| An area exists | ⌘S                                           | save and end                                           |
| An area exists | ⇧⌘T, or the text button                      | copy the text in the area and end                      |
| No marks       | the scroll button                            | show the scrolling capture bar for the area            |
| An area exists | click the size pill                          | switch between points and pixels                       |
| An area exists | the ✗ button                                 | discard and end                                        |
| No area        | Esc or right-click                           | cancel                                                 |

## Tools

| Tool        | Key | A drag or a click                                                              | Options                              |
| ----------- | --- | ------------------------------------------------------------------------------ | ------------------------------------ |
| Rectangle   | R   | drag a box                                                                     | stroke width, ink                    |
| Ellipse     | O   | drag an ellipse                                                                | stroke width, ink                    |
| Line        | L   | drag a line                                                                    | stroke width, ink                    |
| Arrow       | A   | drag a tapered arrow, head at the release                                      | stroke width, ink                    |
| Pen         | P   | draw freehand                                                                  | stroke width, ink                    |
| Highlighter | H   | drag a half-transparent straight line, or draw freehand. Shift snaps it to 45° | straight or freehand, width, ink     |
| Text        | T   | click, then type                                                               | text size, ink                       |
| Step        | N   | click to place the next numbered circle, or drag to carry it into place        | size, ink                            |
| Mosaic      | B   | paint with the brush, or drag a box                                            | brush or box, pixelate or blur, size |

Strokes and the highlighter have four widths, from `Theme.Markup.strokes` and `highlighters`. A step's number is its place among the steps, so deleting one renumbers the rest, and a light ink takes a dark number. Mosaic starts in brush mode with pixelate.

## Scrolling capture

The scroll button in the toolbar closes the frozen screen and shows a blue border around the live area, with a bar under it. Nothing scrolls until the Start button or Space. The scroll button is off once anything is drawn, because the marks belong to the frozen screen. It needs Accessibility, and the first press asks for it.

1. Start captures the area, then scrolls it by itself. There is no scrolling by hand. Stop or Space stops the scrolling at any time, and Start goes on from there.
2. macOS sends a posted scroll only to the window under the pointer. So each scroll moves the pointer into the area and moves it back with a mouse-moved event about 10 ms later, which also clears any hover highlight. The pointer is never in a capture, and moving the mouse changes nothing. While a mouse button is down, the next scroll waits.
3. After each scroll, Nanocast waits 300 ms, then captures every 120 ms until two captures match, so a smooth scroll has come to rest. Then it stitches that frame.
4. Each scroll moves 45% of the rows between the sticky header and footer, and the first moves 20% of the area. Each scroll measures how far the app moves per point asked for. If a frame matches nowhere, Nanocast scrolls back and tries again with half the distance, three times at most.
5. At the end of the page or at the 20,000 px cap, the long image opens in the editor by itself. Return, Esc or ✓ opens it at any time. ✗ discards it. If the retries run out, the bar says so and waits.

`ScrollStitch` matches each frame against the one before it. `RowProfile` reduces each row to the mean level of up to 64 column bins, without the 16 pt band at the right where an overlay scrollbar comes and goes. A color conversion moves a pixel by a level, so two rows match when their bins differ by at most one level on average. A frame lands where 60% of the overlap matches, so a hover highlight or an animated image in the overlap does not lose the page. Rows that stay put at the top and the bottom on the first scroll are a sticky header and footer, and each appears once. The offset with the smallest difference wins. If several tie, for example over blank space or a list of identical rows, the one nearest the scroll's own distance wins. Every capture leaves out every Nanocast window, pins and Settings included.

### The long image opens in the editor

The editor shows the long image at its own size in a scroll view over the dimmed screen, as wide as the image and at most as tall as the screen. It is the same `CaptureCanvasView` as the overlay, as the document of an `NSScrollView`, with a `ScreenshotSession(longImage:)` whose one display is the whole image. The area starts as the whole image, so the handles crop it, and every tool, undo, copy and save work as on the frozen screen. Pin and the scroll button are not in its toolbar, because a long image has no place on the screen.

The canvas keeps a tall image within Core Animation's limits. An image taller than 8,192 px shows in 2,048 px strips, and only the strips within one screen of the view hold their pixels. The dim, the border, the handles, the mosaic masks and the marks layer are cut to the visible part. The toolbar, the options bar, the size pill and the loupe sit in the panel above the scroll view, not in the canvas, so a narrow or short image never clips them. They follow the part of the area in view and are placed against the whole screen, as on the frozen screen. A drag near the edge scrolls.

## Output

Copy writes one `.png` item to the general pasteboard, so clipboard history records it like any other image copy. Save writes `Screenshot <date> at <time>.png` to the save folder and never overwrites a file. If the save fails, the PNG is copied instead and the HUD says so. The PNG keeps the display's color profile and is tagged at 72 × scale DPI, so a Retina capture opens at its on-screen size. The hex that C copies is sRGB, so it matches design tools.

An area with no annotations and no window shot is a plain crop of the frozen image. An area that is exactly a clicked window's visible part exports the window's own image, with transparent corners. Anything else composes into one bitmap on the main actor. Encoding and saving run `@concurrent`.

Copy Text reads the rendered image, so text under a mosaic or a mark stays unread. The canvas closes at once and a "Reading text…" pill shows while the helper runs. The helper uses Vision's `RecognizeDocumentsRequest`, which joins the wrapped lines of a paragraph into one line. Vision misses most text on an image over about 4,000 px a side, so the helper reads 2,560 px tiles that overlap by 256 px. Each tile keeps only the lines centred in its half of an overlap, so a line is read once. A line that crosses a tile edge sideways, which only happens in an area wider than 2,560 px, can come out in two parts. The text is bounded at 32,000 UTF-8 bytes, so a long text-dense page copies only its start. The pill then says **Copied text**, **No text found** or **Couldn’t read the text**. If the pasteboard changed while the helper ran, the text is dropped and the pill says **Clipboard changed, text not copied**. A second Copy Text cancels the first.

Pin opens the rendered image in a floating panel over the area it came from. Drag moves a pin, and scroll or pinch zooms it about the cursor. ⌘C copies it, ⌘S saves it, and Esc, ⌘W or a double-click closes it. Several pins can be open at once.

## Where it is reachable from

The launcher, as `CommandID.captureScreenshot`, which takes aliases and a global shortcut like any other command. There is no default shortcut. The Screenshot pane in Settings lists the command and the save folder. The folder is `screenshot.saveFolder` in `settings.json` and the command's shortcut is under `screenshot.commands`. A settings backup leaves the folder out, because it names a folder on this Mac. Tools, inks and sizes are not preferences, so nothing new enters `settings.json`.
