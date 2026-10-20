import Foundation
import CoreGraphics

/// Turns WebKit's single tall "page" into real paginated A4 pages.
///
/// WKWebView.createPDF returns one page containing the whole document. This
/// paginator slices that page into page-sized bands, choosing each cut near
/// the ideal boundary but snapping to a blank line so text isn't split across
/// pages. Content is drawn (not rasterised), preserving selectable text.
enum PDFSlicer {

    /// - Parameters:
    ///   - data: PDF containing a single tall page.
    ///   - pageSize: target page size in points (A4 = 595×842).
    ///   - margin: page margin in points applied on all sides.
    static func paginate(_ data: Data, pageSize: CGSize = CGSize(width: 595, height: 842), margin: CGFloat = 51) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages == 1,
              let page = document.page(at: 1) else { return nil }

        let sourceBox = page.getBoxRect(.mediaBox)
        let sourceWidth = sourceBox.width
        let sourceHeight = sourceBox.height
        let printableWidth = pageSize.width - margin * 2
        guard sourceWidth > 1, sourceHeight > 1, printableWidth > 1 else { return nil }

        // If WebKit laid out wider than the printable area, scale to fit.
        let scale = min(1, printableWidth / sourceWidth)
        let scaledHeight = sourceHeight * scale
        let scaledWidth = sourceWidth * scale
        let printableHeight = pageSize.height - margin * 2
        guard scaledHeight > printableHeight + 1 else { return nil } // already one page

        // Ink map at 1:1 to find blank rows for clean breaks.
        let pxWidth = Int(ceil(sourceWidth))
        let pxHeight = Int(ceil(sourceHeight))
        var rowHasInk = [Bool](repeating: false, count: pxHeight)
        if let ctx = CGContext(data: nil, width: pxWidth, height: pxHeight,
                               bitsPerComponent: 8, bytesPerRow: pxWidth * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pxWidth, height: pxHeight))
            ctx.drawPDFPage(page)
            if let raw = ctx.data {
                let bytes = raw.bindMemory(to: UInt8.self, capacity: pxWidth * pxHeight * 4)
                for y in 0..<pxHeight {
                    var ink = false
                    for x in stride(from: 0, to: pxWidth, by: 2) {
                        let i = (y * pxWidth + x) * 4
                        let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                        if !(r > 244 && g > 244 && b > 244) { ink = true; break }
                    }
                    rowHasInk[y] = ink
                }
            }
        }

        // Row 0 in bitmap memory corresponds to the top of the page.
        func blankRow(nearTopY point: CGFloat) -> CGFloat {
            guard !rowHasInk.isEmpty else { return point }
            let idealRow = Int(round(point))
            guard idealRow > 0, idealRow < pxHeight - 1 else { return point }
            let searchRadius = 80
            for offset in 0...searchRadius {
                for candidate in [idealRow - offset, idealRow + offset] where candidate > 0 && candidate < pxHeight - 1 {
                    if !rowHasInk[candidate] && !rowHasInk[candidate + 1] {
                        return CGFloat(candidate)
                    }
                }
            }
            return point
        }

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var top: CGFloat = 0 // in scaled page coordinates, measured from the top
        var pageIndex = 0
        while top < scaledHeight - 0.5 && pageIndex < 500 {
            pageIndex += 1
            let idealCut = top + printableHeight
            let remaining = scaledHeight - top
            var cut = min(idealCut, scaledHeight)
            if remaining > printableHeight + 60 {
                // Snap to a blank row (convert scaled row → source row).
                let snappedSourceRow = blankRow(nearTopY: min(sourceHeight - 2, cut / scale))
                let snapped = snappedSourceRow * scale
                if snapped > top + printableHeight * 0.4 {
                    cut = snapped
                }
            }
            let bandHeight = min(cut - top, printableHeight)
            guard bandHeight > 1 else { break }

            pdf.beginPDFPage(nil)
            pdf.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            pdf.fill(mediaBox)

            let bandBottomInPage = scaledHeight - cut // CG y of band's lower edge
            let pageBottom = pageSize.height - margin - bandHeight
            let xOffset = margin + (printableWidth - scaledWidth) / 2

            pdf.saveGState()
            pdf.clip(to: CGRect(x: xOffset, y: pageBottom, width: scaledWidth, height: bandHeight))
            pdf.translateBy(x: xOffset, y: pageBottom - bandBottomInPage)
            pdf.scaleBy(x: scale, y: scale)
            pdf.drawPDFPage(page)
            pdf.restoreGState()
            pdf.endPDFPage()

            top = cut
        }
        pdf.closePDF()
        return output as Data
    }
}
