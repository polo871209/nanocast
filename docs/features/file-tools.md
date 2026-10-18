# File Tools

File Tools acts on files that File Search found or that are selected in Finder. Tab on a selected file opens the File Tools screen with that file as its subject. The File Tools command over Finder opens the same screen with the Finder selection as its subject. The screen lists what can be done to the subject: convert, compress, resize, change speed, trim, combine, split, archive, send or move it. ↵ runs the selected tool and writes new files beside the originals. From File Search, the new files then become the subject, so a second tool can follow at once. From Finder, the palette closes and Finder selects the new files.

The feature is off by default.

## Invariants

- **One screen, whatever the entry.** Tab and ⌘K **File Tools…** on a File Search row or a launcher Files row call `FileToolsCoordinator.open(_:)`. The command over Finder and Tab in Finder call `show()`. Every entry builds a `FileToolsSubject` and shows the same `FileToolsScreen`, so no view branches on where the files came from.
- **The origin decides two things only.** `FileToolCatalog` adds the Finder-only tools for a subject from Finder, and `FileToolsCoordinator.returnsToFinder` sends a finished action back to Finder. A subject from File Search never lists the Finder-only tools, so the screen shows a shorter list and never a disabled row.
- **The original is never written.** The helper writes into a staging folder that `FileManager` gives for the destination's volume. `FileToolWorker` then moves the result to a free name beside the original. The move fails if that name was taken in the meantime, so a job never replaces a file. A failed or cancelled job deletes the staging folder. Move to and Copy to are the only tools that change a folder's contents, and Replace there sends the old item to the Trash.
- **No conversion runs in the app process.** ImageIO, AVFoundation and PDFKit keep their allocations after the work ends, and the app has a 100 MB resident budget. `FileToolWorker` starts one bundled `FileToolHelper` per job, and the helper exits when the job ends.
- **`FileToolCatalog` is the only source of what is offered.** The list, the search and the request come from `FileToolCatalog.tools(for:context:)`, so the screen never offers a pair the helper cannot run.
- **One job runs at a time.** ↵ while a job runs shows a HUD and starts nothing.
- **A job result is applied only to the job that asked.** `FileToolsSession.startJob` returns an id, and `endJob` refuses any other id. A result that arrives after a cancel, a newer job or the switch turning off is dropped.
- **Tab is claimed only on a selected file.** `FileSearchScreen` and `LauncherScreen` claim Tab only while the feature is on and a file row is selected. In Finder, the tap claims Tab only when Tab in Finder is on and `FinderTabPolicy` says so. ⇧Tab is never claimed outside the File Tools screen.
- **The Finder tap passes any key it is unsure of.** A failed or slow Accessibility read passes the key to Finder, so a Nanocast fault never eats a keystroke.

## How it is put together

