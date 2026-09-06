import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Softens the colour of a transparent PNG toward light blue: each opaque
// pixel is mixed (soften% toward a light-blue target) preserving alpha.
// Usage: swift soften-blue.swift <input> <output> [mix 0.0-1.0]

let args = CommandLine.arguments
guard args.count >= 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("usage: swift soften-blue.swift <input> <output> [mix]")
    exit(1)
}
let mix = CGFloat(Double(args.count > 3 ? args[3] : "0.45") ?? 0.45)
let width = image.width
let height = image.height

guard let ctx = CGContext(
    data: nil, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let raw = ctx.data else { exit(1) }
let bytes = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)

// Target: soft light blue.
let tr: CGFloat = 174, tg: CGFloat = 217, tb: CGFloat = 245
var sumR = 0.0, sumG = 0.0, sumB = 0.0, n = 0.0

for i in stride(from: 0, to: width * height * 4, by: 4) {
    let a = bytes[i + 3]
    guard a > 0 else { continue }
    let r = CGFloat(bytes[i])
    let g = CGFloat(bytes[i + 1])
    let b = CGFloat(bytes[i + 2])
    let nr = r * (1 - mix) + tr * mix
    let ng = g * (1 - mix) + tg * mix
    let nb = b * (1 - mix) + tb * mix
    bytes[i] = UInt8(max(0, min(255, nr)))
    bytes[i + 1] = UInt8(max(0, min(255, ng)))
    bytes[i + 2] = UInt8(max(0, min(255, nb)))
    sumR += Double(nr); sumG += Double(ng); sumB += Double(nb); n += 1
}
if n > 0 {
    print(String(format: "avg after -> R%.0f G%.0f B%.0f (alpha px %d)", sumR / n, sumG / n, sumB / n, Int(n)))
}

guard let output = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[2]) as CFURL,
        UTType.png.identifier as CFString,
        1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, output, nil)
CGImageDestinationFinalize(dest)
print("softened -> \(args[2])")
