import Foundation

enum ConversationStore {
    private static let folderName = "AutonomousAIChat"
    private static let sessionsFileName = "sessions-v13.json"
    private static let preV18BackupFileName = "sessions-v13.pre-v18.json"
    private static let lastGoodBackupFileName = "sessions-v13.last-good.json"
    private static let memoryFileName = "long-term-memory.txt"

    static func loadSessions() -> PersistedSessionStore? {
        if let url = try? sessionsFileURL() {
            if let decoded = loadStore(from: url) {
                return decoded
            }

            // Ein abgebrochener Systemstart oder beschädigter Datenträgerzustand darf
            // die App nicht mit einem leeren Chat starten lassen. Die vor v18 angelegte
            // Sicherung ist ein sicherer, unveränderter Fallback.
            let folder = url.deletingLastPathComponent()
            for backupName in [lastGoodBackupFileName, preV18BackupFileName] {
                let backupURL = folder.appendingPathComponent(backupName, isDirectory: false)
                if let decoded = loadStore(from: backupURL) {
                    return decoded
                }
            }
        }

        if let legacy = loadLegacyConversation(), !legacy.messages.isEmpty {
            let session = ChatSession(
                title: titleForLegacyConversation(legacy.messages),
                createdAt: legacy.messages.first?.date ?? Date(),
                updatedAt: legacy.messages.last?.date ?? Date(),
                messages: legacy.messages,
                memory: legacy.memory
            )
            let store = PersistedSessionStore(selectedSessionID: session.id, sessions: [session])
            saveSessions(store)
            return store
        }

        return nil
    }

    private static func loadStore(from url: URL) -> PersistedSessionStore? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= 32 * 1024 * 1024,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let decoded = try? JSONDecoder().decode(PersistedSessionStore.self, from: data),
              !decoded.sessions.isEmpty else {
            return nil
        }
        return decoded
    }

    static func saveSessions(_ store: PersistedSessionStore) {
        guard let url = try? sessionsFileURL() else { return }
        createPreV18BackupIfNeeded(currentURL: url)
        createLastGoodBackupIfPossible(currentURL: url)

        let normalizedSessions = store.sessions.map { session -> ChatSession in
            var copy = session
            let trimmed = Array(session.messages.suffix(1200))
            let dropped = max(0, session.messages.count - trimmed.count)
            copy.messages = trimmed
            copy.memory.coveredMessageCount = max(0, session.memory.coveredMessageCount - dropped)
            return copy
        }

        let normalized = PersistedSessionStore(
            selectedSessionID: store.selectedSessionID,
            sessions: normalizedSessions
        )

        if let data = try? JSONEncoder().encode(normalized) {
            try? data.write(to: url, options: [.atomic])
        }

        if let selected = normalizedSessions.first(where: { $0.id == normalized.selectedSessionID }) {
            writeMemoryExport(session: selected)
        }
    }

    static func memoryFileURL() throws -> URL {
        try supportFolderURL().appendingPathComponent(memoryFileName, isDirectory: false)
    }

    static func supportFolderURL() throws -> URL {
        let manager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["AUTONOMOUS_AI_CHAT_QA_DATA_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let folder = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let base = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func sessionsFileURL() throws -> URL {
        try supportFolderURL().appendingPathComponent(sessionsFileName, isDirectory: false)
    }

    private static func loadLegacyConversation() -> PersistedConversation? {
        let names = [
            "conversation-v9.json",
            "conversation-v5.json",
            "conversation-v4.json"
        ]

        for name in names {
            guard let url = try? supportFolderURL().appendingPathComponent(name, isDirectory: false),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(PersistedConversation.self, from: data) else {
                continue
            }
            return decoded
        }
        return nil
    }

    private static func createPreV18BackupIfNeeded(currentURL: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: currentURL.path),
              let folder = try? supportFolderURL() else { return }
        let backupURL = folder.appendingPathComponent(preV18BackupFileName, isDirectory: false)
        guard !manager.fileExists(atPath: backupURL.path) else { return }
        try? manager.copyItem(at: currentURL, to: backupURL)
    }

    private static func createLastGoodBackupIfPossible(currentURL: URL) {
        guard loadStore(from: currentURL) != nil,
              let data = try? Data(contentsOf: currentURL, options: [.mappedIfSafe]),
              let folder = try? supportFolderURL() else {
            return
        }
        let backupURL = folder.appendingPathComponent(lastGoodBackupFileName, isDirectory: false)
        try? data.write(to: backupURL, options: [.atomic])
    }

    private static func titleForLegacyConversation(_ messages: [ChatMessage]) -> String {
        if let firstUser = messages.first(where: { $0.speaker == .user }) {
            let text = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return String(text.prefix(42))
            }
        }
        return "Bisheriger Chat"
    }

    private static func writeMemoryExport(session: ChatSession) {
        guard let url = try? memoryFileURL() else { return }

        let updated: String
        if session.memory.updatedAt == .distantPast {
            updated = "Noch nicht erstellt"
        } else {
            updated = ISO8601DateFormatter().string(from: session.memory.updatedAt)
        }

        let summary = session.memory.summary.isEmpty
            ? "Noch keine Langzeit-Erinnerung vorhanden. Sie wird nach mehreren Nachrichten automatisch aufgebaut."
            : session.memory.summary

        let text = """
        AUTONOMER KI-GRUPPENCHAT – LANGZEITGEDÄCHTNIS

        Sitzung: \(session.title)
        Aktualisiert: \(updated)
        Berücksichtigte Nachrichten: \(session.memory.coveredMessageCount)
        Lokal gespeicherte Nachrichten: \(session.messages.count)

        --- ERINNERUNG ---
        \(summary)

        --- HINWEIS ---
        Diese Datei zeigt das Langzeitgedächtnis der aktuell ausgewählten Chat-Sitzung.
        Alle Sitzungen liegen lokal in sessions-v13.json.
        """

        if let data = text.data(using: .utf8) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}

actor ConversationPersistenceWorker {
    static let shared = ConversationPersistenceWorker()

    private var latestRevision = 0

    func save(_ store: PersistedSessionStore, revision: Int) {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        ConversationStore.saveSessions(store)
    }
}
