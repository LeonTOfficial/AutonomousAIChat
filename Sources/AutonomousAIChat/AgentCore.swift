import AppKit
import CryptoKit
import Foundation

enum MainWorkspaceMode: String, CaseIterable, Identifiable {
    case chat
    case agent
    case group

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chat: return "Chat"
        case .agent: return "Agent"
        case .group: return "Gruppe"
        }
    }
}

enum AgentSandbox {
    static func directoryURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appFolder = bundleIdentifier ?? "Autonomer-KI-Gruppenchat"
        return applicationSupport
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("Agent-Sandkasten", isDirectory: true)
    }

    @discardableResult
    static func create() throws -> URL {
        let url = try directoryURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }
}

enum AgentPlanStatus: Sendable, Equatable {
    case waiting
    case active
    case completed
}

struct AgentPlanStep: Identifiable, Sendable {
    let id: UUID
    let title: String
    var status: AgentPlanStatus

    init(id: UUID = UUID(), title: String, status: AgentPlanStatus = .waiting) {
        self.id = id
        self.title = title
        self.status = status
    }
}

enum AgentActivityKind: Sendable {
    case info
    case working
    case success
    case warning
    case failure
}

struct AgentActivity: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let kind: AgentActivityKind
    let title: String
    let detail: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: AgentActivityKind,
        title: String,
        detail: String = ""
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

enum AgentConversationRole: Sendable {
    case user
    case agent
}

struct AgentConversationEntry: Identifiable, Sendable {
    let id: UUID
    let role: AgentConversationRole
    let text: String
    let providerLabel: String?

    init(id: UUID = UUID(), role: AgentConversationRole, text: String, providerLabel: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.providerLabel = providerLabel
    }
}

struct AgentModelSelection: Sendable, Equatable {
    let provider: AIProvider
    let geminiModel: String
    let ollamaModel: String

    var selectedModel: String { provider == .gemini ? geminiModel : ollamaModel }

    var displayLabel: String {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? provider.displayName : "\(provider.displayName) · \(model)"
    }
}

enum AgentPendingActionKind: Sendable, Equatable {
    case writeFile
    case revealInFinder
}

struct AgentPendingAction: Identifiable, Sendable {
    let id: UUID
    let kind: AgentPendingActionKind
    let relativePath: String
    let targetURL: URL
    let previousContent: String?
    let proposedContent: String?
    let originalHash: String?
    let reason: String
    let revealAfterWrite: Bool

    init(
        id: UUID = UUID(),
        kind: AgentPendingActionKind,
        relativePath: String,
        targetURL: URL,
        previousContent: String? = nil,
        proposedContent: String? = nil,
        originalHash: String? = nil,
        reason: String,
        revealAfterWrite: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.targetURL = targetURL
        self.previousContent = previousContent
        self.proposedContent = proposedContent
        self.originalHash = originalHash
        self.reason = reason
        self.revealAfterWrite = revealAfterWrite
    }
}

enum AgentFileSystemError: LocalizedError, Equatable {
    case noWorkspace
    case invalidPath
    case pathOutsideWorkspace
    case hiddenOrSensitivePath
    case unsupportedFile
    case fileTooLarge
    case unreadableText
    case conflict
    case notFound

    var errorDescription: String? {
        switch self {
        case .noWorkspace:
            return "Wähle zuerst einen Arbeitsordner."
        case .invalidPath:
            return "Der Agent hat einen ungültigen relativen Pfad vorgeschlagen."
        case .pathOutsideWorkspace:
            return "Der Pfad liegt außerhalb des gewählten Arbeitsordners oder führt über einen Symlink hinaus."
        case .hiddenOrSensitivePath:
            return "Versteckte oder möglicherweise sensible Pfade sind für den Agenten gesperrt."
        case .unsupportedFile:
            return "Der Agent darf in dieser Version nur normale Textdateien bearbeiten."
        case .fileTooLarge:
            return "Die Datei oder der vorgeschlagene Inhalt ist für eine sichere Vorschau zu groß."
        case .unreadableText:
            return "Die Datei ist keine lesbare UTF-8-Textdatei."
        case .conflict:
            return "Die Datei wurde seit der Vorschau verändert. Die Aktion wurde zum Schutz deiner Änderungen gestoppt."
        case .notFound:
            return "Die angeforderte Datei wurde im Arbeitsordner nicht gefunden."
        }
    }
}

