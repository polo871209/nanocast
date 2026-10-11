import Foundation

enum ClipDragPayload: Equatable, Sendable {
    case file(URL)
    case link(URL, String)
    case text(String)
}

extension ClipboardItem {
    var dragPayload: ClipDragPayload {
        if let path = imagePath ?? filePath { return .file(URL(fileURLWithPath: path)) }
        let copy = text ?? ""
        guard textForm == .link else { return .text(copy) }
        switch LinkDestination.detect(copy) {
        case .web(let url), .network(let url), .deeplink(let url): return .link(url, copy)
        case .path, nil: return .text(copy)
        }
    }
}