| Piece                                              | Holds                                                                                                 |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `Model/FileTool.swift`                             | one tool: kind, target format, option slot, fields, section, title, verb, output and the request      |
| `Model/FileToolFormats.swift`                      | the image, audio and archive formats, the speeds and the quality levels, shared with the helper       |
| `Model/FileToolOption.swift`                       | `FileToolKind`, `FileToolTarget`, `FileToolOption` and its slots, shared with the helper              |
| `Model/FileToolParameters.swift`                   | the typed fields (pages, start, end, size) and `FileToolFieldParser`                                  |
| `Model/FileToolCatalog.swift`                      | which tools fit a file and a subject                                                                  |
| `Model/FileToolOutputName.swift`                   | the free name beside the original: `IMG_2041.png`, then `IMG_2041 2.png`                              |
| `Model/FileToolRequest.swift`                      | the `Codable` job that goes to the helper as one JSON argument                                        |
| `Model/FileToolsSubject.swift`                     | the files the screen acts on, their types and their origin                                            |
| `Model/FinderTabPolicy.swift`                      | whether a key down in Finder opens File Tools                                                         |
| `Helper/`                                          | the helper's `main` and one engine per area: image, code, archive, PDF, media                         |
| `Service/FileToolWorker.swift`                     | the staging folder, the helper process, progress lines, the deadline, cancellation and the final move |
| `Service/FileToolTransfer.swift`                   | Move to and Copy to, with Keep Both and Replace                                                       |
| `Service/FinderSelectionReader.swift`              | the Finder selection as file URLs, through one Apple Events script off the main actor                 |
| `Service/FinderTabTap.swift`                       | the event tap on Finder's process that asks `FinderTabPolicy` for each Tab                            |
| `Service/FileToolPinLoader.swift`                  | an image file decoded at its pin size                                                                 |
| `Service/FileToolsSession.swift`                   | the subject, its tools, the chosen option per slot, the running job and the last outcome              |
| `UI/FileToolsCoordinator.swift`                    | the switch, the command, the entries, `run(_:fields:)`, the transfers and the reports                 |
| `UI/FileToolsScreen.swift`                         | the `PaletteScreen` for `PaletteMode.fileTools`                                                       |
| `UI/FileToolsDestinationScreen.swift`              | the `PaletteScreen` for `PaletteMode.fileToolsDestination`, the folder picker of Move to and Copy to  |
| `UI/FileToolsList.swift`, `UI/FileToolsPane.swift` | the tool list and the right pane                                                                      |
| `Settings/FileToolsSettingsView.swift`             | the pane: the switch, Tab in Finder, the Accessibility row and the File Tools command row             |

## The catalog

`FileToolCatalog.tools(for:context:)` lists the tools in three sections: Convert, Tools and Actions. A file gets the rows of its type:

| Type                                        | Convert                                                | Tools                                                                  | Actions                            |
| ------------------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------- | ---------------------------------- |
| raster image                                | JPEG, PNG, HEIC, AVIF, TIFF, PDF, minus its own format | Compress (lossy source only), Compress to Size, Resize, Strip Metadata | Copy Text, Read QR Code, Pin Image |
| SVG                                         | the same targets, with a Scale option                  | Resize                                                                 | Pin Image                          |
| PDF                                         | PDF to Images, PDF to Text                             | Split PDF, Extract Pages, Compress PDF                                 | Copy Text                          |
| audio (M4A, MP3, AAC, WAV, AIFF, FLAC, CAF) | M4A, WAV, AIFF, FLAC, minus its own format except M4A  | Trim                                                                   |                                    |
| video (MOV, MP4, M4V)                       |                                                        | Change Speed, Change Speed and Pitch                                   |                                    |
| ZIP, TAR (also bzip2 and xz), TAR.GZ, GZ    |                                                        | Extract                                                                |                                    |

Every file and folder also gets Copy Path and AirDrop. Move to and Copy to need File Search on, because the destination is picked by a folder search. A type that ImageIO cannot read on this Mac gets no image rows.

A subject of several files keeps only the tools that every file gets, and each file runs as its own job. A subject from Finder adds four tools that put the files into one output:

- **Compress to ZIP** and **Compress to TAR.GZ**, for any selection, also of one folder.
- **Combine PDFs**, when every file is a PDF.
- **Images to PDF**, when every file is a raster image. The page size follows each image's pixel size and DPI.

### Options and fields

A tool has an option slot, typed fields, or neither. An option has a default, so ↵ never asks first. A field takes text in the header, beside the search field.

| Tool                    | Option or field | Values                                       | Default |
| ----------------------- | --------------- | -------------------------------------------- | ------- |
| Compress                | quality         | High, Medium, Small (quality 0.8, 0.6, 0.4)  | Medium  |
| Resize                  | longest edge    | 3840, 2560, 1920, 1280, 640 px               | 1920    |
| Convert, for an SVG     | scale           | 1×, 2×, 4× the declared size                 | 2×      |
| Change Speed, and Pitch | speed           | 0.5×, 1.5×, 2×, 4×                           | 2×      |
| Convert to M4A          | codec           | AAC, ALAC                                    | AAC     |
| PDF to Images           | page format     | PNG, JPEG                                    | PNG     |
| Compress to Size        | size field      | `500`, `500 KB`, `2 MB`. A bare number is KB |         |
| Extract Pages           | pages field     | `1-3, 5`                                     |         |
| Trim                    | start, end      | `90` or `1:30`. Either one can be empty      |         |

