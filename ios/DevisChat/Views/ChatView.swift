import SwiftUI
import UIKit

/// Fichier(s) à afficher ou partager.
struct PreviewItem: Identifiable {
    let id = UUID()
    let pdf: URL
}

struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Conversation d'un devis : bulles, carte devis, raccourcis, composeur.
@MainActor
struct ChatView: View {
    @Bindable var model: ChatViewModel
    @Environment(AppSettings.self) private var settings
    @State private var preview: PreviewItem?
    @State private var share: ShareItem?
    @State private var showEditor = false
    @State private var showCompanyPicker = false
    @State private var confirmIncompleteValidation = false
    @State private var isExporting = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            if let error = model.errorMessage {
                ErrorBanner(message: error, canRetry: model.canRetry) {
                    Task { await model.retry() }
                } dismiss: {
                    model.errorMessage = nil
                }
            }
            ShortcutBar(enabled: model.currentQuote != nil && !model.isSending, onTap: { shortcut in handleShortcut(shortcut) })
            ComposerBar(model: model, focused: $composerFocused)
        }
        .navigationTitle(model.currentQuote?.title ?? "Nouveau devis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sensoryFeedback(.success, trigger: model.receivedQuoteCount)
        .sheet(item: $preview) { item in
            PDFPreviewView(pdfURL: item.pdf, title: model.currentQuote?.title ?? "Devis") {
                try await model.exportDOCX()
            }
        }
        .sheet(item: $share) { item in
            ShareSheet(items: item.urls)
        }
        .sheet(isPresented: $showEditor) {
            if let quote = model.currentQuote {
                QuoteEditorSheet(
                    quote: quote,
                    companies: settings.companies,
                    hasCoverPhoto: model.coverPhotoFileName != nil,
                    onSave: { edited in model.applyManualEdit(edited) },
                    onCoverPhoto: { data in model.setCoverPhoto(data) }
                )
            }
        }
        .confirmationDialog("Changer d'entreprise", isPresented: $showCompanyPicker, titleVisibility: .visible) {
            ForEach(settings.companies.filter { $0.id != model.companyId }) { company in
                Button(company.label) {
                    Task { await model.send(shortcut: "Passe sur \(company.label)") }
                }
            }
        }
        .confirmationDialog("Valider un devis incomplet ?", isPresented: $confirmIncompleteValidation, titleVisibility: .visible) {
            Button("Valider quand même") { model.validate() }
        } message: {
            Text("Il manque : \(model.currentQuote?.missing.joined(separator: ", ") ?? "").")
        }
        .alert("Attention", isPresented: noticeShown) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .overlay {
            if isExporting {
                ProgressView("Préparation du document…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        EmptyChatHint()
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(
                            message: message,
                            companies: settings.companies,
                            isLatestQuote: message.payload?.quote.map { model.isLatest($0) } ?? false,
                            canUndo: model.canUndo,
                            imageData: { name in model.imageData(named: name) },
                            actions: cardActions
                        )
                        .id(message.id)
                    }
                    if model.isSending {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.isSending) { _, _ in
                scrollToBottom(proxy)
            }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if model.isSending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = model.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var cardActions: QuoteCardActions {
        QuoteCardActions(
            preview: { openPreview() },
            share: { openShare() },
            undo: { model.undo() },
            edit: { showEditor = true }
        )
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    }

    // MARK: Actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { openPreview() } label: { Label("Aperçu PDF", systemImage: "doc.richtext") }
                Button { openShare() } label: { Label("Partager (PDF + Word)", systemImage: "square.and.arrow.up") }
                Button { showEditor = true } label: { Label("Éditer à la main", systemImage: "pencil") }
                if model.currentQuote?.status == .draft {
                    Button { requestValidation() } label: { Label("Valider le devis", systemImage: "checkmark.seal") }
                }
                if model.currentQuote?.status == .validated {
                    Button { markSent() } label: { Label("Marquer comme envoyé", systemImage: "paperplane") }
                }
                if model.canUndo {
                    Button { model.undo() } label: { Label("Annuler la dernière modif", systemImage: "arrow.uturn.backward") }
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .disabled(model.currentQuote == nil)
        }
    }

    private func handleShortcut(_ shortcut: ChatShortcut) {
        if let message = shortcut.message {
            Task { await model.send(shortcut: message) }
        } else if shortcut == .changeCompany {
            showCompanyPicker = true
        } else if let prefill = shortcut.prefill {
            model.draftText = prefill
            composerFocused = true
        }
    }

    private func requestValidation() {
        if model.currentQuote?.isIncomplete == true {
            confirmIncompleteValidation = true
        } else {
            model.validate()
        }
    }

    private func markSent() {
        guard var quote = model.currentQuote else { return }
        quote.status = .sent
        model.applyManualEdit(quote)
    }

    private func openPreview() {
        Task {
            isExporting = true
            defer { isExporting = false }
            do {
                preview = PreviewItem(pdf: try await model.exportPDF())
            } catch {
                model.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Aperçu impossible."
            }
        }
    }

    private func openShare() {
        Task {
            isExporting = true
            defer { isExporting = false }
            do {
                let pdf = try await model.exportPDF()
                let docx = try await model.exportDOCX()
                share = ShareItem(urls: [pdf, docx])
            } catch {
                model.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Partage impossible."
            }
        }
    }
}

// MARK: - Petits éléments

@MainActor
struct ShortcutBar: View {
    let enabled: Bool
    let onTap: @MainActor (ChatShortcut) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatShortcut.allCases) { shortcut in
                    Button(shortcut.title) { onTap(shortcut) }
                        .font(.subheadline)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

@MainActor
struct ErrorBanner: View {
    let message: String
    let canRetry: Bool
    let retry: @MainActor () -> Void
    let dismiss: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canRetry {
                Button("Réessayer") { retry() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Fermer le message d'erreur")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }
}

struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("En train d'écrire…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyChatHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Comment ça marche", systemImage: "lightbulb")
                .font(.headline)
                .foregroundStyle(Theme.accent)
            Text("Envoie une capture de l'annonce AlloVoisins, une photo du chantier ou décris les travaux (tu peux dicter avec le micro du clavier).")
            Text("Exemple : « Peinture salon 25 m² + couloir, appart à Courbevoie, 2 semaines, 2 800 TTC. »")
                .italic()
                .foregroundStyle(.secondary)
            Text("Rien n'est envoyé au client : tu relis l'aperçu, puis tu partages toi-même.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(0.08)))
    }
}
