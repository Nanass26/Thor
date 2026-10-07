import UIKit
import XCTest
@testable import DevisChat

/// Compression réelle (UIKit) : uniquement dans le simulateur iOS.
final class ImageCompressorTests: XCTestCase {
    private func photo(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor(red: 0.18, green: 0.44, blue: 0.56, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData() ?? Data()
    }

    func testRedimensionneA1600EtConvertitEnJPEG() throws {
        let jpeg = try ImageCompressor().jpegForUpload(photo(width: 4032, height: 3024))
        XCTAssertEqual(Array(jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG attendu")
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(decoded.size.width * decoded.scale, 1600, accuracy: 1)
        XCTAssertEqual(decoded.size.height * decoded.scale, 1200, accuracy: 1)
    }

    func testPetiteImageNonAgrandie() throws {
        let jpeg = try ImageCompressor().jpegForUpload(photo(width: 800, height: 600))
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(decoded.size.width * decoded.scale, 800, accuracy: 1)
    }

    func testImageIllisible() {
        XCTAssertThrowsError(try ImageCompressor().jpegForUpload(Data("pas une image".utf8)))
    }
}