The chosen option is stored per slot in `fileToolsOptions`, as tokens such as `quality.small`, so the next subject starts with it. `FileToolFieldParser` reads the fields when ↵ runs the tool. A bad value shows a HUD with an example and starts nothing.

### What each engine does

| Tools                                        | Engine                                                                                                                                  |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Convert, Compress, Resize, Strip Metadata    | ImageIO. SVG goes through `NSImage`. JPEG and BMP output draw a transparent source on white                                             |
| Compress to Size                             | JPEG or the lossy source format: seven quality steps of a binary search, then scale down by 0.75 until it fits                          |
| Read QR Code                                 | Vision `DetectBarcodesRequest`. Every payload is copied, one per line                                                                   |
| Copy Text                                    | `ClipboardTextWorker`, the clipboard's OCR and PDF text helper                                                                          |
| Compress to ZIP, Compress to TAR.GZ, Extract | `/usr/bin/tar` with `--no-mac-metadata`, skipping `.DS_Store` and `__MACOSX`. GZIP goes through `/usr/bin/gunzip`                       |
| PDF tools, Images to PDF                     | PDFKit. Compress PDF writes JPEG images optimized for screen. PDF to Images renders at 2× on white                                      |
| Change Speed                                 | `AVMutableComposition.scaleTimeRange`, then `AVAssetExportSession`, with the `.spectral` pitch algorithm                                |
| Change Speed and Pitch                       | the same for video. The sound is first rewritten at a sample rate times the speed, because `.varispeed` hangs the export on short clips |
| Trim                                         | `AVAssetExportSession` with a time range. M4A, WAV and AIFF pass through, every other format becomes M4A                                |
| Convert audio                                | `AVAudioFile`: AAC at 256 kbit/s, ALAC, FLAC, or PCM at the source bit depth                                                            |

Extract writes into a new folder named after the archive. If the archive holds one top-level folder, that folder is lifted out instead.

## Output names

`FileToolOutputName` builds the name from the source stem and the tool, then counts up from 2 while the name is taken:

| Tool                 | Output for `IMG_2041.HEIC`, `talk.m4a`, `clip.mov` or `report.pdf` |
| -------------------- | ------------------------------------------------------------------ |
| Convert to PNG       | `IMG_2041.png`                                                     |
| Compress             | `IMG_2041 compressed.heic`                                         |
| Compress to Size     | `IMG_2041 500 KB.heic`                                             |
| Resize at 1280       | `IMG_2041 1280px.heic`                                             |
| Strip Metadata       | `IMG_2041 no metadata.heic`                                        |
| Trim                 | `talk trimmed.m4a`                                                 |
| Change Speed at 2×   | `clip 2×.mov`                                                      |
| Extract Pages 1-3, 5 | `report pages 1-3, 5.pdf`                                          |
| Split PDF            | folder `report pages`, holding `report 1.pdf` and onward           |
| PDF to Images        | folder `report images`, holding `report 1.png` and onward          |
| Compress to ZIP      | `report.zip` for one item, `Archive.zip` for several               |
| Combine PDFs         | `report combined.pdf`, after the first file                        |

Page numbers in Split PDF and PDF to Images are zero-padded to the page count, so the files sort in order. The right pane shows the name the job will use before ↵.

## The screen

`FileToolsScreen` uses the File Search layout: the tool list in the 290 pt column, a hairline, then the right pane. The search field filters the list with the action-menu fuzzy match (`ActionMenuSearchQuery`). A Convert row also matches its file extension, so `jpg` finds Convert to JPEG. The best match is selected.

The right pane is the File Search preview stage (`FileSearchPreviewStage`) for one file, or a tilted stack of up to three icons for several. Then come the File, Output and Where rows, the option buttons or the field hint of the selected tool, and the run button with the tool's verb and ↵. While a job runs, the run button is a progress bar, and a **Cancel Job** button stops the helper. After a job, the pane starts with the outcome, for example "Saved, 1.2 MB, 71% smaller" or "Moved to Downloads".

