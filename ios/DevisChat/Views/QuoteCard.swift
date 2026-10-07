import SwiftUI
import UIKit

/// Carte « devis » dans la conversation.
@MainActor
struct QuoteCard: View {
    let quote: Quote
    let changes: [String]
    let companyLabel: String
    let isLatest: Bool
    let canUndo: Bool
    let actions: QuoteCardActions

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack {
                Label("\(quote.lots.count) lot\(quote.lots.count > 1 ? "s" : "")", systemImage: "list.bullet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(FR.amountTTC(quote.price.amountTtc))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(quote.price.amountTtc == nil ? Color.orange : Color.primary)
            }
            if quote.isIncomplete {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Incomplet : \(quote.missing.count) champ\(quote.missing.count > 1 ? "s" : "")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange))
                    Text(quote.missing.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if !changes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(changes, id: \.self) { change in
                        Text("• \(change)")
                            .font(.caption)
                    }
                }
            }
            if isLatest {
                LazyVGrid(columns: columns, spacing: 8) {
                    Button { actions.preview() } label: { Label("Aperçu", systemImage: "doc.richtext") }
                    Button { actions.share() } label: { Label("Partager", systemImage: "square.and.arrow.up") }
                    Button { actions.undo() } label: { Label("Annuler", systemImage: "arrow.uturn.backward") }
                        .disabled(!canUndo)
                        .accessibilityLabel("Annuler la dernière modif")
                    Button { actions.edit() } label: { Label("Éditer", systemImage: "pencil") }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(isLatest ? 0.8 : 0.3), lineWidth: isLatest ? 1.5 : 1))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.title.isEmpty ? "Devis sans titre" : quote.title)
                    .font(.headline)
                Text("\(companyLabel) · n° \(quote.number ?? "à attribuer") · version \(quote.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(quote.mode.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(quote.status.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.accent.opacity(0.15)))
                .foregroundStyle(Theme.accent)
        }
    }
}
