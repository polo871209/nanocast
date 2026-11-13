import CoreGraphics
import ScreenCaptureKit

enum WindowPreviewCapture {
    static var isPermitted: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        guard !isPermitted else { return }
        CGRequestScreenCaptureAccess()
    }

    @concurrent
    static func stream(
        _ windowIDs: [CGWindowID], pixelHeight: Int, interval: Duration,
        deliver: @escaping @MainActor @Sendable (CGWindowID, CGImage) -> Void
    ) async {
        guard
            let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        else { return }
        let available = Dictionary(
            content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        let windows = windowIDs.compactMap { available[$0] }
        while !Task.isCancelled {
            for window in windows {
                guard !Task.isCancelled else { return }
                guard let image = await capture(window, pixelHeight: pixelHeight) else { continue }
                await deliver(window.windowID, image)
            }
            try? await Task.sleep(for: interval)
        }
    }

    private static func capture(_ window: SCWindow, pixelHeight: Int) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }
        let configuration = SCStreamConfiguration()
        let height = min(frame.height * 2, CGFloat(pixelHeight))
        configuration.height = Int(height)
        configuration.width = Int(height * frame.width / frame.height)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // The async overload force-unwraps a nil image, which ScreenCaptureKit returns for DRM video.
        return await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