| Key               | What it does                                                                                          |
| ----------------- | ----------------------------------------------------------------------------------------------------- |
| ↵                 | runs the selected tool                                                                                |
| Tab, ⇧Tab         | picks the next or previous option, or walks into the fields of a tool that has some                   |
| ⌘↵                | shows the subject in Finder                                                                           |
| ⌘K                | the Actions tools, then the File Search actions for a one-file subject, or Show in Finder for several |
| ⌃⌘C               | copies the path of every file in the subject, one per line                                            |
| ⇧⌘C, ⌥⌘C, ⌃X      | the File Search chords, on a one-file subject                                                         |
| Escape            | back to the screen File Tools was opened from, on the same row                                        |

File Search keeps its session while File Tools is on top of it, and Escape pops with `pop(preservingSelection:)`, so the row and its results are still there on the way back. File Tools opened from Finder is a root screen, so Escape closes the palette.

A finished job copies the full path of every output to the clipboard, one per line, and makes the outputs the subject. What happens next depends on the subject's origin:

- **From File Search,** the palette stays, the query clears, the first row is selected and the outcome says "Path copied", so a second tool can follow.
- **From Finder,** the palette closes, Finder comes to the front with the outputs selected, and a HUD says "Saved" with the file name or count, and that the path was copied. If the palette was already hidden, Finder selects the outputs only while Finder is the front app, so a long job never takes focus from another app.
- **With the palette hidden** and the subject from File Search, only the HUD shows.

Move to and Copy to follow the same rule with the moved or copied items. Copy Path, Copy Text and Read QR Code from Finder close the palette and return to Finder after they copy.

A failure opens a Nanocast dialog with the file name. A helper failure reads "The file couldn’t be read, or the new file couldn’t be written." Any other failure shows the system's message, for example for a folder the user cannot write to. If a batch fails part way, the files already written become the subject.

### Actions sit last in the list and also live in ⌘K

The list always shows Convert first, then Tools, then Actions, so Tab on a file lands on a Convert row. ⌘K opens the Actions tools of the subject (Copy Text, Read QR Code, Pin Image, Copy Path, AirDrop, Move to and Copy to) without scrolling past the rest. For a one-file subject, the File Search actions follow (Open, Show in Finder, Share, Copy File, Copy Name, Copy Path, Move to Trash), so Copy Path appears once, with ⌃⌘C.

### Actions that write no file

- **Copy Path** copies the full path of every file in the subject, one per line.

- **Copy Text** and **Read QR Code** put the text of every file on the clipboard, joined by blank lines. If the clipboard changed while they ran, they copy nothing and say so.
- **Pin Image** hides the palette and opens each image in a screenshot pin through `ScreenshotCoordinator.pin(_:scale:centeredIn:)`. The pin is centered on the palette's screen and fits half of its visible frame. The image is decoded at that size, so a 48 MP photo costs only the pin's pixels.
- **AirDrop** opens the system AirDrop sheet through `NSSharingService(named: .sendViaAirDrop)`, the same system-sheet exception as Share.

### Move to and Copy to pick a folder by search

Move to and Copy to push `PaletteMode.fileToolsDestination`. That screen runs the File Search session with the Folders filter, so typing finds folders the same way File Search finds files. ↵ on a folder pops back to File Tools and runs the transfer, and ⌘↵ shows the folder in Finder.

If a name already exists in the folder, a Nanocast dialog asks: Keep Both, Replace or Cancel. Keep Both names the new item `note 2.txt`. Replace moves the existing item to the Trash first. A move into the item's own folder changes nothing, and a copy there makes `note 2.txt`. The moved or copied items become the subject.

## Finder

### The command reads the Finder selection

If the app the palette was summoned over is Finder, the File Tools command reads Finder's selection through Apple Events (`get selection as alias list`). The selection opens File Tools as a root screen, with the Finder-only tools. With nothing selected, a HUD says "Select files in Finder first". Over any other app, the command opens File Search, and with File Search off it shows the same HUD.

