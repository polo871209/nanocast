enum ScreenshotIntent: Equatable {
    case copy
    case copyText
    case save
    case pin
    case scroll
    case cancel
    case copyColor(String)
    case captureWindow
}
