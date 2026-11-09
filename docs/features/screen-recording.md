# Screen Recording

`Record Screen` is a launcher command that records an area of the screen or one window to a MOV or MP4 file, with your camera and your voice if you want them. It borrows the screenshot overlay to pick what it records, then records the live screen through ScreenCaptureKit.

## Invariants

- **Nothing runs until the command runs.** `ScreenRecordingCoordinator` is `lazy` on `AppCore`. The Screen Recording grant is checked by the screenshot overlay when the command opens it.
- **A recording never takes the keyboard.** The recording bar is a `LiveCapturePanel` that cannot become key, so typing during a recording still reaches the recorded app. Its buttons take the first click through `FirstMouseHostingView`.
- **Every end of a recording settles the file.** A save keeps it. A discard, a failure, or a stop before the stream existed deletes it. Quitting Nanocast stops and saves the recording before the app exits, through `AppCore.finishWorkForTermination`, so a quit or an update never leaves a half-written file.
- **A stop is never lost.** ScreenCaptureKit rejects `stopCapture` for about the first 30 ms of a stream with `SCStreamError -3808`. `ScreenRecordingRunner` waits for `recordingOutputDidStartRecording` and then retries the stop every 20 ms, for up to one second, so the bar can never stick on "Saving…". A stop a few milliseconds after the start can reach the stream before the first frame is in the file. `SCRecordingOutput` then fails with -5822 and an empty file, and the runner reports this as a cancellation, so no failure HUD shows.

## How it is put together

| Piece                                        | Holds                                                                     |
| -------------------------------------------- | ------------------------------------------------------------------------- |
| `Model/ScreenRecordingFormat.swift`          | MOV or MP4, the container setting                                         |
| `Model/ScreenRecordingOptions.swift`         | system audio, the microphone and click rings for one recording            |
| `Service/ScreenRecordingRunner.swift`        | one `SCStream` with an `SCRecordingOutput`, from start to a complete file |
| `Service/RecordingCamera.swift`              | the `AVCaptureSession` that feeds the camera bubble                       |
| `UI/CameraBubble.swift`                      | the round, draggable camera preview that the recording includes           |
| `UI/ScreenRecordingCoordinator.swift`        | the command, the save folder, and at most one recording                   |
| `UI/ScreenRecordingController.swift`         | the border, the bar, the recording task, and the file's fate when it ends |
| `UI/ScreenRecordingView.swift`               | the bar: elapsed time, discard and stop                                   |
| `Settings/ScreenRecordingSettingsView.swift` | the pane: commands, save folder and format                                |

The area picker is the screenshot overlay with `ScreenshotSession.Purpose.recording`. See [screenshot.md](screenshot.md#picking-an-area-for-a-recording). The border, the bar and their placement reuse the screenshot feature's `LiveCapturePanel`, `FirstMouseHostingView`, `ChromePlacement` and toolbar buttons.

## What gets recorded

- If the picked area is exactly a clicked window's visible part, Nanocast records that window alone with `SCContentFilter(desktopIndependentWindow:)`. The window stays whole when another window covers it, and the recording follows it when it moves. It has no border, because the window can move away from it. A window records at its own pixel size when the recording starts.
- If the camera is on for that window, Nanocast records it in place instead, with `SCContentFilter(display:including:)` cropped to the window's frame. The filter includes only the window and the camera bubble, so the window still stays whole under another window. The crop stays where the window was when the recording started, so the recording has the red border.
- Otherwise Nanocast records the area of the display, with a red border around it. Every Nanocast window is left out.

The bar under the area shows the elapsed time, a ✗ that discards the recording, and a stop button that saves it. Running `Record Screen` again also stops and saves, so its shortcut is a stop key. Stopping from the macOS menu-bar recording indicator saves too.

The file is `Screen Recording <date> at <time>.mov` in the save folder, HEVC at up to 60 frames per second, with the pointer. It is written in place while the recording runs. An odd width or height loses its last pixel, because the encoder needs even sizes. File Tools converts a recording between MOV, MP4 and M4V later, without a re-encode.

## The camera bubble

The picker's toolbar has a microphone switch (M) and a camera switch (C). They start from **Record Microphone** and **Show Camera** in the pane, and the picker writes the last choice back to them.

With the camera on, an area or window recording shows a round, mirrored camera preview inside the area, in its bottom-left corner, 25% of the area's short side and between 80 and 220 points across. Drag it to move it, and it stays inside the area. It is a `LiveCapturePanel`, so it never takes the keyboard. The recording leaves out every Nanocast window except this one. The runner passes the bubble's window number to the content filter, as `exceptingWindows` for an area and as `including` for a window, so the bubble is in the file exactly where it is on screen. A window recording does not composite the camera into its frames, because `AVAssetWriter` on macOS 27 needs the deprecated `expectsMediaDataInRealTime` for live frames. The camera starts before the recording and stops when the recording ends. **Camera** in the pane picks the device. If the camera grant is off, the recording starts without the camera and a HUD says so.

Presenter Overlay in the menu bar's Video menu is a macOS feature that Nanocast does not control. No API turns it on, so the bubble is how Nanocast puts you in a recording.

## Audio and clicks

Besides the camera, the Capture section of the pane turns on three things, each read when a recording starts:

- **Record System Audio** sets `capturesAudio`, with `excludesCurrentProcessAudio` so Nanocast's own sounds stay out.
- **Record Microphone** sets `captureMicrophone`, and `microphoneCaptureDeviceID` when the **Microphone** picker names a device. A device that is gone falls back to the system default. `SCRecordingOutput` mixes the microphone into the system audio track, so the file has one audio track.
- **Show Clicks** sets `showMouseClicks`, which draws a ring at each click.

The microphone needs its own grant. The first recording with the microphone on asks for it through `Permissions.ensureCaptureAccess(for: .audio)`. If the grant is off, the recording starts without the microphone and a HUD says so. The grant needs `NSMicrophoneUsageDescription` and the `com.apple.security.device.audio-input` entitlement, as described in [signing.md](../signing.md).

## Where it is reachable from

The launcher, as `CommandID.recordScreen`, which takes aliases and a global shortcut like any other command. There is no default shortcut. The Screen Recording pane in Settings lists the command, the save folder and the format. In `settings.json` they are `screenRecording.commands`, `screenRecording.saveFolder`, `screenRecording.format`, `screenRecording.systemAudio`, `screenRecording.microphone`, `screenRecording.showsClicks` and `screenRecording.camera`. The chosen microphone and camera are machine state, so they have no key. A settings backup carries the format and the four switches, and leaves the folder, the microphone and the camera out, because each names something on this Mac.
