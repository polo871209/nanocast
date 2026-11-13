import AVFoundation
import SwiftUI

struct ScreenRecordingSettingsSections: View {
    @Environment(ScreenRecordingCoordinator.self) private var recordings
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Group {
            Section {
                LabeledContent {
                    if settings.screenRecordingSaveFolder != nil {
                        Button("Use Default", action: recordings.resetSaveFolder)
                    }
                    Button("Choose…", action: recordings.chooseSaveFolder)
                } label: {
                    SettingsRowTitle(.screenRecordingSaving, "Save Folder")
                    Text((recordings.saveFolder.path as NSString).abbreviatingWithTildeInPath)
                }
                Picker(selection: $settings.screenRecordingFormat) {
                    ForEach(ScreenRecordingFormat.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.screenRecordingSaving, "Format")
                }
            } header: {
                SettingsSectionHeader(.screenRecordingSaving)
            } footer: {
                Text("Record Screen opens a bar to pick the screen, an area or a window, then records it to a file here.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.screenRecordingSystemAudio) {
                    SettingsRowTitle(.screenRecordingCapture, "Record System Audio")
                    Text("The sound your Mac plays, without Nanocast's own.")
                }
                Toggle(isOn: $settings.screenRecordingMicrophone) {
                    SettingsRowTitle(.screenRecordingCapture, "Record Microphone")
                    Text("Your voice, mixed into the same audio track.")
                }
                if settings.screenRecordingMicrophone {
                    Picker(selection: $settings.screenRecordingMicrophoneID) {
                        Text("System Default").tag(String?.none)
                        ForEach(recordings.microphones, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(Optional(device.uniqueID))
                        }
                    } label: {
                        SettingsRowTitle(.screenRecordingCapture, "Microphone")
                    }
                }
                Toggle(isOn: $settings.screenRecordingCamera) {
                    SettingsRowTitle(.screenRecordingCapture, "Show Camera")
                    Text("You, in a round bubble you can move and resize inside the recording.")
                }
                if settings.screenRecordingCamera {
                    Picker(selection: $settings.screenRecordingCameraID) {
                        Text("System Default").tag(String?.none)
                        ForEach(CameraSession.devices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(Optional(device.uniqueID))
                        }
                    } label: {
                        SettingsRowTitle(.screenRecordingCapture, "Camera")
                    }
                }
                Toggle(isOn: $settings.screenRecordingShowsClicks) {
                    SettingsRowTitle(.screenRecordingCapture, "Show Clicks")
                    Text("Draws a ring where the pointer clicks.")
                }
            } header: {
                SettingsSectionHeader(.screenRecordingCapture)
            }
        }
    }
}
