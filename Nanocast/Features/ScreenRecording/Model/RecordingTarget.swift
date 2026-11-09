import CoreGraphics

enum RecordingTarget: Equatable, Sendable {
    case display(CGDirectDisplayID)
    /// `rect` is in points, relative to the display's top-left corner.
    case area(display: CGDirectDisplayID, rect: CGRect)
    case window(CGWindowID)
}
