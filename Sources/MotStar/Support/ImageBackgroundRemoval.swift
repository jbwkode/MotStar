import AppKit

/// Best-effort background removal for artwork that lacks an alpha channel
/// (e.g. JPEG-sourced icons). Removes the border/background colour that is
/// 4-connected to the image edges, turning it transparent — so square logos
/// blend into the title bar. Keeps the original untouched; a proper
/// transparent PNG is always preferable, but this is a decent fallback.
enum ImageBackgroundRemoval {

    /// Returns a copy of `image` with edge-connected background removed.
    /// Returns the original image when nothing can be removed or the image
    /// already has transparency at its corners.
    static func transparentBackground(of image: NSImage, tolerance: Float = 0.22) -> NSImage? {
        let size = image.size
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        guard width <= 2048, height <= 2048 else { return image }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsW: width,
            pixelsH: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return image
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                   from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return image }

        func pixel(_ x: Int, _ y: Int) -> (r: Float, g: Float, b: Float, a: Float) {
            let i = (y * width + x) * 4
            return (Float(data[i]), Float(data[i + 1]), Float(data[i + 2]), Float(data[i + 3]))
        }

        // Already transparent at the corners? Nothing to do.
        if pixel(0, 0).a < 10 || pixel(width - 1, height - 1).a < 10 {
            return image
        }

        // Reference colour: average of the border pixels.
        var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
        var count: Float = 0
        for x in 0..<width {
            for y in [0, height - 1] {
                let p = pixel(x, y)
                if p.a > 200 { sumR += p.r; sumG += p.g; sumB += p.b; count += 1 }
            }
        }
        for y in 0..<height {
            for x in [0, width - 1] {
                let p = pixel(x, y)
                if p.a > 200 { sumR += p.r; sumG += p.g; sumB += p.b; count += 1 }
            }
        }
        guard count > 0 else { return image }
        let refR = sumR / count, refG = sumG / count, refB = sumB / count

        func distance(_ p: (r: Float, g: Float, b: Float, a: Float)) -> Float {
            abs(p.r - refR) + abs(p.g - refG) + abs(p.b - refB)
        }

        // Flood fill from every border pixel while the colour is close to ref.
        var visited = [UInt8](repeating: 0, count: width * height)
        var queue: [Int] = []
        for x in 0..<width {
            queue.append(yIndex(x, 0))
            queue.append(yIndex(x, height - 1))
        }
        for y in 0..<height {
            queue.append(yIndex(0, y))
            queue.append(yIndex(width - 1, y))
        }

        func yIndex(_ x: Int, _ y: Int) -> Int { y * width + x }

        var removed = 0
        while let index = queue.popLast() {
            guard visited[index] == 0 else { continue }
            visited[index] = 1
            let x = index % width
            let y = index / width
            let p = pixel(x, y)
            // Scale tolerance by 255 (3 channels summed) → ~0..765; use a
            // normalized threshold relative to the 255-space distance.
            let scaledTolerance = tolerance * 3 * 255
            guard distance(p) <= scaledTolerance else { continue }

            let i = index * 4
            data[i + 3] = 0 // alpha
            removed += 1

            if x > 0 { queue.append(index - 1) }
            if x < width - 1 { queue.append(index + 1) }
            if y > 0 { queue.append(index - width) }
            if y < height - 1 { queue.append(index + width) }
        }

        guard removed > 0, let cgImage = rep.cgImage else { return image }
        return NSImage(cgImage: cgImage, size: size)
    }
}
