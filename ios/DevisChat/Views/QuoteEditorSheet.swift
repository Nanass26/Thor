import PhotosUI
import SwiftUI

/// Éditeur manuel : parfois le plus rapide est de taper le prix soi-même.
@MainActor
struct QuoteEditorSheet: View {
    let companies: [Company]
    let hasCoverPhoto: Bool
    let onSave: @MainActor (Quote) -> Void
    let onCoverPhoto: @MainActor (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Quote
    @State private var priceText: String
    @State private var coverItem: PhotosPickerItem?
    @State private var coverChosen = false

    init(quote: Quote, companies: [Company], hasCoverPhoto: Bool, onSave: @escaping @MainActor (Quote) -> Void, onCoverPhoto: @escaping @MainActor (Data) -> Void) {
        self.companies = companies
        self.hasCoverPhoto = hasCoverPhoto
        self.onSave = onSave
        self.onCoverPhoto = onCoverPhoto
        _draft = State(initialValue: quote)
        _priceText = State(initialValue: quote.price.amountTtc.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Devis") {
                    TextField("Titre", text: $draft.title, axis: .vertical)
                }
                Section("Client") {
                    TextField("Nom du client", text: text(\.client.name))
                        .textContentType(.name)
                    TextField("E-mail", text: text(\.client.email))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Téléphone", text: text(\.client.phone))
                        .keyboardType(.phonePad)
                }
                Section("Chantier") {
                    TextField("Adresse exacte du chantier", text: text(\.siteAddress), axis: .vertical)
                }
                Section {
                    TextField("Prix TTC en euros (ex. 3500)", text: $priceText)
                        .keyboardType(.numberPad)
                    Picker("TVA", selection: $draft.price.vatRate) {
                        Text("À définir").tag(Double?.none)
                        Text("5,5 %").tag(Double?.some(5.5))
                        Text("10 %").tag(Double?.some(10))
                        Text("20 %").tag(Double?.some(20))
                    }
                    Picker("Mode", selection: $draft.mode) {
                        ForEach(QuoteMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } header: {
                    Text("Prix")
                } footer: {
                    Text("C'est toi qui décides du prix. Laisse vide pour « Prix à définir ».")
                }
                Section("Délais") {
                    TextField("Durée des travaux (ex. 3 semaines)", text: text(\.duration))
                    TextField("Délai de démarrage", text: text(\.startDelay), axis: .vertical)
                    Stepper("Validité : \(draft.validityDays) jours", value: $draft.validityDays, in: 1...365)
                }
                Section("Entreprise") {
                    Picker("Entreprise", selection: $draft.companyId) {
                        ForEach(companies) { company in
                            Text(company.label).tag(company.id)
                        }
                    }
                }
                Section("Options du document") {
                    Toggle("Tableau de prix (HT / TVA / TTC)", isOn: $draft.options.showPriceTable)
                    Toggle("Bloc signatures", isOn: $draft.options.showSignatures)
                    Toggle("Page de garde avec photo", isOn: $draft.options.coverPhoto)
                    if draft.options.coverPhoto {
                        PhotosPicker(selection: $coverItem, matching: .images) {
                            Label(hasCoverPhoto || coverChosen ? "Changer la photo de garde" : "Choisir la photo de garde", systemImage: "photo")
                        }
                    }
                }
                Section("Remarque (nota)") {
                    TextField("Optionnel", text: text(\.nota), axis: .vertical)
                }
            }
            .navigationTitle("Modifier le devis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .bold()
                }
            }
            .onChange(of: coverItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        onCoverPhoto(data)
                        coverChosen = true
                    }
                }
            }
        }
    }

    /// Liaison texte pour un champ optionnel (vide = absent).
    private func text(_ keyPath: WritableKeyPath<Quote, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func save() {
        var quote = draft
        let digits = priceText.filter { $0.isNumber }
        quote.price.amountTtc = digits.isEmpty ? nil : Int(digits)
        onSave(quote)
        dismiss()
    }
}
