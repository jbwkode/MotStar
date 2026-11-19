import AppKit
import CoreGraphics
import Foundation

/// Adds a footer to every page of a PDF: the document's file name on the left
/// and "Page n of N" on the right.
///
/// Used when printing only — exported PDFs keep their original appearance.
/// Single-page documents are returned untouched (a page number adds nothing).
enum PDFPageNumbers {

    static func stamping(_ data: Data,
                         fileName: String? = nil,
                         fontSize: CGFloat = 8,
                         bottomInset: CGFloat = 14,
                         sideInset: CGFloat = 51) -> Data {
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

        let inset = min(sideInset, max(0, mediaBox.width / 4))
        let available = mediaBox.width - inset * 2

        for index in 1...source.numberOfPages {
            guard let page = source.page(at: index) else { continue }

            context.beginPDFPage(nil)
            context.saveGState()
            context.drawPDFPage(page)
            context.restoreGState()

            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics

            let pageText = "Page \(index) of \(source.numberOfPages)" as NSString
            let pageSize = pageText.size(withAttributes: attributes)
            pageText.draw(at: NSPoint(x: mediaBox.width - inset - pageSize.width, y: bottomInset),
                          withAttributes: attributes)

            if let fileName, !fileName.isEmpty {
                let maxNameWidth = max(0, available - pageSize.width - 12)
                let fitted = truncated(fileName, to: maxNameWidth, attributes: attributes)
                fitted.draw(at: NSPoint(x: inset, y: bottomInset), withAttributes: attributes)
            }

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        let stamped = output as Data
        return stamped.isEmpty ? data : stamped
    }

    /// Fits a long file name into `maxWidth`, keeping the extension where
    /// possible so the printed footer stays readable.
    private static func truncated(_ fileName: String,
                                  to maxWidth: CGFloat,
                                  attributes: [NSAttributedString.Key: Any]) -> NSString {
        let full = fileName as NSString
        guard maxWidth > 0, full.size(withAttributes: attributes).width > maxWidth else {
            return maxWidth > 0 ? full : ""
        }

        let ns = fileName as NSString
        let ext = ns.pathExtension
        var stem = ext.isEmpty ? fileName : ns.deletingPathExtension
        while !stem.isEmpty {
            stem.removeLast()
            let candidate = (stem + "…" + (ext.isEmpty ? "" : "." + ext)) as NSString
            if candidate.size(withAttributes: attributes).width <= maxWidth {
                return candidate
            }
        }
        return "…" as NSString
    }
}
