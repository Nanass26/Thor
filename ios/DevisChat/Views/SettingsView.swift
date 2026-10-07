import SwiftUI

/// Réglages : serveur, jeton (Trousseau), test de connexion, entreprise par défaut, numérotation.
@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SettingsViewModel

    init(model: SettingsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://mon-mac.local:8000", text: $model.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Jeton (APP_TOKEN du serveur)", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Serveur")
                } footer: {
                    Text("Sur le même Wi-Fi que le Mac : http://<nom-du-mac>.local:8000. Le jeton est rangé dans le Trousseau de l'iPhone.")
                }

                Section {
                    Button {
                        Task { await model.testConnection() }
                    } label: {
                        HStack {
                            Text("Tester la connexion")
                            if model.isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.isTesting)
                    if let status = model.connectionStatus {
                        Label(status, systemImage: model.connectionOK == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.connectionOK == true ? Color.green : Color.orange)
                            .font(.subheadline)
                    }
                }

                Section("Entreprise par défaut") {
                    Picker("Entreprise", selection: $model.defaultCompanyId) {
                        ForEach(model.companies) { company in
                            Text(company.label).tag(company.id)
                        }
                    }
                }

                Section {
                    ForEach(model.companies) { company in
                        Stepper(value: nextNumber(for: company.id), in: 1...999) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(company.label)
                                Text("Prochain numéro : \(model.preview(for: company.id))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let warning = model.duplicateWarning(for: company.id) {
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Numérotation")
                } footer: {
                    Text("Le numéro (NN/AA) est attribué quand tu valides un devis, et à nouveau si tu changes d'entreprise.")
                }

                Section("Données") {
                    Text(AppSettings.privacyNotice)
                        .font(.footnote)
                    Text("Rien n'est envoyé au client par l'app : tu partages toi-même après relecture.")
                        .font(.footnote)
                }

                Section("À propos") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        model.save()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    private func nextNumber(for companyId: String) -> Binding<Int> {
        Binding(
            get: { model.nextNumbers[companyId] ?? 1 },
            set: { model.nextNumbers[companyId] = $0 }
        )
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
