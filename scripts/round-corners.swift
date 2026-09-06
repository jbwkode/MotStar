import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Rounds the corners of a JPEG/PNG image with a transparent alpha mask.
// Usage: swift round.swift <input> <output> <radiusPx>

let args = CommandLine.arguments
guard args.count >= 4,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("usage: swift round.swift <input> <output> <radiusPx>")
    exit(1)
}
let radius = CGFloat(Double(args[3]) ?? 64)
let width = image.width
let height = image.height

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let rect = CGRect(x: 0, y: 0, width: width, height: height)
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
context.addPath(path)
context.clip()
context.draw(image, in: rect)

guard let outputImage = context.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[2]) as CFURL,
        UTType.png.identifier as CFString,
        1, nil) else { exit(1) }

CGImageDestinationAddImage(dest, outputImage, nil)
CGImageDestinationFinalize(dest)
print("rounded -> \(args[2])")
