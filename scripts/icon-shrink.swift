import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Shrinks the subject of a full-bleed tile by N% and extends the edge
// background colour to fill the canvas. Usage:
//   swift icon-shrink.swift <input> <output> <scale>   (scale e.g. 0.95)

let args = CommandLine.arguments
guard args.count >= 4,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("usage: swift icon-shrink.swift <input> <output> <scale>")
    exit(1)
}
let scale = CGFloat(Double(args[3]) ?? 0.95)
let width = image.width
let height = image.height

// Sample the background colour from the border pixels (average).
var sumR = 0.0, sumG = 0.0, sumB = 0.0, count = 0.0
let sample = CGDataProvider(data: image.dataProvider!.data!)
let data = sample!.data as Data
let bpr = image.bytesPerRow
let bpp = image.bitsPerPixel / 8
let bpc = image.bitsPerComponent

func px(_ x: Int, _ y: Int) -> (Double, Double, Double) {
    let i = y * bpr + x * bpp
    let shift = (bpc == 16) ? 8 : 0
    func v(_ o: Int) -> Double { Double(data[i + o] >> shift) }
    return (v(0), v(1), v(2))
}
func avgBorder() -> (Double, Double, Double) {
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    for x in stride(from: 0, to: width, by: 2) {
        for y in [0, height - 1] {
            let p = px(x, y); r += p.0; g += p.1; b += p.2; n += 1
        }
    }
    for y in stride(from: 0, to: height, by: 2) {
        for x in [0, width - 1] {
            let p = px(x, y); r += p.0; g += p.1; b += p.2; n += 1
        }
    }
    return (r / n, g / n, b / n)
}
let bg = avgBorder()

guard let context = CGContext(
    data: nil, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

context.setFillColor(CGColor(red: bg.0 / 255, green: bg.1 / 255, blue: bg.2 / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

let drawW = CGFloat(width) * scale
let drawH = CGFloat(height) * scale
context.draw(image, in: CGRect(x: (CGFloat(width) - drawW) / 2,
                               y: (CGFloat(height) - drawH) / 2,
                               width: drawW, height: drawH))

guard let output = context.makeImage() else { exit(1) }
let type = UTType.jpeg.identifier as CFString
guard let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: args[2]) as CFURL, type, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, output, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
CGImageDestinationFinalize(dest)
print("shrunk \(Int(scale * 100))% -> \(args[2])")
