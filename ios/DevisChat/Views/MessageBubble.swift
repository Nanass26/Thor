import SwiftUI
import UIKit

struct QuoteCardActions {
    var preview: @MainActor () -> Void
    var share: @MainActor () -> Void
    var undo: @MainActor () -> Void
    var edit: @MainActor () -> Void
}

@MainActor
/// Une bulle du chat, avec les blocs structurés de la réponse (carte devis, fiche, conseils, message client).
struct MessageBubble: View {
    let message: ChatMessage
    let companies: [Company]
    let isLatestQuote: Bool
    let canUndo: Bool
    let imageData: @MainActor (String) -> Data?
    let actions: QuoteCardActions

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBlock
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.imageFileNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(message.imageFileNames, id: \.self) { name in
                            Thumbnail(data: imageData(name))
                        }
                    }
                }
                .frame(maxWidth: 280)
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .padding(10)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 40)
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.text)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
                .textSelection(.enabled)
            if let payload = message.payload {
                if !payload.questions.isEmpty {
                    QuestionsBlock(questions: payload.questions)
                }
                if let quote = payload.quote {
                    QuoteCard(
                        quote: quote,
                        changes: payload.changes,
                        companyLabel: Company.label(for: quote.companyId, in: companies),
                        isLatest: isLatestQuote,
                        canUndo: canUndo,
                        actions: actions
                    )
                }
                if let sheet = payload.clientSheet {
                    ClientSheetBlock(sheet: sheet)
                }
                if let advice = payload.advice {
                    AdviceBlock(advice: advice)
                }
                if let reply = payload.clientReply {
                    ClientReplyBlock(reply: reply)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
    }
}

struct Thumbnail: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Image envoyée")
    }
}

struct QuestionsBlock: View {
    let questions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(questions, id: \.self) { question in
                Label(question, systemImage: "questionmark.bubble")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(Theme.accent)
    }
}

struct ClientSheetBlock: View {
    let sheet: ClientSheet
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(sheet.displayLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label)
                            .font(.caption.weight(.semibold))
                            .frame(width: 100, alignment: .leading)
                        Text(line.value)
                            .font(.caption)
                    }
                }
                ForEach(sheet.snippets, id: \.self) { snippet in
                    Text(snippet)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Fiche lue dans la capture", systemImage: "text.viewfinder")
                .font(.subheadline.weight(.medium))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
    }
}

struct AdviceBlock: View {
    let advice: Advice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Conseils", systemImage: "lightbulb")
                .font(.subheadline.weight(.semibold))
            if let range = advice.priceRange, range.low != nil || range.high != nil {
                Text("Fourchette indicative : \(rangeText(range))")
                    .font(.subheadline)
                if let note = range.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !range.comparableIds.isEmpty {
                    Text("Chantiers comparables : \(range.comparableIds.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let note = advice.priceRange?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(advice.risks, id: \.label) { risk in
                VStack(alignment: .leading, spacing: 1) {
                    Label(risk.label, systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(risk.why)
                        .font(.caption)
                }
            }
            Text(Advice.disclaimer)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.10)))
    }

    private func rangeText(_ range: PriceRange) -> String {
        let low = range.low.map { FR.amount($0) } ?? "?"
        let high = range.high.map { FR.amount($0) } ?? "?"
        return "\(low) – \(high) TTC"
    }
}

struct ClientReplyBlock: View {
    let reply: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Message pour le client", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
            Text(reply)
                .font(.subheadline)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = reply
                copied = true
            } label: {
                Label(copied ? "Copié !" : "Copier le message client", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .sensoryFeedback(.success, trigger: copied)
            Text("À coller toi-même dans AlloVoisins, SMS ou WhatsApp : l'app n'envoie rien.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.4)))
    }
}
