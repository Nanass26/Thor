import SwiftData
import SwiftUI

@main
@MainActor
struct DevisChatApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings

    init() {
        container = Self.makeContainer()
        _settings = State(initialValue: AppSettings(tokenStore: KeychainStore()))
    }

    var body: some Scene {
        WindowGroup {
            QuoteListView()
                .environment(settings)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }

    /// Stockage sur l'appareil ; en cas de problème, stockage en mémoire pour que l'app reste utilisable.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([QuoteRecord.self, MessageRecord.self, CounterRecord.self])
        if let container = try? ModelContainer(for: schema) {
            return container
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("Impossible de créer le stockage local : \(error.localizedDescription)")
        }
    }
}

enum Theme {
    /// Teal #2E6F8E (couleur de la maison).
    static let accent = Color(red: 46 / 255, green: 111 / 255, blue: 142 / 255)
}