actor AgentWorkspaceFileSystem {
    static let maximumTextBytes = 256 * 1024
    static let maximumDirectoryEntries = 200

    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    nonisolated static func validatedRelativePath(_ rawPath: String) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0") else {
            throw AgentFileSystemError.invalidPath
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AgentFileSystemError.invalidPath
        }

        let blockedNames: Set<String> = [
            ".ssh", ".gnupg", ".aws", ".env", ".git-credentials", ".netrc",
            "id_rsa", "id_ed25519", "keychain", "cookies"
        ]
        for component in components {
            let lower = component.lowercased()
            if component.hasPrefix(".") || blockedNames.contains(lower) {
                throw AgentFileSystemError.hiddenOrSensitivePath
            }
        }

        return components.joined(separator: "/")
    }

    func listDirectory(relativePath: String) throws -> String {
        let relative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = relative.isEmpty || relative == "."
            ? try canonicalRoot()
            : try resolvedExistingURL(relativePath: relative)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AgentFileSystemError.notFound
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let entries = try FileManager.default.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .prefix(Self.maximumDirectoryEntries)

        return try entries.map { url in
            let values = try url.resourceValues(forKeys: Set(keys))
            let suffix: String
            if values.isSymbolicLink == true {
                suffix = " [Symlink – nicht verfolgt]"
            } else if values.isDirectory == true {
                suffix = "/"
            } else {
                suffix = values.fileSize.map { " (\($0) Bytes)" } ?? ""
            }
            return url.lastPathComponent + suffix
        }.joined(separator: "\n")
    }

    func readFile(relativePath: String) throws -> String {
        let target = try resolvedExistingURL(relativePath: relativePath)
        let values = try target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw AgentFileSystemError.unsupportedFile }
        guard (values.fileSize ?? 0) <= Self.maximumTextBytes else { throw AgentFileSystemError.fileTooLarge }

        let data = try Data(contentsOf: target, options: [.mappedIfSafe])
        guard data.count <= Self.maximumTextBytes else { throw AgentFileSystemError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw AgentFileSystemError.unreadableText }
        return text
    }

    func prepareWrite(
        relativePath: String,
        content: String,
        reason: String,
        revealAfterWrite: Bool
    ) throws -> AgentPendingAction {
        let relative = try Self.validatedRelativePath(relativePath)
        guard let data = content.data(using: .utf8), data.count <= Self.maximumTextBytes else {
            throw AgentFileSystemError.fileTooLarge
        }

        let target = try resolvedURLForPotentialNewFile(relativePath: relative)
        let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        if values?.isDirectory == true { throw AgentFileSystemError.unsupportedFile }
        if let size = values?.fileSize, size > Self.maximumTextBytes { throw AgentFileSystemError.fileTooLarge }

        let targetExists = FileManager.default.fileExists(atPath: target.path)
        let previousData: Data?
        if targetExists {
            do {
                previousData = try Data(contentsOf: target, options: [.mappedIfSafe])
            } catch {
                throw AgentFileSystemError.unreadableText
            }
        } else {
            previousData = nil
        }
        let previousContent: String?
        if let previousData {
            guard previousData.count <= Self.maximumTextBytes else { throw AgentFileSystemError.fileTooLarge }
            guard let decoded = String(data: previousData, encoding: .utf8) else {
                throw AgentFileSystemError.unreadableText
            }
            previousContent = decoded
        } else {
            previousContent = nil
        }

        return AgentPendingAction(
            kind: .writeFile,
            relativePath: relative,
            targetURL: target,
            previousContent: previousContent,
            proposedContent: content,
            originalHash: previousData.map(Self.sha256),
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            revealAfterWrite: revealAfterWrite
        )
    }

    func prepareReveal(relativePath: String, reason: String) throws -> AgentPendingAction {
        let relative = try Self.validatedRelativePath(relativePath)
        let target = try resolvedExistingURL(relativePath: relative)
        return AgentPendingAction(
            kind: .revealInFinder,
            relativePath: relative,
            targetURL: target,
            reason: reason
        )
    }

    func commit(_ action: AgentPendingAction) throws -> URL {
        switch action.kind {
        case .revealInFinder:
            _ = try resolvedExistingURL(relativePath: action.relativePath)
            return action.targetURL

        case .writeFile:
            let target = try resolvedURLForPotentialNewFile(relativePath: action.relativePath)
            let targetExists = FileManager.default.fileExists(atPath: target.path)
            let currentData: Data?
            if targetExists {
                do {
                    currentData = try Data(contentsOf: target, options: [.mappedIfSafe])
                } catch {
                    throw AgentFileSystemError.conflict
                }
            } else {
                currentData = nil
            }
            let currentHash = currentData.map(Self.sha256)
            guard currentHash == action.originalHash else { throw AgentFileSystemError.conflict }
            guard let proposedContent = action.proposedContent,
                  let data = proposedContent.data(using: .utf8),
                  data.count <= Self.maximumTextBytes else {
                throw AgentFileSystemError.fileTooLarge
            }

            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: target, options: [.atomic])
            return target
        }
    }

    private func canonicalRoot() throws -> URL {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AgentFileSystemError.noWorkspace
        }
        return canonical
    }

    private func resolvedExistingURL(relativePath: String) throws -> URL {
        let relative = try Self.validatedRelativePath(relativePath)
        let root = try canonicalRoot()
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        guard FileManager.default.fileExists(atPath: candidate.path) else { throw AgentFileSystemError.notFound }
        let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard Self.contains(canonical, inside: root) else { throw AgentFileSystemError.pathOutsideWorkspace }
        return canonical
    }

    private func resolvedURLForPotentialNewFile(relativePath: String) throws -> URL {
        let relative = try Self.validatedRelativePath(relativePath)
        let root = try canonicalRoot()
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        guard Self.contains(candidate, inside: root) else { throw AgentFileSystemError.pathOutsideWorkspace }

        if FileManager.default.fileExists(atPath: candidate.path) {
            let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard Self.contains(canonical, inside: root) else { throw AgentFileSystemError.pathOutsideWorkspace }
            return canonical
        }

        var ancestor = candidate.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != root.path {
            ancestor.deleteLastPathComponent()
        }
        let canonicalAncestor = ancestor.resolvingSymlinksInPath().standardizedFileURL
        guard Self.contains(canonicalAncestor, inside: root) else { throw AgentFileSystemError.pathOutsideWorkspace }
        return candidate
    }

    nonisolated private static func contains(_ candidate: URL, inside root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum AgentWorkspaceBookmarkStore {
    private static let bookmarkKey = "agentWorkspaceBookmarkV19"

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale { try? save(url) }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}

enum AgentModelError: LocalizedError {
    case noLocalModel
    case missingGeminiKey
    case invalidResponse
    case server(status: Int, message: String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noLocalModel:
            return "Kein lokales Ollama-Modell gefunden. Installiere zum Beispiel qwen3.5:9b."
        case .missingGeminiKey:
            return "Für den Gemini-Agenten fehlt ein API-Key. Hinterlege ihn unter Einstellungen → KI."
        case .invalidResponse:
            return "Ollama hat eine unvollständige Agenten-Antwort geliefert."
        case let .server(status, message):
            return "Ollama-Fehler \(status): \(message)"
        case .timedOut:
            return "Das gewählte Modell hat innerhalb des Zeitlimits nicht geantwortet. Du kannst die Aufgabe erneut versuchen oder in den Einstellungen den Anbieter wechseln."
        }
    }
}

