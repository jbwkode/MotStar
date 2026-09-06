import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Pads any image onto a square transparent canvas (fitted, ~88% area),
// so wide or non-square artwork can be used as a macOS app icon source.
// Usage: swift icon-prepare.swift <input> <output>

let args = CommandLine.arguments
guard args.count >= 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("usage: swift icon-prepare.swift <input> <output>")
    exit(1)
}

let canvas = max(image.width, image.height)
let margin = CGFloat(canvas) * 0.06
let maxW = CGFloat(canvas) - margin * 2
let maxH = CGFloat(canvas) - margin * 2
let scale = min(maxW / CGFloat(image.width), maxH / CGFloat(image.height))
let drawW = CGFloat(image.width) * scale
let drawH = CGFloat(image.height) * scale
let originX = (CGFloat(canvas) - drawW) / 2
let originY = (CGFloat(canvas) - drawH) / 2

guard let context = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
context.draw(image, in: CGRect(x: originX, y: originY, width: drawW, height: drawH))

guard let outputImage = context.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[2]) as CFURL,
        UTType.png.identifier as CFString,
        1, nil) else { exit(1) }

CGImageDestinationAddImage(dest, outputImage, nil)
CGImageDestinationFinalize(dest)
print("prepared -> \(args[2])")
