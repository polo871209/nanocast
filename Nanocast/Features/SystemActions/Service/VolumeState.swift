import Foundation

@Observable
final class VolumeState {
    var level: Double
    var muted: Bool

    init(level: Double, muted: Bool = false) {
        self.level = level
        self.muted = muted
    }
}
