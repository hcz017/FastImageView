import CoreGraphics
import Foundation
import ImageIO

let url = URL(fileURLWithPath: "Tests/FastImageViewCoreTests/Fixtures/sample.jpg")
let context = CGContext(
    data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, context.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("写出 JPEG 失败\n", stderr)
    exit(1)
}
