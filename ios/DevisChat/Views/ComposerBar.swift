import PhotosUI
import SwiftUI
import UIKit

/// Zone de saisie : texte multi-lignes (dictée via le micro du clavier), photos, coller, envoyer.
@MainActor
struct ComposerBar: View {
    @Bindable var model: ChatViewModel
    var focused: FocusState<Bool>.Binding
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 6) {
            if !model.pendingImages.isEmpty {
                pendingImagesRow
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, ImageSizing.maxImages - model.pendingImages.count),
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                }
                .accessibilityLabel("Ajouter des captures ou des photos")

                Button {
                    paste()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3)
                }
                .accessibilityLabel("Coller une image du presse-papiers")

                TextField("Écris ou dicte ta demande…", text: $model.draftText, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused)

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Envoyer")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
    }

    private var pendingImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.pendingImages.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        Thumbnail(data: data)
                        Button {
                            model.removePendingImage(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .accessibilityLabel("Retirer l'image \(index + 1)")
                    }
                }
            }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                datas.append(data)
            }
        }
        pickerItems = []
        model.addImages(datas)
    }

    private func paste() {
        let pasteboard = UIPasteboard.general
        if let image = pasteboard.image, let data = image.jpegData(compressionQuality: 0.9) {
            model.addImages([data])
        } else if let text = pasteboard.string, !text.isEmpty {
            model.draftText += text
        } else {
            model.errorMessage = "Le presse-papiers ne contient ni image ni texte."
        }
    }
}