The first read shows the macOS Automation prompt for Finder. If the user denies it, the script fails with error -1743, and a Nanocast dialog offers to open Privacy & Security ▸ Automation. `NSAppleEventsUsageDescription` names the Finder selection read.

### Tab in Finder is an opt-in tap

With **Tab in Finder** on, Tab in a Finder window or on the desktop runs the same path as the command. Finder uses Tab to select the next item by name, so the switch is off by default.

`FinderTabTap` is an event tap made with `CGEvent.tapCreateForPid` for Finder's process only, so no other app's keys pass through it. It is installed while `fileToolsEnabled` and `fileToolsFinderTab` are on and Accessibility is granted. The health ticker calls `healthCheck()`, which installs it again after Accessibility is granted or Finder relaunches. For each key down, the callback reads Finder's focused element with a 0.1 s Accessibility timeout and asks `FinderTabPolicy`:

1. A key other than a bare Tab passes.
2. A failed read passes.
3. A text role (rename field, search field, text area, combo box) passes.
4. A file view role (outline, table, list, browser, group, scroll area) with a selection opens File Tools and swallows the key.
5. Every other case passes.

⇧Tab is never claimed, so it keeps its Finder meaning. The switch is left out of settings backups and `settings.json`, as `dictationEnabled` is, because it installs a key tap in another app. An import never turns it on.

## The helper

`FileToolWorker.run` encodes the request as JSON and passes it as the helper's only argument. The helper writes `progress 0.42` lines to its standard output, which the worker reports to the job. Every other line is ignored. Exit 0 means the staged output exists. Read QR Code uses `FileToolWorker.read`, which stages a text file and returns its contents, so nothing lands beside the source.

The worker terminates the helper on task cancellation and after the tool's deadline: 120 seconds for image tools and an hour for every other tool. A batch runs one helper per file, one after another, and reports its progress as one bar. `project.yml` builds `FileToolHelper` from `Helper/` and the four shared model files (`FileToolFormats`, `FileToolOption`, `FileToolParameters`, `FileToolRequest`), and embeds it in `Contents/Helpers`. Its executable name is pinned there, so a renamed product does not break `FileToolWorker.executable`.

## Invocation and settings

Settings ▸ File Tools owns three things:

- `fileToolsEnabled`, off when its preference is absent. It has a `SettingsFileKey` (`fileTools.enabled`) and is carried by settings backups.
- `fileToolsFinderTab`, the Tab in Finder switch, off by default. It is not in `settings.json` and not in backups. While it is on without Accessibility, the pane shows a row that opens Accessibility settings.
- The File Tools command row. `CommandID.fileTools` has no default hotkey, and `SettingsTab.ownedCommands` names it, so Settings ▸ Commands does not list it.

`fileToolsOptions`, the chosen option per slot, has a `SettingsFileKey` (`fileTools.options`) and is carried by backups. It has no control in the pane, because the screen sets it.

`AppCore` observes the two switches and asks `FileToolsCoordinator.applyEnabled()` to project `CommandID.fileTools` into the launcher and to install or remove the tap. Turning the feature off cancels a running job, clears the session, removes the tap and returns an open File Tools screen to the launcher.

## Tests

- `file-tools-test` compiles `Model/`. It checks the catalog per type and per Finder batch, option tokens and cycling, field parsing, output names with collisions, the request round trip, archive names and every `FinderTabPolicy` case.
- `file-tools-helper-test` compiles the engines, the worker, `FileToolTransfer` and the shared model files. It converts a generated PNG, BMP, JPEG and SVG and a 1×1 WebP literal to every output and reads each result back. It checks Compress to Size budgets, a generated QR code, ZIP, TAR.GZ and GZIP round trips, every PDF tool, every audio conversion and trim, and every video speed against the expected length. It also checks the worker's progress, text, failure, move, no-replace and deadline paths with stub helpers, and Keep Both and same-folder transfers.
- A manual check presses Tab in Finder in icon, list, column and gallery view, on the desktop, in a rename field, in the search field, and with nothing selected.
