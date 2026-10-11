import SwiftUI

struct EntryIconView: View {
    let source: EntryIcon
    var fileURL: URL = URL(fileURLWithPath: "/")
    @State private var image: NSImage?
    @Environment(\.metrics) private var metrics

    init(source: EntryIcon, fileURL: URL = URL(fileURLWithPath: "/")) {
        self.source = source
        self.fileURL = fileURL
        _image = State(initialValue: IconCache.cached(source, fileURL: fileURL))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        .task(id: IconRequest(source)) {
            if let warm = IconCache.cached(source, fileURL: fileURL) {
                image = warm
                return
            }
            image = await IconCache.loadAsync(source, fileURL: fileURL)
        }
    }
}
