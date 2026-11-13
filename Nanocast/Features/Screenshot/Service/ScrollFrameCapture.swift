import ScreenCaptureKit

enum ScrollFrameCapture {
    @concurrent
    static func frame(
        display id: CGDirectDisplayID, area: CGRect, pixelWidth: Int, pixelHeight: Int, band: Int
    ) async -> ScrollFrame? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
            let display = content.displays.first(where: { $0.displayID == id })
        else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(
            display: display, excludingApplications: content.applications.filter { $0.processID == ownPID },
            exceptingWindows: [])
        let configuration = SCScreenshotConfiguration()
        configuration.sourceRect = area
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        // The async overload force-unwraps a nil image, which ScreenCaptureKit returns for DRM video.
        let image = await withCheckedContinuation { continuation in
            SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration) { output, _ in
                continuation.resume(returning: output?.sdrImage)
            }
        }
        return image.flatMap { ScrollFrame(image: $0, ignoringRight: band) }
    }
}