enum AgentJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AgentJSONValue])
    case array([AgentJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: AgentJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([AgentJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiger JSON-Wert") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}

struct AgentToolCall: Codable, Sendable, Equatable {
    struct Function: Codable, Sendable, Equatable {
        let name: String
        let arguments: [String: AgentJSONValue]
    }

    let id: String?
    let function: Function
}

struct AgentModelMessage: Codable, Sendable, Equatable {
    let role: String
    let content: String
    let toolCalls: [AgentToolCall]?
    let toolName: String?

    init(role: String, content: String, toolCalls: [AgentToolCall]? = nil, toolName: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolName = toolName
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }
}

actor AgentOllamaClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 115
        configuration.timeoutIntervalForResource = 130
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration)
    }

    func complete(messages: [AgentModelMessage], preferredModel: String) async throws -> (String, AgentModelMessage) {
        let model = try await resolveModel(preferred: preferredModel)
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            throw AgentModelError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(AgentChatRequest(
            model: model,
            messages: messages,
            tools: Self.tools,
            stream: false,
            think: false,
            options: .init(temperature: 0.1, numCtx: 16_384, numPredict: 1_200)
        ))

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AgentModelError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? JSONDecoder().decode(AgentServerError.self, from: data).error) ?? "Unbekannte Antwort"
                throw AgentModelError.server(status: http.statusCode, message: detail)
            }
            let decoded = try JSONDecoder().decode(AgentChatResponse.self, from: data)
            return (model, decoded.message)
        } catch let error as AgentModelError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw AgentModelError.timedOut
        }
    }

    private func resolveModel(preferred: String) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            throw AgentModelError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(AgentTagsResponse.self, from: data),
              !decoded.models.isEmpty else {
            throw AgentModelError.noLocalModel
        }

        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = decoded.models.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact.name
        }
        if let recommended = decoded.models.first(where: { $0.name.lowercased() == "qwen3.5:9b" }) {
            return recommended.name
        }
        return decoded.models[0].name
    }

    private static let tools: [AgentToolDefinition] = [
        .function(
            name: "list_directory",
            description: "Listet einen Ordner innerhalb des gewählten Arbeitsbereichs. Verwende einen relativen Pfad oder einen leeren String für den Hauptordner.",
            properties: ["path": .string(description: "Relativer Ordnerpfad")],
            required: ["path"]
        ),
        .function(
            name: "read_file",
            description: "Liest eine UTF-8-Textdatei innerhalb des gewählten Arbeitsbereichs.",
            properties: ["path": .string(description: "Relativer Dateipfad")],
            required: ["path"]
        ),
        .function(
            name: "propose_write_file",
            description: "Bereitet das Erstellen oder vollständige Ersetzen einer Textdatei vor. Die App schreibt erst nach sichtbarer Freigabe durch den Nutzer.",
            properties: [
                "path": .string(description: "Relativer Dateipfad inklusive Dateiname"),
                "content": .string(description: "Vollständiger UTF-8-Dateiinhalt"),
                "reason": .string(description: "Kurze verständliche Begründung"),
                "reveal_in_finder": .boolean(description: "Datei nach Freigabe im Finder zeigen")
            ],
            required: ["path", "content", "reason", "reveal_in_finder"]
        ),
        .function(
            name: "reveal_in_finder",
            description: "Bereitet vor, eine vorhandene Datei oder einen Ordner im Finder zu zeigen. Auch dies wird vorher sichtbar freigegeben.",
            properties: [
                "path": .string(description: "Relativer Pfad"),
                "reason": .string(description: "Kurze verständliche Begründung")
            ],
            required: ["path", "reason"]
        )
    ]
}

