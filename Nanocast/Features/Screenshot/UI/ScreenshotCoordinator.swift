import AppKit
import os

@MainActor
@Observable
final class ScreenshotCoordinator {
    private static let logger = Logger(subsystem: "com.nanocast", category: "Screenshot")
    private static let longImageID = CGDirectDisplayID.max

    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var session: ScreenshotSession?
    @ObservationIgnored private var overlay: ScreenshotOverlayController?
    @ObservationIgnored private var scrollCapture: ScrollCaptureController?
    @ObservationIgnored private var capturing: Task<Void, Never>?
    @ObservationIgnored private var capturingWindow: Task<Void, Never>?
    @ObservationIgnored private var readingText: Task<Void, Never>?
    @ObservationIgnored private var isFinishing = false
    @ObservationIgnored private var lastArea: DisplayArea?
    @ObservationIgnored private lazy var pins = PinController { [weak self] image, scale, saving in
        Task { await self?.deliver(image, scale: scale, saving: saving) }
    }

    init(core: AppCore) {
        self.core = core
    }

    var saveFolder: URL {
        guard let chosen = core.settings.screenshotSaveFolder, AppPaths.isFolderPath(chosen) else {
            return Self.desktop
        }
        return URL(filePath: (chosen as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }

    func capture() {
        guard session == nil, scrollCapture == nil, !core.isShowingDialog else { return }
        guard Permissions.isScreenRecordingGranted() else {
            Task { await askForScreenRecording() }
            return
        }
        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        let cursorScreen = NSScreen.underCursor
        let screens = NSScreen.screens.filter { $0 == cursorScreen } + NSScreen.screens.filter { $0 != cursorScreen }
        var places: [CGDirectDisplayID: (frame: CGRect, quartzFrame: CGRect)] = [:]
        let targets = screens.compactMap { screen -> DisplayCapture.Target? in
            guard let id = screen.displayID else { return nil }
            places[id] = (screen.frame, CGDisplayBounds(id))
            return DisplayCapture.Target(
                displayID: id, pixelWidth: Int(screen.frame.width * screen.backingScaleFactor),
                pixelHeight: Int(screen.frame.height * screen.backingScaleFactor))
        }
        let session = ScreenshotSession(windows: WindowFrameProvider.frontToBack(), lastArea: lastArea)
        let metrics = core.settings.interfaceSize.metrics
        let overlay = ScreenshotOverlayController(session: session, metrics: metrics) { [weak self] in
            self?.finish($0)
        }
        self.session = session
        self.overlay = overlay
        capturing = Task { [weak self, places] in
            do {
                try await DisplayCapture.capture(targets) { id, image in
                    guard !Task.isCancelled, let place = places[id] else { return }
                    let display = CapturedDisplay(
                        id: id, image: image, frame: place.frame, quartzFrame: place.quartzFrame)
                    session.add(display)
                    overlay.show(display)
                }
            } catch {
                Self.logger.error("Screen capture failed: \(error.localizedDescription, privacy: .public)")
            }
            guard let self, !Task.isCancelled, self.session === session, session.displays.isEmpty else { return }
            end()
            core.showMessage("Couldn't capture the screen", tone: .danger)
        }
    }

    func chooseSaveFolder() {
        guard
            let url = FolderPicker.choose(
                message: "Choose the folder screenshots are saved in.", startingAt: saveFolder)
        else { return }
        let chosen = url.standardizedFileURL.resolvingSymlinksInPath()
        core.settings.screenshotSaveFolder =
            chosen.path == Self.desktop.resolvingSymlinksInPath().path
            ? nil : (chosen.path as NSString).abbreviatingWithTildeInPath
    }

    func resetSaveFolder() {
        core.settings.screenshotSaveFolder = nil
    }

    private static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private func finish(_ intent: ScreenshotIntent) {
        guard let session else { return }
        if intent == .cancel { return end() }
        guard !isFinishing else { return }
        switch intent {
        case .cancel:
            end()
        case .copyColor(let hex):
            end()
            ScreenshotOutputRunner.copy(hex)
            core.showMessage("Copied \(hex)")
        case .captureWindow:
            captureWindow(for: session)
        case .scroll:
            guard !session.isLongImage, let area = session.area, let display = session.display(area.display) else {
                return
            }
            lastArea = area
            end()
            scroll(area.rect, on: display)
        case .copy, .copyText, .save, .pin:
            guard session.area != nil, intent != .pin || !session.isLongImage else { return }
            isFinishing = true
            let window = capturingWindow
            Task { [weak self] in
                await window?.value
                self?.output(intent, from: session)
            }
        }
    }

    private func captureWindow(for session: ScreenshotSession) {
        guard let shot = session.windowShot else { return }
        capturingWindow?.cancel()
        capturingWindow = Task { [weak self] in
            let image = await WindowCapture.image(
                of: shot.windowID, pixelWidth: shot.frame.width, pixelHeight: shot.frame.height)
            guard let self, !Task.isCancelled, self.session === session else { return }
            session.setWindowImage(image, for: shot.windowID)
            overlay?.refresh()
        }
    }

    private func output(_ intent: ScreenshotIntent, from session: ScreenshotSession) {
        guard self.session === session else { return }
        guard let area = session.area, let display = session.display(area.display) else {
            isFinishing = false
            return
        }
        let annotations = session.board.visible
        let window = session.windowShot?.display == display.id ? session.windowShot : nil
        let mosaic = annotations.contains(where: \.isMosaic) ? session.mosaicSource(for: display) : nil
        let image = ScreenshotRenderer.image(
            of: area.rect, on: display, window: window, annotations: annotations,
            painter: AnnotationAppearance.painter(scale: display.scale, mosaic: mosaic))
        if !session.isLongImage { lastArea = area }
        end()
        guard let image else { return core.showMessage("Couldn't draw the screenshot", tone: .danger) }
        switch intent {
        case .pin:
            let points = display.points(area.rect)
            pins.pin(
                image, scale: display.scale,
                at: CGRect(
                    x: display.frame.minX + points.minX, y: display.frame.maxY - points.maxY, width: points.width,
                    height: points.height))
        case .copyText:
            copyText(in: image)
        default:
            Task { await deliver(image, scale: display.scale, saving: intent == .save) }
        }
    }

    private func copyText(in image: CGImage) {
        core.showProgress("Reading text…")
        let changeCount = NSPasteboard.general.changeCount
        let file = Task { await ScreenshotOutputRunner.temporaryPNG(of: image) }
        readingText?.cancel()
        readingText = Task { [weak self] in
            guard let url = await file.value else {
                self?.core.showMessage("Couldn’t read the text", tone: .danger)
                return
            }
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let text = try await ClipboardTextWorker.extract(at: url, as: .screenshot)
                guard let self else { return }
                guard !text.isEmpty else { return core.showMessage("No text found", tone: .neutral) }
                guard NSPasteboard.general.changeCount == changeCount else {
                    return core.showMessage("Clipboard changed, text not copied", tone: .neutral)
                }
                ScreenshotOutputRunner.copy(text)
                core.showMessage("Copied text")
            } catch is CancellationError {
            } catch {
                Self.logger.error("Text recognition failed: \(String(describing: error), privacy: .public)")
                self?.core.showMessage("Couldn’t read the text", tone: .danger)
            }
        }
    }

    private func scroll(_ area: PixelRect, on display: CapturedDisplay) {
        guard Permissions.ensureAccessibility() else {
            return core.showMessage("Scrolling capture needs Accessibility", tone: .danger)
        }
        let controller = ScrollCaptureController(
            area: area, on: display, metrics: core.settings.interfaceSize.metrics
        ) { [weak self] outcome in
            self?.finishScroll(outcome, scale: display.scale, over: display.frame)
        }
        guard let controller else { return core.showMessage("Couldn't start a scrolling capture", tone: .danger) }
        scrollCapture = controller
        controller.show()
    }

    private func finishScroll(_ outcome: ScrollCaptureController.Outcome, scale: CGFloat, over screen: CGRect) {
        scrollCapture = nil
        switch outcome {
        case .discarded:
            return
        case .failed:
            core.showMessage("Couldn't capture the scrolling area", tone: .danger)
        case .captured(let image):
            editLongImage(image, scale: scale, over: screen)
        }
    }

    private func editLongImage(_ image: CGImage, scale: CGFloat, over screen: CGRect) {
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let display = CapturedDisplay(
            id: Self.longImageID, image: image, frame: CGRect(origin: .zero, size: size),
            quartzFrame: CGRect(origin: .zero, size: size))
        let session = ScreenshotSession(longImage: display)
        let metrics = core.settings.interfaceSize.metrics
        let overlay = ScreenshotOverlayController(session: session, metrics: metrics) { [weak self] in
            self?.finish($0)
        }
        self.session = session
        self.overlay = overlay
        overlay.showLongImage(display, over: screen)
    }

    private func end() {
        capturing?.cancel()
        capturing = nil
        capturingWindow?.cancel()
        capturingWindow = nil
        isFinishing = false
        overlay?.close()
        overlay = nil
        session = nil
    }

    private func deliver(_ image: CGImage, scale: CGFloat, saving: Bool) async {
        guard let png = await ScreenshotOutputRunner.png(of: image, scale: scale) else {
            core.showMessage("Couldn't encode the screenshot", tone: .danger)
            return
        }
        guard saving else {
            ScreenshotOutputRunner.copy(png)
            core.showMessage("Screenshot copied")
            return
        }
        do {
            let url = try await ScreenshotOutputRunner.save(png, in: saveFolder, at: .now)
            core.showMessage("Saved \(url.lastPathComponent)")
        } catch {
            Self.logger.error("Screenshot save failed: \(error.localizedDescription, privacy: .public)")
            ScreenshotOutputRunner.copy(png)
            core.showMessage("Couldn't save, so it was copied", tone: .danger)
        }
    }

    private func askForScreenRecording() async {
        guard
            await core.confirm(
                title: "Allow Screen Recording?",
                message: "Nanocast captures the screen only when you take a screenshot. "
                    + "Turn on Screen Recording for Nanocast, then try again.",
                symbol: "camera.viewfinder", confirmTitle: "Open System Settings", tone: .neutral,
                confirmRole: .standard)
        else { return }
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }
}
