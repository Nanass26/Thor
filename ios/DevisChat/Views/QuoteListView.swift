import SwiftData
import SwiftUI

/// Écran d'accueil : devis récents, recherche, suppression par balayage, « Nouveau devis ».
@MainActor
struct QuoteListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \QuoteRecord.updatedAt, order: .reverse) private var records: [QuoteRecord]
    @State private var listModel = QuoteListViewModel()
    @State private var path: [UUID] = []
    @State private var showSettings = false
    @State private var showPrivacyNotice = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { summary in
                    NavigationLink(value: summary.id) {
                        QuoteRow(summary: summary)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView(
                        "Aucun devis",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Touche « Nouveau devis », puis envoie une capture AlloVoisins, une photo ou un texte.")
                    )
                }
            }
            .searchable(text: $listModel.searchText, prompt: "Rechercher (titre, entreprise, n°)")
            .navigationTitle("Devis")
            .navigationDestination(for: UUID.self) { id in
                ChatScreen(conversationId: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Réglages", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(UUID())
                    } label: {
                        Label("Nouveau devis", systemImage: "square.and.pencil")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    path.append(UUID())
                } label: {
                    Label("Nouveau devis", systemImage: "plus.bubble.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: SettingsViewModel(settings: settings, store: SwiftDataConversationStore(context: context)))
            }
            .alert("Bon à savoir", isPresented: $showPrivacyNotice) {
                Button("J'ai compris") { settings.markPrivacyNoticeSeen() }
            } message: {
                Text(AppSettings.privacyNotice)
            }
            .onAppear {
                if !settings.hasSeenPrivacyNotice && !settings.isDemo {
                    showPrivacyNotice = true
                }
            }
        }
    }

    private var summaries: [QuoteSummary] {
        records.map { rec in
            QuoteSummary(
                id: rec.id,
                title: rec.title,
                companyLabel: rec.companyId.isEmpty ? "" : settings.label(for: rec.companyId),
                number: rec.number,
                status: QuoteStatus(rawValue: rec.status) ?? .draft,
                priceTTC: rec.priceTTC,
                missingCount: rec.currentVersion == nil ? 0 : rec.missingCount,
                updatedAt: rec.updatedAt
            )
        }
    }

    private var filtered: [QuoteSummary] {
        listModel.filter(summaries)
    }

    private func delete(at offsets: IndexSet) {
        let items = filtered
        let store = SwiftDataConversationStore(context: context)
        for index in offsets where items.indices.contains(index) {
            store.deleteConversation(items[index].id)
        }
    }
}

struct QuoteRow: View {
    let summary: QuoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(summary.priceTTC == nil ? "Prix à définir" : summary.priceText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summary.priceTTC == nil ? Color.orange : Color.primary)
            }
            HStack(spacing: 6) {
                if !summary.companyLabel.isEmpty {
                    Text(summary.companyLabel)
                }
                Text("n° \(summary.number ?? "—")")
                Text(summary.status.label)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.accent.opacity(0.15)))
                if summary.missingCount > 0 {
                    Label("\(summary.missingCount)", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("\(summary.missingCount) champ(s) à compléter")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Crée le view model d'une conversation avec le stockage SwiftData et les réglages courants.
@MainActor
struct ChatScreen: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var model: ChatViewModel?

    var body: some View {
        Group {
            if let model {
                ChatView(model: model)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            let settings = self.settings
            model = ChatViewModel(
                conversationId: conversationId,
                defaultCompanyId: settings.defaultCompanyId,
                store: SwiftDataConversationStore(context: context),
                apiProvider: { settings.makeAPI() },
                imageProcessor: ImageCompressor(),
                companies: { settings.companies }
            )
        }
    }
}
