import Foundation

/// Écrit les fichiers à partager (PDF, Word) dans un dossier temporaire avec un nom propre.
enum FileExporter {
    static func write(_ data: Data, fileName: String, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = directory.appendingPathComponent("Partage", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Résumé court de la conversation envoyé au serveur (qui ne stocke rien).
enum HistorySummary {
    static func make(from messages: [ChatMessage], maxMessages: Int = 6, maxChars: Int = 3500) -> String? {
        let recent = messages.suffix(maxMessages).compactMap { m -> String? in
            let text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let who = m.role == .user ? "Utilisateur" : "Assistant"
            return "\(who) : \(String(text.prefix(300)))"
        }
        guard !recent.isEmpty else { return nil }
        return String(recent.joined(separator: "\n").suffix(maxChars))
    }
}
