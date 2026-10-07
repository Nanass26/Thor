import PDFKit
import SwiftUI
import UIKit

/// Aperçu du PDF avec partage du PDF ou du Word.
@MainActor
struct PDFPreviewView: View {
    let pdfURL: URL
    let title: String
    let makeDocx: @MainActor () async throws -> URL
    @Environment(\.dismiss) private var dismiss
    @State private var share: ShareItem?
    @State private var errorMessage: String?
    @State private var isLoadingDocx = false

    var body: some View {
        NavigationStack {
            PDFKitView(url: pdfURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ShareLink(item: pdfURL) {
                                Label("PDF", systemImage: "doc.richtext")
                            }
                            Button {
                                shareDocx()
                            } label: {
                                Label("Word (.docx)", systemImage: "doc.text")
                            }
                        } label: {
                            if isLoadingDocx {
                                ProgressView()
                            } else {
                                Label("Partager", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .sheet(item: $share) { item in
                    ShareSheet(items: item.urls)
                }
                .alert("Partage impossible", isPresented: errorShown) {
                    Button("OK") { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func shareDocx() {
        Task {
            isLoadingDocx = true
            defer { isLoadingDocx = false }
            do {
                share = ShareItem(urls: [try await makeDocx()])
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Impossible de préparer le fichier Word."
            }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

/// Feuille de partage iOS (Messages, WhatsApp, Mail, Fichiers…). C'est l'utilisateur qui envoie.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