private struct AgentChatRequest: Encodable {
    let model: String
    let messages: [AgentModelMessage]
    let tools: [AgentToolDefinition]
    let stream: Bool
    let think: Bool
    let options: AgentOptions
}

actor AgentGeminiClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 70
        configuration.timeoutIntervalForResource = 85
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration)
    }

    func complete(messages: [AgentModelMessage], preferredModel: String) async throws -> (String, AgentModelMessage) {
        guard let apiKey = KeychainStore.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw AgentModelError.missingGeminiKey
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions") else {
            throw AgentModelError.invalidResponse
        }
        let model = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AIService.recommendedGeminiModel
            : preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemInstruction = messages.first(where: { $0.role == "system" })?.content ?? ""
        let transcript = messages.filter { $0.role != "system" }.map { message -> String in
            switch message.role {
            case "user": return "NUTZER:\n\(message.content)"
            case "tool": return "WERKZEUGERGEBNIS \(message.toolName ?? "unbekannt"):\n\(message.content)"
            default: return message.content.isEmpty ? "AGENT: Werkzeug wurde angefordert." : "AGENT:\n\(message.content)"
            }
        }.joined(separator: "\n\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(AgentGeminiRequest(
            model: model,
            input: transcript,
            systemInstruction: systemInstruction,
            stream: false,
            store: false,
            tools: AgentGeminiToolDefinition.all,
            generationConfig: .init(maxOutputTokens: 1_200, thinkingLevel: "low", thinkingSummaries: "none")
        ))
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AgentModelError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw AgentModelError.server(status: http.statusCode, message: "Gemini: \(Self.errorText(data))")
            }
            let decoded = try JSONDecoder().decode(AgentGeminiResponse.self, from: data)
            let content = decoded.steps.filter { $0.type == "model_output" }
                .flatMap { $0.content ?? [] }
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined(separator: "\n")
            let calls = decoded.steps.compactMap { step -> AgentToolCall? in
                guard step.type == "function_call", let name = step.name else { return nil }
                return AgentToolCall(id: step.id, function: .init(name: name, arguments: step.arguments ?? [:]))
            }
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else {
                throw AgentModelError.invalidResponse
            }
            return (model, AgentModelMessage(role: "assistant", content: content, toolCalls: calls))
        } catch let error as AgentModelError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw AgentModelError.timedOut
        }
    }

    private static func errorText(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return String(message.prefix(420))
        }
        return String(String(data: data, encoding: .utf8)?.prefix(420) ?? "Unbekannte Antwort")
    }
}

