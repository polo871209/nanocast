import CoreGraphics
import Observation

@MainActor
@Observable
final class WindowSwitchSession {
    private(set) var entries: [WindowSwitchEntry] = []
    private(set) var previews: [UInt32: CGImage] = [:]
    var selection = 0

    @ObservationIgnored private var elements: [Int: WindowSwitchSweep.Element] = [:]

    var selectedElement: WindowSwitchSweep.Element? {
        entries.indices.contains(selection) ? elements[entries[selection].handle] : nil
    }

    func present(_ entries: [WindowSwitchEntry], elements: [Int: WindowSwitchSweep.Element], selection: Int) {
        self.entries = entries
        self.elements = elements
        self.selection = selection
    }

    func step(by delta: Int) {
        guard !entries.isEmpty else { return }
        selection = ((selection + delta) % entries.count + entries.count) % entries.count
    }

    func setPreview(_ image: CGImage, for windowID: UInt32) {
        guard entries.contains(where: { $0.windowID == windowID }) else { return }
        previews[windowID] = image
    }

    func reset() {
        entries = []
        previews = [:]
        elements = [:]
        selection = 0
    }
}
