import CoreGraphics
import Foundation

struct PixelColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(image: CGImage, at point: PixelPoint) {
        guard point.x >= 0, point.y >= 0, point.x < image.width, point.y < image.height,
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var bytes: [UInt8] = [0, 0, 0, 0]
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(
                    x: -point.x, y: point.y + 1 - image.height, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.init(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
}
