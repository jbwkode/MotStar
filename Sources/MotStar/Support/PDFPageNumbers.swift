import AppKit
import CoreGraphics
import Foundation

/// Adds a "Page n of N" footer to every page of a PDF.
///
/// Used when printing only — exported PDFs keep their original appearance.
/// Single-page documents are returned untouched (a page number adds nothing).
enum PDFPageNumbers {

    static func stamping(_ data: Data,
                         fontSize: CGFloat = 8,
                         bottomInset: CGFloat = 14) -> Data {
        guard let provider = CGDataProvider(data: data as CFData),
              let source = CGPDFDocument(provider),
              source.numberOfPages > 1,
              let firstPage = source.page(at: 1) else {
            return data
        }

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return data }

        var mediaBox = firstPage.getBoxRect(.mediaBox)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return data }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor(white: 0.35, alpha: 1)
        ]

        for index in 1...source.numberOfPages {
            guard let page = source.page(at: index) else { continue }

            context.beginPDFPage(nil)
            context.saveGState()
            context.drawPDFPage(page)
            context.restoreGState()

            let text = "Page \(index) of \(source.numberOfPages)" as NSString
            let size = text.size(withAttributes: attributes)
            let origin = NSPoint(x: (mediaBox.width - size.width) / 2, y: bottomInset)

            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            text.draw(at: origin, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()

            context.endPDFPage()
        }
        context.closePDF()

        let stamped = output as Data
        return stamped.isEmpty ? data : stamped
    }
}
