import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

// Generates a transparent PNG: five-pointed star OUTLINE with an "M" inside
// (template-style black artwork, for the title-bar brand glyph).
// Usage: swift generate-star-logo.swift <output>

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: swift generate-star-logo.swift <output.png>")
    exit(1)
}

let canvas = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)
let outerRadius: CGFloat = 415
let innerRadius: CGFloat = 160
let strokeWidth: CGFloat = 62

guard let context = CGContext(
    data: nil, width: canvas, height: canvas,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

// --- Star outline path ------------------------------------------------
var points: [CGPoint] = []
for i in 0..<10 {
    let radius = (i % 2 == 0) ? outerRadius : innerRadius
    let angle = -CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 5
    points.append(CGPoint(x: center.x + radius * cos(angle),
                          y: center.y + radius * sin(angle)))
}
let starPath = CGMutablePath()
starPath.move(to: points[0])
for p in points.dropFirst() { starPath.addLine(to: p) }
starPath.closeSubpath()

context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.setLineWidth(strokeWidth)
context.setLineJoin(.round)
context.setLineCap(.round)
context.addPath(starPath)
context.strokePath()

// --- "M" letterform ------------------------------------------------
let mSize = CGFloat(420)
let font = NSFont.systemFont(ofSize: mSize, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.black
]
let m = NSAttributedString(string: "M", attributes: attributes)
let mSizePx = m.size()
let mRect = CGRect(x: center.x - mSizePx.width / 2,
                   y: center.y - mSizePx.height / 2,
                   width: mSizePx.width,
                   height: mSizePx.height)
let textContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = textContext
m.draw(in: mRect)
NSGraphicsContext.restoreGraphicsState()

guard let output = context.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[1]) as CFURL,
        UTType.png.identifier as CFString,
        1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, output, nil)
CGImageDestinationFinalize(dest)
print("star+M glyph -> \(args[1])")
