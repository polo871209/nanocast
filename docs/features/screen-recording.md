# Screen Recording

`Record Screen` is a launcher command that records a display, an area of the screen or one window to a MOV or MP4 file, with your camera and your voice if you want them. One bar sets up the recording and controls it, and ScreenCaptureKit records the live screen.

## Invariants

- **Nothing runs until the command runs.** `ScreenRecordingCoordinator` is `lazy` on `AppCore`. The command checks the Screen Recording grant before it opens the bar, and a Nanocast dialog asks first if the grant is missing.
- **A recording never takes the keyboard.** The recording bar is a `LiveCapturePanel` that cannot become key, so typing during a recording still reaches the recorded app. Its buttons take the first click through `FirstMouseHostingView`.
- **Every end of a recording settles the file.** A save joins the segments into one file in the save folder. A discard, a failure with no segment, or a stop before anything was recorded leaves no file. The segments live in a temporary folder that is deleted when the recording ends. Quitting Nanocast stops and saves the recording before the app exits, through `AppCore.finishWorkForTermination`, so a quit or an update never leaves a half-written file.
- **User actions run in order.** `ScreenRecordingController` chains each segment and the end on one task, so a pause, resume and stop clicked in quick succession apply in the order they were clicked. The session status is the only record of what the user asked for.
- **A pause or stop is never lost.** Both stop the segment's stream. ScreenCaptureKit rejects `stopCapture` for about the first 30 ms of a stream with `SCStreamError -3808`, so `ScreenRecordingRunner` waits for `recordingOutputDidStartRecording` and then retries the stop every 20 ms, for up to one second. A stop a few milliseconds after the start can reach the stream before the first frame is in the file. `SCRecordingOutput` then fails with -5822 and an empty file, and the runner reports this as a cancellation, so the empty segment is dropped without a failure HUD.
- **A recording never shows a stale time.** The bar computes the time from the session status on every tick, and a pause, a resume or a new segment carries the time recorded so far. The time never resets or blanks between segments.
- **A segment never outlives its stream.** Each segment is its own `SCStream`. Removing an `SCRecordingOutput` from a running stream before its first frame crashes `replayd` in `-[AVAssetWriterHelper addInput:]` on macOS 27, which breaks screen capture for every app until launchd restarts it.

## How it is put together

| Piece                                        | Holds                                                                     |
| -------------------------------------------- | ------------------------------------------------------------------------- |
| `Model/ScreenRecordingFormat.swift`          | MOV or MP4, the container setting                                         |
| `Model/ScreenRecordingOptions.swift`         | system audio, the microphone and click rings for one recording            |
| `Model/RecordingTarget.swift`                | what is recorded: a display, an area or a window                          |
| `Service/ScreenRecordingRunner.swift`        | one segment: an `SCStream` and its `SCRecordingOutput`, to a whole file   |
| `Service/RecordingJoinService.swift`         | joins the segments into the saved file                                    |
| `Service/RecordingCamera.swift`              | the `AVCaptureSession` that feeds the camera bubble                       |
| `Service/MicrophoneMeter.swift`              | the microphone level for the bar, from the stream's microphone samples    |
| `Service/RecordingWindows.swift`             | the window list, a window's frame, and window thumbnails                  |
| `UI/CameraBubble.swift`                      | the round camera preview, which you can move and resize                   |
| `UI/RecordingPickerPanel.swift`              | the grid of the desktop and the windows to record                         |
| `UI/ScreenRecordingCoordinator.swift`        | the command, the save folder, and at most one recording                   |
| `UI/ScreenRecordingController.swift`         | the border, the bar, the segments, and the file's fate when it ends       |
| `UI/ScreenRecordingView.swift`               | the bar: target, microphone, camera, time, record or pause, stop, discard |
| `Settings/ScreenRecordingSettingsSections.swift` | the Recordings and Recording Options sections of the Screen pane      |

