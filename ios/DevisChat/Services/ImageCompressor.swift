import Foundation
import UIKit

/// Redimensionne (1 600 px max) et convertit en JPEG qualité 0,7 — HEIC compris (UIImage sait le lire).
struct ImageCompressor: ImageProcessing {
    func jpegForUpload(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw ImageError.unreadable }
        let pixelWidth = Double(image.size.width * image.scale)
        let pixelHeight = Double(image.size.height * image.scale)
        let target = ImageSizing.fitted(width: pixelWidth, height: pixelHeight)
        let size = CGSize(width: target.width, height: target.height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size)) // respecte l'orientation de la photo
        }
        guard let jpeg = resized.jpegData(compressionQuality: CGFloat(ImageSizing.jpegQuality)) else {
            throw ImageError.unreadable
        }
        return jpeg
    }
}
