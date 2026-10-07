import Foundation

/// Préparation des images avant envoi (JPEG compressé). Implémentée par ImageCompressor (UIKit) dans l'app.
protocol ImageProcessing: Sendable {
    func jpegForUpload(_ data: Data) throws -> Data
}

enum ImageError: LocalizedError, Equatable {
    case unreadable
    case tooMany(max: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Cette image est illisible."
        case .tooMany(let max): return "\(max) images maximum par message."
        }
    }
}

enum ImageSizing {
    static let maxDimension: Double = 1600
    static let jpegQuality: Double = 0.7
    static let maxImages = 6

    /// Taille cible : le plus grand côté ramené à 1 600 px, proportions conservées, jamais agrandie.
    static func fitted(width: Double, height: Double, maxDimension: Double = maxDimension) -> (width: Double, height: Double) {
        let longest = max(width, height)
        guard longest > maxDimension, longest > 0 else { return (width, height) }
        let scale = maxDimension / longest
        return ((width * scale).rounded(), (height * scale).rounded())
    }
}

/// Image laissée telle quelle (tests, aperçus).
struct PassthroughImageProcessor: ImageProcessing {
    func jpegForUpload(_ data: Data) throws -> Data { data }
}
