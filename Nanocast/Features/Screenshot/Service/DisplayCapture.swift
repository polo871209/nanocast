import AppKit
import ScreenCaptureKit

enum DisplayCapture {
    struct Target: Sendable {
        let displayID: CGDirectDisplayID
        let pixelWidth: Int
        let pixelHeight: Int
    }

    @concurrent
    static func capture(
        _ targets: [Target], deliver: @escaping @MainActor @Sendable (CGDirectDisplayID, CGImage) -> Void
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let chrome = content.windows.filter {
            $0.owningApplication?.processID == ownPID
                && $0.windowLayer >= NSWindow.Level.paletteDropGuide.rawValue
        }
        for target in targets {
            guard !Task.isCancelled else { return }
            guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else { continue }
            let image = await Signposts.interval("DisplayCapture.image") {
                await image(of: display, excluding: chrome, target: target)
            }
            guard let image else { continue }
            await deliver(target.displayID, image)
        }
    }

    private static func image(
        of display: SCDisplay, excluding windows: [SCWindow], target: Target
    ) async
        -> CGImage?
    {
        let filter = SCContentFilter(display: display, excludingWindows: windows)
        let configuration = SCScreenshotConfiguration()
        configuration.width = target.pixelWidth
        configuration.height = target.pixelHeight
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        // The async overload force-unwraps a nil image, which ScreenCaptureKit returns for DRM video.
        return await withCheckedContinuation { continuation in
            SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration) { output, _ in
                continuation.resume(returning: output?.sdrImage)
            }
        }
    }
}
