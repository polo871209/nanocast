import CoreGraphics
import Foundation

enum WindowFrameProvider {
    /// Other apps' normal windows, front to back, in Quartz space. The read needs no Screen Recording.
    static func frontToBack() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return listing.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                window[kCGWindowOwnerPID as String] as? Int32 != ownPID,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let id = window[kCGWindowNumber as String] as? UInt32,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return ScreenWindow(id: id, frame: frame)
        }
    }
}
