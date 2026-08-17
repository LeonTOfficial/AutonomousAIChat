import Foundation

actor DiagnosticsLogger {
    enum Level: String, Sendable {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
    }

    static let shared = DiagnosticsLogger()

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func logFileURL() throws -> URL {
        let folder = try ConversationStore.supportFolderURL()
            .appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("autonomous-ai-chat.log", isDirectory: false)
    }

    @discardableResult
    func log(
        _ level: Level,
        source: String,
        message: String,
        metadata: [String: String] = [:]
    ) -> String {
        let eventID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        let timestamp = timestampFormatter.string(from: Date())
        let meta = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.sanitize($0.value))" }
            .joined(separator: " ")
        let suffix = meta.isEmpty ? "" : " | \(meta)"
        let line = "\(timestamp) | \(level.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) | \(eventID) | \(source) | \(Self.sanitize(message))\(suffix)\n"

        do {
            let url = try Self.logFileURL()
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            // Logging must never break the chat itself.
        }
        return eventID
    }

    func recentLines(limit: Int = 120) -> String {
        guard let url = try? Self.logFileURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Noch keine Diagnose-Einträge vorhanden."
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(max(1, limit))
            .joined(separator: "\n")
    }

    func clear() {
        guard let url = try? Self.logFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .prefix(900)
            .description
    }
}
