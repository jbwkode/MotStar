import Foundation
import CoreGraphics

/// Crops uniform (white/transparent) margins from an image — used for Quick
/// Look page thumbnails, which are rendered on padded square canvases.
enum ImageTrimming {

    /// Returns the image cropped to the bounding box of non-background pixels
    /// (near-white or transparent counts as background). Falls back to the
    /// original image when no content is detected.
    static func trimmedWhitespace(_ image: CGImage, tolerance: Int = 18) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else { return image }

        guard let scan = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        scan.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = scan.data else { return image }
        let bytes = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)

        func isBackground(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2]), a = Int(bytes[i + 3])
            if a < 8 { return true }
            return abs(r - 255) <= tolerance && abs(g - 255) <= tolerance && abs(b - 255) <= tolerance
        }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where !isBackground(x, y) {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY, maxX > minX, maxY > minY else { return image }

        // Padding so glyph edges aren't clipped, clamped to the canvas.
        let pad = 3
        let left = max(0, minX - pad)
        let right = min(width - 1, maxX + pad)
        let top = max(0, minY - pad)
        let bottom = min(height - 1, maxY + pad)

        let cropWidth = right - left + 1
        let cropHeight = bottom - top + 1

        // Draw the original offset so the detected box fills the new canvas.
        // Memory row 0 is the top row; CG drawing uses bottom-left origin.
        let cgMinY = height - 1 - bottom

        guard let out = CGContext(
            data: nil,
            width: cropWidth,
            height: cropHeight,
            bitsPerComponent: 8,
            bytesPerRow: cropWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        out.draw(image, in: CGRect(x: -left, y: -cgMinY, width: width, height: height))
        return out.makeImage() ?? image
    }
}