private struct AgentOptions: Encodable {
    let temperature: Double
    let numCtx: Int
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numCtx = "num_ctx"
        case numPredict = "num_predict"
    }
}

private struct AgentChatResponse: Decodable {
    let message: AgentModelMessage
}

private struct AgentTagsResponse: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

private struct AgentServerError: Decodable {
    let error: String
}

private struct AgentToolDefinition: Encodable {
    struct Function: Encodable {
        let name: String
        let description: String
        let parameters: AgentJSONSchema
    }

    let type: String
    let function: Function

    static func function(
        name: String,
        description: String,
        properties: [String: AgentJSONSchema],
        required: [String]
    ) -> AgentToolDefinition {
        AgentToolDefinition(
            type: "function",
            function: Function(
                name: name,
                description: description,
                parameters: .object(properties: properties, required: required)
            )
        )
    }
}

private indirect enum AgentJSONSchema: Encodable {
    case object(properties: [String: AgentJSONSchema], required: [String])
    case string(description: String)
    case boolean(description: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .object(properties, required):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
        case let .string(description):
            try container.encode("string", forKey: .type)
            try container.encode(description, forKey: .description)
        case let .boolean(description):
            try container.encode("boolean", forKey: .type)
            try container.encode(description, forKey: .description)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, properties, required, description
    }
}

private struct AgentGeminiRequest: Encodable {
    let model: String
    let input: String
    let systemInstruction: String
    let stream: Bool
    let store: Bool
    let tools: [AgentGeminiToolDefinition]
    let generationConfig: AgentGeminiGenerationConfig

    enum CodingKeys: String, CodingKey {
        case model, input, stream, store, tools
        case systemInstruction = "system_instruction"
        case generationConfig = "generation_config"
    }
}

private struct AgentGeminiGenerationConfig: Encodable {
    let maxOutputTokens: Int
    let thinkingLevel: String
    let thinkingSummaries: String
    enum CodingKeys: String, CodingKey {
        case maxOutputTokens = "max_output_tokens"
        case thinkingLevel = "thinking_level"
        case thinkingSummaries = "thinking_summaries"
    }
}

private struct AgentGeminiToolDefinition: Encodable {
    let type = "function"
    let name: String
    let description: String
    let parameters: AgentJSONSchema

    static let all: [AgentGeminiToolDefinition] = [
        .init(name: "list_directory", description: "Listet einen Ordner innerhalb des Arbeitsbereichs.", parameters: .object(properties: ["path": .string(description: "Relativer Ordnerpfad oder leer für den Hauptordner")], required: ["path"])),
        .init(name: "read_file", description: "Liest eine UTF-8-Textdatei innerhalb des Arbeitsbereichs.", parameters: .object(properties: ["path": .string(description: "Relativer Dateipfad")], required: ["path"])),
        .init(name: "propose_write_file", description: "Bereitet eine Textdatei vor. Die App schreibt erst nach sichtbarer Freigabe.", parameters: .object(properties: ["path": .string(description: "Relativer Dateipfad inklusive Dateiname"), "content": .string(description: "Vollständiger UTF-8-Dateiinhalt"), "reason": .string(description: "Kurze Begründung"), "reveal_in_finder": .boolean(description: "Datei danach im Finder zeigen")], required: ["path", "content", "reason", "reveal_in_finder"])),
        .init(name: "reveal_in_finder", description: "Bereitet vor, eine vorhandene Datei oder einen Ordner im Finder zu zeigen.", parameters: .object(properties: ["path": .string(description: "Relativer Pfad"), "reason": .string(description: "Kurze Begründung")], required: ["path", "reason"]))
    ]
}

private struct AgentGeminiResponse: Decodable { let steps: [AgentGeminiStep] }
private struct AgentGeminiStep: Decodable {
    let id: String?
    let type: String
    let name: String?
    let arguments: [String: AgentJSONValue]?
    let content: [AgentGeminiContent]?
}
private struct AgentGeminiContent: Decodable { let type: String; let text: String? }

@MainActor
final class AgentViewModel: ObservableObject {
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var isUsingSandbox = false
    @Published private(set) var activities: [AgentActivity] = []
    @Published private(set) var plan: [AgentPlanStep] = []
    @Published private(set) var pendingAction: AgentPendingAction?
    @Published private(set) var isRunning = false
    @Published private(set) var lastWrittenURL: URL?
    @Published private(set) var conversation: [AgentConversationEntry] = []
    @Published private(set) var currentStatus = "Bereit"
    @Published var lastError: String?

