import ScreenCaptureKit

enum WindowCapture {
    @concurrent
    static func image(of windowID: UInt32, pixelWidth: Int, pixelHeight: Int) async -> CGImage? {
        guard
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
            let window = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }
        let configuration = SCScreenshotConfiguration()
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.dynamicRange = .sdr
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return await Signposts.interval("WindowCapture.image") {
            // The async overload force-unwraps a nil image, which ScreenCaptureKit returns for DRM video.
            await withCheckedContinuation { continuation in
                SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration) { output, _ in
                    continuation.resume(returning: output?.sdrImage)
                }
            }
        }
    }
}
