import Foundation
import SwiftData

/// Un devis (= une conversation) et toutes ses versions.
@Model
final class QuoteRecord {
    @Attribute(.unique) var id: UUID
    var companyId: String
    var number: String?
    var title: String
    var status: String
    var updatedAt: Date
    /// JSON du devis courant (nil tant que l'IA n'a pas encore produit de devis).
    var currentVersion: Data?
    /// JSON de toutes les versions, de la plus ancienne à la plus récente (pour « Annuler »).
    var versions: [Data]
    var coverPhotoFileName: String?
    var priceTTC: Int?
    var missingCount: Int

    init(id: UUID, companyId: String) {
        self.id = id
        self.companyId = companyId
        self.number = nil
        self.title = "Nouveau devis"
        self.status = QuoteStatus.draft.rawValue
        self.updatedAt = Date()
        self.currentVersion = nil
        self.versions = []
        self.coverPhotoFileName = nil
        self.priceTTC = nil
        self.missingCount = 0
    }
}

/// Un message du chat. Les images sont des fichiers dans Application Support (pas de blob ici).
@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var quoteId: UUID
    var role: String
    var text: String
    var createdAt: Date
    var imageFileNames: [String]
    /// Réponse structurée du serveur (JSON), pour réafficher la carte devis, la fiche, les conseils.
    var payload: Data?

    init(id: UUID, quoteId: UUID, role: String, text: String, createdAt: Date, imageFileNames: [String], payload: Data?) {
        self.id = id
        self.quoteId = quoteId
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.imageFileNames = imageFileNames
        self.payload = payload
    }
}

/// Compteur de numéros par entreprise.
@Model
final class CounterRecord {
    @Attribute(.unique) var companyId: String
    var nextNumber: Int
    var year: Int

    init(companyId: String, nextNumber: Int, year: Int) {
        self.companyId = companyId
        self.nextNumber = nextNumber
        self.year = year
    }
}
