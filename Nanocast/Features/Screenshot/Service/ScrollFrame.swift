import CoreGraphics
import Foundation

struct ScrollFrame: Sendable {
    static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little)

    let width: Int
    let height: Int
    let space: CGColorSpace
    let pixels: Data
    let profile: RowProfile

    var bytesPerRow: Int { width * 4 }

    init?(image: CGImage, ignoringRight band: Int) {
        let width = image.width
        let height = image.height
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, space.model == .rgb else { return nil }
        var pixels = Data(count: width * height * 4)
        let profile = pixels.withUnsafeMutableBytes { bytes -> RowProfile? in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: Self.bitmapInfo.rawValue)
            else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return RowProfile(
                pixels: UnsafeRawBufferPointer(bytes), width: width, height: height, bytesPerRow: width * 4,
                ignoringRight: band)
        }
        guard let profile else { return nil }
        self.width = width
        self.height = height
        self.space = space
        self.pixels = pixels
        self.profile = profile
    }
}
