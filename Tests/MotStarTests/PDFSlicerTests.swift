import XCTest
import CoreGraphics
@testable import MotStar

final class PDFSlicerTests: XCTestCase {

    /// Builds a synthetic "tall WebKit page" with simulated text rows.
    private func makeTallPDF(width: CGFloat = 493, height: CGFloat = 2600) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(box)
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        var y = height - 60
        while y > 40 {
            ctx.fill(CGRect(x: 20, y: y, width: width - 40, height: 10))
            y -= 32
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    func testPaginatesIntoTargetPageSize() {
        let input = makeTallPDF()
        let output = PDFSlicer.paginate(input,
                                        pageSize: CGSize(width: 595, height: 842),
                                        margin: 51)
        XCTAssertNotNil(output)
        let provider = CGDataProvider(data: output! as CFData)!
        let doc = CGPDFDocument(provider)!
        XCTAssertGreaterThanOrEqual(doc.numberOfPages, 3)
        for index in 1...doc.numberOfPages {
            let page = doc.page(at: index)!
            let box = page.getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, 595, accuracy: 0.5)
            XCTAssertEqual(box.height, 842, accuracy: 0.5)
        }
    }

    func testAlreadyShortDocumentIsNotSliced() {
        let short = makeTallPDF(height: 600)
        XCTAssertNil(PDFSlicer.paginate(short,
                                        pageSize: CGSize(width: 595, height: 842),
                                        margin: 51))
    }
}
