import SwiftUI

enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let dialogInset: CGFloat = 18
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 28
        static let sectionHeaderBottom: CGFloat = 4
        static let followTailSlack: CGFloat = 44
        static let sectionSpacing: CGFloat = 12
        static let emojiSectionSpacing: CGFloat = 14
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let formField: CGFloat = 12
        static let emojiCell: CGFloat = 12
        static let menu: CGFloat = 6
        static let menuRow: CGFloat = 10
        static let barControl: CGFloat = 8
        static let menuPanel: CGFloat = 16
        static let dialogSymbol: CGFloat = 16
        static let dialog: CGFloat = 20
        static let thumbnail: CGFloat = 6
        static let glyph: CGFloat = 2
        static let card: CGFloat = 10
        static let roomCard: CGFloat = 16
        static let keyCap: CGFloat = 6
        static let recorderKeyCap: CGFloat = 4
        static let tooltip: CGFloat = 8
        static let switcherPanel: CGFloat = 28
        static let switcherSelection: CGFloat = 18
        static let switcherThumbnail: CGFloat = 12
        static let loupe: CGFloat = 8
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        static let noteWindow = CGSize(width: 440, height: 180)
        static let noteWindowMaxHeight: CGFloat = 860
        static let noteEditorInset: CGFloat = 16
        static let noteEditorTopInset: CGFloat = 6
        static let noteSearchHeight: CGFloat = 34
        static let noteSwitcher = CGSize(width: 300, height: 240)
        static let noteSwitcherEmptyHeight: CGFloat = 96
        static let noteSwitcherDrop: CGFloat = 56
        static let noteHeadingMenu = CGSize(
            width: 220, height: menuRowHeight * 4 + menuRowSpacing * 3 + Spacing.sm * 2)
        static let noteFooterHeight: CGFloat = 28
        static let noteTitlebar: CGFloat = 52
        static let noteTitleInset: CGFloat = 120
        static let noteTrafficLightInset: CGFloat = 20
        static let paletteTopMarginFraction: CGFloat = 0.18
        /// The search row; padded alike above and below, it is the compact bar's whole height.
        static let headerHeight: CGFloat = 36
        static let headerIconSlot: CGFloat = 22
        static let searchFieldMinWidth: CGFloat = 60
        static let headerPadding: CGFloat = 10
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        static let paletteSnapDistance: CGFloat = 8
        static let paletteMinimumVisible: CGFloat = 44
        static let dropGuideDash: CGFloat = 8
        static let dropGuideGap: CGFloat = 12
        static let dropGuideWidth: CGFloat = 2
        static let dropGuideCombinedFlashTolerance: CGFloat = 6
        static let dropGuideFadeThreshold: CGFloat = 36
        static let dropGuideFadeDistance: CGFloat = 180
        static let bottomBarHeight: CGFloat = 52
        /// The unit a form's text area counts its minimum height in, so it scales with the interface.
        static let textAreaUnit: CGFloat = 44
        static let barButtonHeight: CGFloat = 28
        static let rowIcon: CGFloat = 24
        static let resultRowIcon: CGFloat = 26
        static let colorDot: CGFloat = 8
        static let keyCap: CGFloat = 18
        static let recorderKeyCap: CGFloat = 16
        static let shortcutRecorder: CGFloat = 120
        static let shortcutPopoverLine: CGFloat = 14
        static let shortcutPopover = CGSize(
            width: 176,
            height: Spacing.sm * 2 + heroKeyCap + Spacing.sm + shortcutPopoverLine * 2 + Spacing.sm
                + compactKeyCap + calloutCaretHeight)
        static let calloutCaretWidth: CGFloat = 15
        static let calloutCaretHeight: CGFloat = 7
        static let calloutCaretTip: CGFloat = 2.5
        static let compactKeyCap: CGFloat = 15
        static let heroKeyCap: CGFloat = 22
        static let menuButton: CGFloat = 36
        static let noteGlyph: CGFloat = 16
        static let noteEmptyGlyph: CGFloat = 28
        static let hairline: CGFloat = 1
        static let markdownListMarker: CGFloat = 20
        static let markdownQuoteBar: CGFloat = 2
        static let checkbox: CGFloat = 16
        static let clipboardListWidth: CGFloat = 290
        static let emojiGridInset: CGFloat = 16
        static let emojiCell: CGFloat = 56
        static let formMenuMinimumWidth: CGFloat = 200
        static let formMenuExtraRowsHeight: CGFloat = 20
        static let formFieldFocusStroke: CGFloat = 2
        static let actionMenuWidth: CGFloat = 320
        static let clipboardFilterMenuWidth: CGFloat = 200
        static let fileSearchFilterMenuWidth: CGFloat = 200
        static let emojiCategoryMenuWidth: CGFloat = 220
        static let menuRowHeight: CGFloat = menuIcon + Spacing.md * 2
        static let menuRowSpacing: CGFloat = 1
        static let menuSectionHeader: CGFloat = 16
        static let menuVisibleRows: CGFloat = 5.5
        static var menuRowsMaxHeight: CGFloat {
            (menuVisibleRows * (menuRowHeight + menuRowSpacing)).rounded()
        }
        static let menuIcon: CGFloat = 20
        static let clipboardMediaHeight: CGFloat = 260
        static let clipboardPreviewPixel: CGFloat = 900
        static let previewAspectRatio: CGFloat = 16 / 9
        static let settingsWindow = CGSize(width: 900, height: 700)
        static let settingsSidebar: CGFloat = 215
        static let settingsDetailMinimum: CGFloat = 420
        static let settingsRowIcon: CGFloat = 20
        static let settingsRowButton: CGFloat = 24
        static let settingsSidebarGlyph: CGFloat = 14
        static let settingsControlHeight: CGFloat = 28
        static let emojiSkinToneGlyph: CGFloat = 13
        static let emojiSettingsGridPreview: CGFloat = 72
        static let layoutEditorSheet = CGSize(width: 900, height: 660)
        static let layoutInspectorColumn: CGFloat = 300
        static let layoutEntryPopover: CGFloat = 260
        static let layoutPreviewIcon: CGFloat = 22
        static let layoutDisplayTab: CGFloat = 24
        static let layoutControlHeight: CGFloat = 28
        static let layoutFieldUnit: CGFloat = 16
        static let layoutPositionGlyph = CGSize(width: 26, height: 19)
        static let layoutPositionStroke: CGFloat = 1.5
        static let layoutPositionCell: CGFloat = 34
        static let editorSheetWidth: CGFloat = 480
        static let hudMaxWidth: CGFloat = 420
        static let hudEdgeOffset: CGFloat = 48
        static let dialogCompactWidth: CGFloat = 290
        static let dialogWidth: CGFloat = 420
        static let dialogTextHeight: CGFloat = 180
        static let dialogButtonHeight: CGFloat = menuButton - 2
        static let dialogSymbol: CGFloat = 28
        static let dialogSymbolContainer: CGFloat = 52
        static let dialogIcon: CGFloat = 32
        static let cameraStage = CGSize(width: 560, height: 315)
        static let hudWidth: CGFloat = 200
        static let hudHeight: CGFloat = 100
        static let volumeTrackHeight: CGFloat = 6
        static let volumeReadout: CGFloat = 38
        static let roomCardTitleBar: CGFloat = 40
        static let roomCardStroke: CGFloat = 2
        static let roomCardShadowRadius: CGFloat = 24
        static let roomCardShadowOffset: CGFloat = 8
        static let roomCardDot: CGFloat = 8
        static let roomCardIcon: CGFloat = 64
        static let roomCardIconLarge: CGFloat = 96
        static let roomCardIconMinHeight: CGFloat = 160
        static let roomCardLargeIconMinSide: CGFloat = 320
        static let switcherThumbnail = CGSize(width: 312, height: 195)
        static let switcherBadgeIcon: CGFloat = 28
        static let switcherBadgeInset: CGFloat = 6
        static let switcherPlaceholderIcon: CGFloat = 96
        static let switcherSelectionInset: CGFloat = 5
        static let switcherGap: CGFloat = 10
        static let switcherPadding: CGFloat = 10
        static let switcherSelectionStroke: CGFloat = 1.5
        static let switcherScreenFraction = CGSize(width: 0.92, height: 0.85)
        static let switcherMinimumScale: CGFloat = 0.5
        static let captureBorder: CGFloat = 1
        static let captureHandle: CGFloat = 8
        static let captureHandleRim: CGFloat = 1.5
        static let captureHandleReach: CGFloat = 6
        static let captureClickSlop: CGFloat = 3
        static let loupeCell: CGFloat = 8
        static let loupeCaption: CGFloat = 36
        static let loupeOffset: CGFloat = 20
        static let pinMinimum: CGFloat = 40
    }

    enum Markup {
        static let strokes: [CGFloat] = [2, 4, 8, 14]
        static let highlighters: [CGFloat] = [8, 14, 20, 30]
        static let highlighterOpacity: CGFloat = 0.5
        static let textSizes: [CGFloat] = [14, 20, 28]
        static let brushes: [CGFloat] = [12, 24, 40]
        static let stepInset: CGFloat = 5
        static let mosaicBlock: CGFloat = 10
        static let blurBlock: CGFloat = 4
        static let hitSlop: CGFloat = 4
        static let dragSlop: CGFloat = 3
        static let selectionDash: [CGFloat] = [4, 3]
        static let selectionOutset: CGFloat = 4
        static let swatch: CGFloat = 14
        static let levelDots: [CGFloat] = [4, 7, 10]
        static let widthDots: [CGFloat] = [3, 5, 8, 12]
        static let chromeScale: CGFloat = 1.25
        static let scrollStatusWidth: CGFloat = 140
        static let recordingStatusWidth: CGFloat = 72
        static let recordingDot: CGFloat = 8
        static let levelText: [CGFloat] = [10, 13, 16]
    }

    enum Duration {
        static let messageHUD: TimeInterval = 2.4
        static let volumeHUD: TimeInterval = 1.6
        static let enter: TimeInterval = 0.18
        static let exit: TimeInterval = 0.12
        static let dialogEnter: TimeInterval = 0.12
        static let dialogExit: TimeInterval = 0.10
        static let tooltip: TimeInterval = 0.15
        static let dropGuide: TimeInterval = 0.24
        static let tooltipDelay: TimeInterval = 0.4
        static let hover: TimeInterval = 0.12
        static let menuChevron: TimeInterval = 0.34
        static let copyFeedback: TimeInterval = 1.2
        static let settingsReveal: TimeInterval = 0.28
        static let settingsFlash: TimeInterval = 2.0
        static let settingsFlashOut: TimeInterval = 0.6
        static let roomGlide: TimeInterval = 0.32
        static let roomCardEnter: TimeInterval = 0.2
        static let roomCardExit: TimeInterval = 0.18
        static let roomSettle: TimeInterval = 0.25
    }

    enum RoomMotion {
        static let glide = Animation.timingCurve(0.2, 0, 0, 1, duration: Theme.Duration.roomGlide)
    }

    enum CompactBarMotion {
        /// Under the 10pt gap, so resting buttons stand apart and only moving ones fuse.
        static let blend: CGFloat = 8
        /// Parked inside the capsule's end this small, so each button pinches out of it.
        static let parkedScale: CGFloat = 0.36
        /// One button after another, beaded off the capsule.
        static let stagger: TimeInterval = 0.055
        /// A summon lands first; the buttons extrude once the window has arrived.
        static let revealDelay: TimeInterval = 0.12
        /// The glyph surfaces once its glass has formed, and blurs in rather than popping.
        static let glyphDelay: TimeInterval = 0.24
        static let glyphFade: TimeInterval = 0.16
        static let glyphBlur: CGFloat = 4
        /// Past the window's own close animation, so parking the buttons is never seen.
        static let parkAfterHide: TimeInterval = 0.3
        /// The capsule undershoots as it shortens, then settles.
        static let capsule = Animation.spring(response: 0.44, dampingFraction: 0.62)
        /// The buttons barely overshoot: the last rests on the window's edge, which would clip it.
        static let button = Animation.spring(response: 0.44, dampingFraction: 0.86)
    }

    enum MenuMotion {
        static let chevronAnimation = Animation.timingCurve(
            0.16, 1, 0.3, 1, duration: Theme.Duration.menuChevron)
    }

    enum Typography {
        static let searchFieldSize: CGFloat = 20
        static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        /// `NSFont` is not `Sendable`, hence the isolation; every reader is a view anyway.
        @MainActor static let searchFieldNSFont = NSFont.systemFont(
            ofSize: searchFieldSize, weight: .regular)
        static let headerIconSize: CGFloat = 18
        static let headerIcon = Font.system(size: headerIconSize, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        static let panelTitle = Font.headline
        static let calcResult = Font.title
        static let keyCap = Font.caption
        static let compactKeyCap = Font.caption2
        static let heroKeyCap = Font.body
        static let code = Font.system(.callout, design: .monospaced)
        static let bar = Font.callout.weight(.medium)
        static let disclosure = Font.caption.weight(.semibold)
        static let menuRow = Font.body
        static let menuIcon = Font.body
        static let menuSymbolSize: CGFloat = 14
        static let menuSymbolWeight = Font.Weight.medium
        static let noteTitle = Font.headline
    }

    enum Colors {
        static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
        }

        static func ramp(dark: Double, light: Double) -> Color {
            adaptive(dark: .srgbInk(1, alpha: dark), light: .srgbInk(0, alpha: light))
        }

        static let panelScrim = adaptive(dark: .srgbInk(0, alpha: 0.40), light: .srgbInk(1, alpha: 0.55))
        static let dialogDimming = adaptive(
            dark: .srgbInk(0, alpha: 0.34), light: .srgbInk(0, alpha: 0.34))
        static let tooltipShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))

        static let selection = ramp(dark: 0.10, light: 0.09)
        static let rowHover = ramp(dark: 0.05, light: 0.045)
        static let emojiCell = ramp(dark: 0.045, light: 0.04)
        static let emojiHoverBorder = ramp(dark: 0.42, light: 0.34)
        static let emojiSelectionBorder = ramp(dark: 0.92, light: 0.72)
        static let emojiInnerBorder = adaptive(
            dark: .srgbInk(0, alpha: 0.72), light: .srgbInk(1, alpha: 0.72))
        static let menuHover = ramp(dark: 0.10, light: 0.09)
        static let separator = ramp(dark: 0.10, light: 0.12)
        static let controlSurface = ramp(dark: 0.10, light: 0.08)
        static let controlHover = ramp(dark: 0.16, light: 0.14)
        static let controlPressed = ramp(dark: 0.24, light: 0.20)
        static let compactShortcutGlassSelection = ramp(dark: 1, light: 0)
        static let compactShortcutSelection = ramp(dark: 0.20, light: 0.55)
        static let compactShortcutSelectedInk = adaptive(
            dark: .srgbInk(1, alpha: 1), light: .srgbInk(1, alpha: 1))
        static let border = ramp(dark: 0.20, light: 0.18)
        static let textPrimary = ramp(dark: 1.0, light: 1.0)
        static let textSecondary = ramp(dark: 0.60, light: 0.60)
        static let textTertiary = ramp(dark: 0.40, light: 0.42)
        static let menuSymbol = ramp(dark: 0.70, light: 0.70)
        static let noteText = ramp(dark: 0.90, light: 0.85)
        static let iconPlaceholder = ramp(dark: 0.06, light: 0.06)
        static let sheen = ramp(dark: 0.04, light: 0.04)
        static let cardFill = ramp(dark: 0.05, light: 0.04)
        static let cardStroke = ramp(dark: 0.10, light: 0.10)
        static let switcherSelection = ramp(dark: 0.14, light: 0.12)
        static let switcherSelectionRim = ramp(dark: 0.50, light: 0.55)
        static let layoutPreviewWindow = adaptive(
            dark: .srgbInk(1, alpha: 0.22), light: .srgbInk(1, alpha: 0.28))
        static let layoutPreviewWindowSelected = adaptive(
            dark: .srgbInk(1, alpha: 0.38), light: .srgbInk(1, alpha: 0.44))
        static let layoutPreviewGround = adaptive(
            dark: .srgbInk(0, alpha: 0.55), light: .srgbInk(0, alpha: 0.50))
        static let roomPreviewDim = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))
        static let roomCardFill = adaptive(
            dark: .srgbInk(0.16, alpha: 0.94), light: .srgbInk(0.98, alpha: 0.94))
        static let roomCardStroke = Color.accentColor
        static let roomCardShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.25), light: .srgbInk(0, alpha: 0.25))
        static let roomCardDot = ramp(dark: 0.25, light: 0.25)
        static let searchFlash = Color.accentColor.opacity(0.35)
        static let checkerLight = Color(nsColor: .srgbInk(1, alpha: 0.22))
        static let checkerDark = Color(nsColor: .srgbInk(0, alpha: 0.22))
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
        static let dropGuide = ramp(dark: 0.35, light: 0.35)
        static let dropGuideArmed = Color.blue
        static let primaryAction = Color.blue
        static let destructive = Color.red
        static let success = Color.green
        static let warning = Color.orange
        static let progress = Color.blue
        static let captureDim = Color(nsColor: .srgbInk(0, alpha: 0.45))
        static let captureHandleRim = Color(nsColor: .srgbInk(1, alpha: 1))
        static let loupeSurface = adaptive(
            dark: .srgbInk(0.12, alpha: 0.94), light: .srgbInk(0.98, alpha: 0.94))
        static let loupeGrid = Color(nsColor: .srgbInk(0, alpha: 0.18))
        static let markupRed = Color(red: 0.961, green: 0.290, blue: 0.271)
        static let markupYellow = Color(red: 1.0, green: 0.776, blue: 0.039)
        static let markupGreen = Color(red: 0.204, green: 0.780, blue: 0.141)
        static let markupBlue = Color(red: 0.200, green: 0.439, blue: 1.0)
        static let markupBlack = Color(red: 0.122, green: 0.137, blue: 0.161)
        static let markupWhite = Color(nsColor: .srgbInk(1, alpha: 1))
        static let terminalSurface = adaptive(
            dark: .srgbInk(0.07, alpha: 1), light: .srgbInk(0.99, alpha: 1))
    }
}

extension View {
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }
}
