import Foundation

@MainActor
@Observable
final class ScrollCaptureSession {
    enum Status {
        case ready
        case scrolling
        case stopped
        case finished
        case lost
        case full
    }

    let pointWidth: Int
    let scale: CGFloat
    private(set) var pixelHeight = 0
    var status = Status.ready

    init(pointWidth: Int, scale: CGFloat) {
        self.pointWidth = pointWidth
        self.scale = scale
    }

    var pointHeight: Int { Int((CGFloat(pixelHeight) / scale).rounded()) }

    func record(height: Int) {
        if pixelHeight != height { pixelHeight = height }
    }
}