The area choice opens the screenshot overlay with `ScreenshotSession.Purpose.recording`. See [screenshot.md](screenshot.md#picking-an-area-for-a-recording). The border, the bar and their placement reuse the screenshot feature's `LiveCapturePanel`, `FirstMouseHostingView`, `ChromePlacement` and toolbar buttons.

## One bar sets up and records

`Record Screen` opens the bar on the display under the pointer, set to record that whole display. Nothing is captured until you press record. The bar opens in the bottom-right corner of that display's visible frame. Drag its grip to move it. After a drag, it stays where you put it for the rest of the recording, and a new target no longer moves it. The bar holds these controls, from left to right:

1. A grip and three target buttons: the entire desktop, an area, and a window or the desktop from a grid. They work only before the recording starts.
2. The microphone and camera switches. They start from **Record Microphone** and **Show Camera** in the pane, work at any time, and write each change back to the pane.
3. The time recorded so far, with a dot that is red while recording.
4. Record, which turns into pause while recording and into resume while paused.
5. Stop, which saves, and ✗, which cancels before the start and discards after it.

The area button hides the bar and opens the screenshot overlay. A drag picks an area, and a click on a window picks that window. The window button opens a grid with a thumbnail of each choice. It lists the entire desktop first, as one card per display when there are several, then the open windows of other apps. A click picks the card, and Esc or ✗ closes the grid. If the chosen window closes before the recording starts, the target goes back to its display.

Running `Record Screen` again starts the recording when the bar is still in setup, and otherwise stops and saves, so its shortcut is a start and stop key. Stopping from the macOS menu-bar recording indicator saves too.

## What gets recorded

- A display or an area records that part of the display, with a red border around an area. Every Nanocast window except the camera bubble and the [Draw on Screen](screen-draw.md) canvas is left out. Starting or ending Draw on Screen during a recording starts a new segment, because a segment's content filter fixes its windows.
- A window records that window alone with `SCContentFilter(desktopIndependentWindow:)`. The window stays whole when another window covers it or when you switch to another app, and the recording follows it when it moves. The red border follows the window too. A window records at the pixel size it had when the recording started.
- If the camera is on for a window, Nanocast records it in place instead, with `SCContentFilter(display:including:)` cropped to the window's frame. The filter includes only the window and the camera bubble, so the window still stays whole under another window. When the window moves, the bubble moves with it, and once the window holds still for 0.4 s, a new segment starts at the new frame.

## Segments, pauses and live switches

Each record or resume starts a new `ScreenRecordingRunner`, and each pause stops it, which finishes one segment file. While paused, nothing is captured. Turning the microphone or the camera on or off during a recording also ends the segment and starts a new one, because a running `SCStream` cannot add the microphone, and removing an output from it crashes `replayd`. The time keeps counting across that switch, so the bar shows no break.

If a segment's stream ends on its own, because the window closed or the macOS menu-bar indicator stopped it, the recording stops and saves. On stop, `RecordingJoinService` moves a single segment into place, or joins several with an `AVMutableComposition` and a passthrough `AVAssetExportSession`, which copies the samples without a re-encode.

The file is `Screen Recording <date> at <time>.mov` in the save folder, HEVC at up to 60 frames per second, with the pointer. An odd width or height loses its last pixel, because the encoder needs even sizes.

## The camera bubble

With the camera on, the recording shows a round, mirrored camera preview with a white ring, in the bottom-left corner of the target. It starts at the size you last gave it, or at 25% of the target's short side the first time, and it is between 64 and 480 points across. Drag the middle to move it. Drag the ring, scroll, or pinch to resize it. On hover, a white knob shows on the ring, and the pointer turns into a resize cursor over the ring. The cursor comes from a tracking area, because cursor rects work only in a key window and the bubble's panel never becomes key. It stays inside the target, and it moves with the target when the target changes. It is a `LiveCapturePanel`, so it never takes the keyboard. A `CAShapeLayer` mask on the video layer clips the preview to the circle, because `cornerRadius` on the `AVCaptureVideoPreviewLayer` itself did not clip the video. The runner passes the bubble's window number to the content filter, as `exceptingWindows` for a display or an area and as `including` for a window, so the bubble is in the file exactly where it is on screen. A window recording does not composite the camera into its frames, because `AVAssetWriter` on macOS 27 needs the deprecated `expectsMediaDataInRealTime` for live frames. **Camera** in the pane picks the device. If the camera grant is off, the switch stays off and a HUD says so.

Presenter Overlay in the menu bar's Video menu is a macOS feature that Nanocast does not control. No API turns it on, so the bubble is how Nanocast puts you in a recording.

## Audio and clicks

Besides the camera, the Capture section of the pane turns on three things, each read when a recording starts:

- **Record System Audio** sets `capturesAudio`, with `excludesCurrentProcessAudio` so Nanocast's own sounds stay out.
- **Record Microphone** sets `captureMicrophone`, and `microphoneCaptureDeviceID` when the **Microphone** picker names a device. A device that is gone falls back to the system default. `SCRecordingOutput` mixes the microphone into the system audio track, so the file has one audio track.
- **Show Clicks** sets `showMouseClicks`, which draws a ring at each click.

The microphone needs its own grant. Turning the microphone on asks for it through `Permissions.ensureCaptureAccess(for: .audio)`. If the grant is off, the switch stays off and a HUD says so. While recording with the microphone on, a red disc behind the microphone switch grows with your voice. `MicrophoneMeter` reads the stream's microphone samples, which ScreenCaptureKit delivers next to the file, and reports their level about 15 times a second. The grant needs `NSMicrophoneUsageDescription` and the `com.apple.security.device.audio-input` entitlement, as described in [signing.md](../signing.md).

## Where it is reachable from

The launcher, as `CommandID.recordScreen`, which takes aliases and a global shortcut like any other command. There is no default shortcut. The Screen pane in Settings lists the command with `Capture Screenshot` and `Draw on Screen`, then the save folder, the format and the recording options. In `settings.json` they are `screen.commands`, `screen.recordingFolder`, `screen.recordingFormat`, `screen.recordingSystemAudio`, `screen.recordingMicrophone`, `screen.recordingShowsClicks` and `screen.recordingCamera`. The chosen microphone, the chosen camera and the bubble size are machine state, so they have no key. A settings backup carries the format and the four switches, and leaves the folder, the microphone, the camera and the bubble size out, because each belongs to this Mac.
