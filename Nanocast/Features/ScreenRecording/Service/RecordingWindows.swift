import ScreenCaptureKit

enum RecordingSubject: Hashable, Sendable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
}

struct RecordableWindow: Identifiable, Sendable {
    let id: CGWindowID
    let title: String
    let processID: pid_t
    let frame: CGRect
}

enum RecordingWindows {
    private static let minimumSide: CGFloat = 80

    /// Other apps' normal windows on screen, front to back. Titles need the Screen Recording grant.
    static func onScreen() -> [RecordableWindow] {
        listing([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID).filter {
            $0.frame.width >= minimumSide && $0.frame.height >= minimumSide
        }
    }

    /// The window's frame in Quartz space, or nil once it is closed.
    static func frame(of id: CGWindowID) -> CGRect? {
        listing(.optionIncludingWindow, id).first?.frame
    }

    @concurrent
    static func thumbnails(
        of subjects: [RecordingSubject], pixelHeight: Int,
        deliver: @escaping @MainActor @Sendable (RecordingSubject, CGImage) -> Void
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        for subject in subjects {
            guard !Task.isCancelled else { return }
            let filter: SCContentFilter
            let frame: CGRect
            switch subject {
            case .display(let id):
                guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                frame = display.frame
            case .window(let id):
                guard let window = content.windows.first(where: { $0.windowID == id }) else { continue }
                filter = SCContentFilter(desktopIndependentWindow: window)
                frame = window.frame
            }
            guard let image = await thumbnail(with: filter, of: frame.size, pixelHeight: pixelHeight) else { continue }
            await deliver(subject, image)
        }
    }

    private static func thumbnail(with filter: SCContentFilter, of size: CGSize, pixelHeight: Int) async -> CGImage? {
        guard size.height > 1 else { return nil }
        let configuration = SCStreamConfiguration()
        let height = min(size.height * 2, CGFloat(pixelHeight))
        configuration.height = Int(height)
        configuration.width = Int(height * size.width / size.height)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        // The async overload force-unwraps a nil image, which ScreenCaptureKit returns for DRM video.
        return await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func listing(_ options: CGWindowListOption, _ id: CGWindowID) -> [RecordableWindow] {
        guard let listing = CGWindowListCopyWindowInfo(options, id) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return listing.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let number = window[kCGWindowNumber as String] as? UInt32,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            let appName = window[kCGWindowOwnerName as String] as? String ?? ""
            let title = window[kCGWindowName as String] as? String ?? ""
            return RecordableWindow(
                id: number, title: title.isEmpty ? appName : title, processID: pid, frame: frame)
        }
    }
}