    private let ollamaClient = AgentOllamaClient()
    private let geminiClient = AgentGeminiClient()
    private var fileSystem: AgentWorkspaceFileSystem?
    private var runTask: Task<Void, Never>?
    private var workspaceHasSecurityScope = false
    private var lastPrompt: String?
    private var lastSelection: AgentModelSelection?

    init() {
        do {
            let sandbox = try AgentSandbox.create()
            workspaceURL = sandbox
            fileSystem = AgentWorkspaceFileSystem(root: sandbox)
            isUsingSandbox = true
            conversation = [.init(role: .agent, text: "Ich bin bereit. Du kannst mir eine Frage stellen oder mich eine Textdatei im Sandkasten vorbereiten lassen.")]
        } catch {
            lastError = "Der lokale Agent-Sandkasten konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Arbeitsordner für den Agenten wählen"
        panel.prompt = "Ordner verwenden"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setWorkspace(url)
    }

    func setWorkspace(_ url: URL) {
        cancel()
        if workspaceHasSecurityScope, let oldURL = workspaceURL {
            oldURL.stopAccessingSecurityScopedResource()
        }
        workspaceHasSecurityScope = url.startAccessingSecurityScopedResource()
        workspaceURL = url.standardizedFileURL
        isUsingSandbox = false
        fileSystem = AgentWorkspaceFileSystem(root: url)
        pendingAction = nil
        lastWrittenURL = nil
        lastError = nil
        activities = [AgentActivity(kind: .success, title: "Arbeitsordner gewählt", detail: url.path)]
        do {
            try AgentWorkspaceBookmarkStore.save(url)
        } catch {
            addActivity(AgentActivity(kind: .warning, title: "Ordner konnte nicht dauerhaft gemerkt werden", detail: error.localizedDescription))
        }
    }

    func useSandbox() {
        cancel()
        if workspaceHasSecurityScope, let oldURL = workspaceURL {
            oldURL.stopAccessingSecurityScopedResource()
        }
        workspaceHasSecurityScope = false

        do {
            let sandbox = try AgentSandbox.create()
            workspaceURL = sandbox
            fileSystem = AgentWorkspaceFileSystem(root: sandbox)
            isUsingSandbox = true
            pendingAction = nil
            lastWrittenURL = nil
            lastError = nil
            activities = [AgentActivity(
                kind: .success,
                title: "Sicherer Sandkasten aktiv",
                detail: sandbox.path
            )]
        } catch {
            workspaceURL = nil
            fileSystem = nil
            isUsingSandbox = false
            lastError = "Der lokale Agent-Sandkasten konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }

    func run(prompt rawPrompt: String, selection: AgentModelSelection) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard workspaceURL != nil, let fileSystem else {
            lastError = AgentFileSystemError.noWorkspace.localizedDescription
            return
        }

        cancel(keepNotice: false)
        lastError = nil
        lastWrittenURL = nil
        pendingAction = nil
        isRunning = true
        currentStatus = "Aufgabe wird vorbereitet"
        lastPrompt = prompt
        lastSelection = selection
        appendConversation(.init(role: .user, text: prompt))
        plan = [
            AgentPlanStep(title: "Aufgabe und Grenzen prüfen", status: .active),
            AgentPlanStep(title: "Arbeitsordner untersuchen"),
            AgentPlanStep(title: "Sichere Aktion vorbereiten"),
            AgentPlanStep(title: "Ergebnis nachweisen")
        ]
        addActivity(AgentActivity(kind: .info, title: "Neue Aufgabe", detail: prompt))

        runTask = Task { [weak self] in
            guard let self else { return }
            await self.performRun(prompt: prompt, selection: selection, fileSystem: fileSystem)
        }
    }

    func retryLastRun() {
        guard !isRunning, let lastPrompt, let lastSelection else { return }
        run(prompt: lastPrompt, selection: lastSelection)
    }

    func cancel(keepNotice: Bool = true) {
        let hadWork = isRunning || pendingAction != nil
        runTask?.cancel()
        runTask = nil
        isRunning = false
        currentStatus = "Bereit"
        pendingAction = nil
        if hadWork && keepNotice {
            addActivity(AgentActivity(kind: .warning, title: "Agent gestoppt", detail: "Es wurde keine ausstehende Aktion ausgeführt."))
        }
    }

    func rejectPendingAction() {
        guard let pendingAction else { return }
        self.pendingAction = nil
        isRunning = false
        currentStatus = "Änderung abgelehnt"
        markPlan(index: 2, status: .waiting)
        addActivity(AgentActivity(
            kind: .warning,
            title: "Änderung nicht freigegeben",
            detail: pendingAction.relativePath
        ))
    }

    func approvePendingAction() {
        guard let action = pendingAction, let fileSystem else { return }
        pendingAction = nil
        isRunning = true
        lastError = nil

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await fileSystem.commit(action)
                try Task.checkCancellation()

                if action.kind == .revealInFinder || action.revealAfterWrite {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                self.lastWrittenURL = action.kind == .writeFile ? url : self.lastWrittenURL
                self.markPlan(index: 2, status: .completed)
                self.markPlan(index: 3, status: .completed)
                self.addActivity(AgentActivity(
                    kind: .success,
                    title: action.kind == .writeFile ? "Datei sicher geschrieben" : "Im Finder gezeigt",
                    detail: action.relativePath
                ))
                self.appendConversation(.init(role: .agent, text: action.kind == .writeFile ? "Erledigt – ich habe \(action.relativePath) sicher geschrieben." : "Erledigt – ich habe \(action.relativePath) im Finder gezeigt."))
                self.isRunning = false
                self.currentStatus = "Bereit"
                self.runTask = nil
            } catch is CancellationError {
                self.isRunning = false
            } catch {
                self.fail(error)
            }
        }
    }

    func revealLastResult() {
        guard let lastWrittenURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastWrittenURL])
    }

    private func performRun(
        prompt: String,
        selection: AgentModelSelection,
        fileSystem: AgentWorkspaceFileSystem
    ) async {
        let systemPrompt = """
        Du bist ein vorsichtiger lokaler macOS-Dateiagent. Antworte auf Deutsch. Arbeite ausschließlich im bereits vom Nutzer gewählten Arbeitsordner und verwende nur die angebotenen Werkzeuge. Verwende niemals absolute Pfade, .., versteckte Dateien, Zugangsdaten oder eine Shell. Lies oder liste nur, wenn es für die Aufgabe nötig ist. Für jede Dateiänderung musst du propose_write_file verwenden; die App holt danach eine sichtbare Freigabe ein. Wenn der Nutzer die erstellte Datei im Finder sehen möchte, setze reveal_in_finder auf true. Behaupte niemals, eine Aktion sei erfolgt, bevor das Werkzeug erfolgreich war. Gib keine private Gedankenkette aus, sondern nur kurze nachvollziehbare Aktionszusammenfassungen.
        """
        var messages = [
            AgentModelMessage(role: "system", content: systemPrompt),
            AgentModelMessage(role: "user", content: prompt)
        ]

        do {
            for iteration in 0..<6 {
                try Task.checkCancellation()
                addActivity(AgentActivity(
                    kind: .working,
                    title: iteration == 0 ? "Agent plant die Aufgabe" : "Agent wertet das Ergebnis aus",
                    detail: "Begrenzter Schritt \(iteration + 1) von 6"
                ))
                currentStatus = iteration == 0 ? "\(selection.provider.displayName) formuliert eine Antwort" : "Werkzeugergebnis wird ausgewertet"

                let (model, response): (String, AgentModelMessage)
                switch selection.provider {
                case .ollama:
                    (model, response) = try await ollamaClient.complete(messages: messages, preferredModel: selection.ollamaModel)
                case .gemini:
                    (model, response) = try await geminiClient.complete(messages: messages, preferredModel: selection.geminiModel)
                }
                try Task.checkCancellation()
                if iteration == 0 {
                    markPlan(index: 0, status: .completed)
                    markPlan(index: 1, status: .active)
                    addActivity(AgentActivity(kind: .info, title: "\(selection.provider.displayName)-Modell bereit", detail: model))
                }

                let calls = Array((response.toolCalls ?? []).prefix(4))
                if calls.isEmpty {
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw AgentModelError.invalidResponse }
                    guard !AgentTaskPolicy.requiresFileTool(prompt) else {
                        throw AgentModelError.invalidResponse
                    }
                    markPlan(index: 1, status: .completed)
                    markPlan(index: 2, status: .completed)
                    markPlan(index: 3, status: .completed)
                    addActivity(AgentActivity(kind: .success, title: "Agent fertig", detail: text))
                    appendConversation(.init(role: .agent, text: text, providerLabel: "\(selection.provider.displayName) · \(model)"))
                    isRunning = false
                    currentStatus = "Bereit"
                    runTask = nil
                    return
                }

                messages.append(response)
                for call in calls {
                    try Task.checkCancellation()
                    let name = call.function.name
                    let arguments = call.function.arguments
                    switch name {
                    case "list_directory":
                        let path = arguments["path"]?.stringValue ?? ""
                        let result = try await fileSystem.listDirectory(relativePath: path)
                        markPlan(index: 1, status: .completed)
                        addActivity(AgentActivity(kind: .success, title: "Ordner gelesen", detail: path.isEmpty ? "Hauptordner" : path))
                        messages.append(AgentModelMessage(role: "tool", content: limitedToolResult(result), toolName: name))

                    case "read_file":
                        guard let path = arguments["path"]?.stringValue else { throw AgentModelError.invalidResponse }
                        let result = try await fileSystem.readFile(relativePath: path)
                        markPlan(index: 1, status: .completed)
                        addActivity(AgentActivity(kind: .success, title: "Datei gelesen", detail: path))
                        messages.append(AgentModelMessage(role: "tool", content: limitedToolResult(result), toolName: name))

                    case "propose_write_file":
                        guard let path = arguments["path"]?.stringValue,
                              let content = arguments["content"]?.stringValue else {
                            throw AgentModelError.invalidResponse
                        }
                        let reason = arguments["reason"]?.stringValue ?? "Vom Agenten vorgeschlagene Dateiänderung"
                        let reveal = arguments["reveal_in_finder"]?.boolValue ?? false
                        let action = try await fileSystem.prepareWrite(
                            relativePath: path,
                            content: content,
                            reason: reason,
                            revealAfterWrite: reveal
                        )
                        markPlan(index: 1, status: .completed)
                        markPlan(index: 2, status: .active)
                        pendingAction = action
                        isRunning = false
                        currentStatus = "Wartet auf deine Freigabe"
                        runTask = nil
                        addActivity(AgentActivity(kind: .warning, title: "Freigabe erforderlich", detail: path))
                        appendConversation(.init(role: .agent, text: "Ich habe die Änderung für \(path) vorbereitet. Bitte prüfe den vollständigen Inhalt und gib das Schreiben anschließend frei.", providerLabel: selection.displayLabel))
                        return

                    case "reveal_in_finder":
                        guard let path = arguments["path"]?.stringValue else { throw AgentModelError.invalidResponse }
                        let reason = arguments["reason"]?.stringValue ?? "Datei im Finder anzeigen"
                        let action = try await fileSystem.prepareReveal(relativePath: path, reason: reason)
                        markPlan(index: 1, status: .completed)
                        markPlan(index: 2, status: .active)
                        pendingAction = action
                        isRunning = false
                        currentStatus = "Wartet auf deine Freigabe"
                        runTask = nil
                        addActivity(AgentActivity(kind: .warning, title: "Freigabe erforderlich", detail: path))
                        appendConversation(.init(role: .agent, text: "Ich kann \(path) im Finder zeigen, sobald du diese Aktion freigibst.", providerLabel: selection.displayLabel))
                        return

                    default:
                        messages.append(AgentModelMessage(role: "tool", content: "Werkzeug ist nicht erlaubt.", toolName: name))
                        addActivity(AgentActivity(kind: .warning, title: "Unbekanntes Werkzeug blockiert", detail: name))
                    }
                }
            }
            throw AgentModelError.invalidResponse
        } catch is CancellationError {
            isRunning = false
            currentStatus = "Bereit"
            runTask = nil
        } catch {
            fail(error)
        }
    }

    private func limitedToolResult(_ value: String) -> String {
        let limit = 20_000
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "\n… Ausgabe sicher gekürzt"
    }

    private func markPlan(index: Int, status: AgentPlanStatus) {
        guard plan.indices.contains(index) else { return }
        plan[index].status = status
    }

    private func addActivity(_ activity: AgentActivity) {
        activities.append(activity)
        if activities.count > 200 {
            activities.removeFirst(activities.count - 200)
        }
    }

    private func appendConversation(_ entry: AgentConversationEntry) {
        conversation.append(entry)
        if conversation.count > 60 { conversation.removeFirst(conversation.count - 60) }
    }

    private func fail(_ error: Error) {
        isRunning = false
        runTask = nil
        let message = error.localizedDescription
        lastError = message
        currentStatus = "Antwort nicht abgeschlossen"
        appendConversation(.init(role: .agent, text: "Ich konnte diese Aufgabe nicht abschließen. \(message)"))
        addActivity(AgentActivity(kind: .failure, title: "Agent sicher gestoppt", detail: message))
    }
}

enum AgentTaskPolicy {
    static func requiresFileTool(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        let markers = [
            "datei", "ordner", "finder", "dokument", "textfile",
            "schreib", "erstell", "speicher", "öffne", "oeffne", "lies", "lese"
        ]
        return markers.contains(where: lower.contains)
    }
}
