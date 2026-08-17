import Foundation
import SwiftUI
import AppKit

// MARK: - Chat

enum ChatSpeaker: String, Codable, Sendable, Hashable {
    case alice
    case bob
    case user

    var fallbackDisplayName: String {
        switch self {
        case .alice: return "Alice"
        case .bob: return "Bob"
        case .user: return "Du"
        }
    }

    var fallbackInitial: String {
        switch self {
        case .alice: return "A"
        case .bob: return "B"
        case .user: return "D"
        }
    }

    var otherAI: ChatSpeaker {
        switch self {
        case .alice: return .bob
        case .bob: return .alice
        case .user: return .alice
        }
    }
}

struct WebSource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let url: String

    init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

struct InlineCitation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceID: UUID
    let startUTF8Offset: Int?
    let endUTF8Offset: Int?
    let evidenceQuote: String?

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        startUTF8Offset: Int? = nil,
        endUTF8Offset: Int? = nil,
        evidenceQuote: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.startUTF8Offset = startUTF8Offset
        self.endUTF8Offset = endUTF8Offset
        self.evidenceQuote = evidenceQuote
    }
}

struct ResearchStatus: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Hashable, Sendable {
        case ollamaSearch = "ollama_search"
        case geminiGrounding = "gemini_grounding"
        case unavailable
    }

    let query: String
    let resultCount: Int
    let fetchedPageCount: Int
    let mode: Mode

    var displayText: String {
        switch mode {
        case .ollamaSearch:
            return "\(resultCount) Treffer gefunden · \(fetchedPageCount) Seiten gelesen"
        case .geminiGrounding:
            return "Gemini-Websuche · \(resultCount) belegte Quelle(n)"
        case .unavailable:
            return "Live-Recherche nicht verfügbar"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let speaker: ChatSpeaker
    let text: String
    let date: Date
    let sources: [WebSource]?
    let citations: [InlineCitation]?
    let researchStatus: ResearchStatus?

    init(
        id: UUID = UUID(),
        speaker: ChatSpeaker,
        text: String,
        date: Date = Date(),
        sources: [WebSource]? = nil,
        citations: [InlineCitation]? = nil,
        researchStatus: ResearchStatus? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.date = date
        self.sources = sources?.isEmpty == true ? nil : sources
        self.citations = citations?.isEmpty == true ? nil : citations
        self.researchStatus = researchStatus
    }
}

struct ConversationMemory: Codable, Hashable, Sendable {
    var summary: String
    var coveredMessageCount: Int
    var updatedAt: Date

    static let empty = ConversationMemory(summary: "", coveredMessageCount: 0, updatedAt: .distantPast)
}

struct PersistedConversation: Codable, Sendable {
    var messages: [ChatMessage]
    var memory: ConversationMemory
}

struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var memory: ConversationMemory
    // Optional for backward-compatible decoding of sessions created before v15.
    var mode: ChatMode?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        memory: ConversationMemory = .empty,
        mode: ChatMode? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.memory = memory
        self.mode = mode
    }
}

struct PersistedSessionStore: Codable, Sendable {
    var selectedSessionID: UUID
    var sessions: [ChatSession]
}

enum ChatMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case group
    case single

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .group: return "Gruppe"
        case .single: return "KI-Chat"
        }
    }
}

enum ReplyMode: String, Sendable {
    case autonomous
    case directUser
    case followUpUser
    case doubleText
}

// MARK: - Provider

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case gemini
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        }
    }
}

struct AIProfileSnapshot: Sendable {
    let name: String
    let role: String
    let personality: String
    let creativity: Double
    let preferredLanguage: String
}

struct ParticipantAISelectionSnapshot: Sendable {
    let provider: AIProvider
    let geminiModel: String
    let ollamaModel: String

    var activeModel: String {
        switch provider {
        case .gemini: return geminiModel
        case .ollama: return ollamaModel
        }
    }
}

struct PreferencesSnapshot: Sendable {
    let chatMode: ChatMode
    let aliceAI: ParticipantAISelectionSnapshot
    let bobAI: ParticipantAISelectionSnapshot
    let conversationTopic: String
    let memoryEnabled: Bool
    let doubleTextingEnabled: Bool
    let doubleTextChance: Double
    let autoFallbackToOllama: Bool
    let simulatedStreamingEnabled: Bool
    let webAccessEnabled: Bool
    let limitProtectionEnabled: Bool
    let geminiDailyRequestSoftLimit: Int
    let alice: AIProfileSnapshot
    let bob: AIProfileSnapshot

    func profile(for speaker: ChatSpeaker) -> AIProfileSnapshot {
        switch speaker {
        case .alice: return alice
        case .bob: return bob
        case .user:
            return AIProfileSnapshot(
                name: "Du",
                role: "Menschlicher Teilnehmer",
                personality: "",
                creativity: 0.5,
                preferredLanguage: "Deutsch"
            )
        }
    }

    func aiSelection(for speaker: ChatSpeaker) -> ParticipantAISelectionSnapshot {
        switch speaker {
        case .alice: return aliceAI
        case .bob: return bobAI
        case .user: return aliceAI
        }
    }

    func name(for speaker: ChatSpeaker) -> String {
        profile(for: speaker).name
    }
}

// MARK: - Preferences

enum AppDesignMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case current
    case transparentGlass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: return "Aktuelles Design"
        case .transparentGlass: return "Transparent Glass"
        }
    }
}

enum DesignDefaults {
    static let currentBackgroundOpacity = 0.34
    static let currentBackgroundBlur = 7.0
    static let transparentBackgroundOpacity = 0.18
    static let transparentBackgroundBlur = 12.0

    static func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func clampedBlur(_ value: Double) -> Double {
        min(max(value, 0), 24)
    }
}

@MainActor
final class Preferences: ObservableObject {
    private enum Keys {
        static let legacyProvider = "provider"
        static let legacyGeminiModel = "geminiModel"
        static let legacyOllamaModel = "ollamaModel"
        static let participantMigrationV13 = "participantMigrationV13"

        static let aliceProvider = "aliceProviderV13"
        static let bobProvider = "bobProviderV13"
        static let aliceGeminiModel = "aliceGeminiModelV13"
        static let bobGeminiModel = "bobGeminiModelV13"
        static let aliceOllamaModel = "aliceOllamaModelV13"
        static let bobOllamaModel = "bobOllamaModelV13"

        static let chatMode = "chatModeV14"
        static let showMessageCount = "showMessageCount"
        static let autonomousEnabled = "autonomousEnabled"
        static let interval = "interval"
        static let backgroundOpacity = "backgroundOpacity"
        static let backgroundBlur = "backgroundBlur"
        static let designMode = "designModeV18"
        static let transparentBackgroundOpacity = "transparentBackgroundOpacityV18"
        static let transparentBackgroundBlur = "transparentBackgroundBlurV18"
        static let tintRed = "tintRed"
        static let tintGreen = "tintGreen"
        static let tintBlue = "tintBlue"
        static let conversationTopic = "conversationTopic"
        static let memoryEnabled = "memoryEnabled"
        static let doubleTextingEnabled = "doubleTextingEnabled"
        static let doubleTextChance = "doubleTextChance"
        static let autoFallbackToOllama = "autoFallbackToOllama"
        static let simulatedStreamingEnabled = "simulatedStreamingEnabled"
        static let webAccessEnabled = "webAccessEnabled"
        static let limitProtectionEnabled = "limitProtectionEnabledV13"
        static let geminiDailyRequestSoftLimit = "geminiDailyRequestSoftLimitV13"
        static let topicPromptCompleted = "topicPromptCompletedV13"

        static let aliceName = "aliceName"
        static let aliceRole = "aliceRole"
        static let alicePersonality = "alicePersonality"
        static let aliceCreativity = "aliceCreativity"
        static let aliceLanguage = "aliceLanguage"
        static let bobName = "bobName"
        static let bobRole = "bobRole"
        static let bobPersonality = "bobPersonality"
        static let bobCreativity = "bobCreativity"
        static let bobLanguage = "bobLanguage"
    }

    private let defaults: UserDefaults
    private var isLoading = true

    @Published var aliceProvider: AIProvider { didSet { save(Keys.aliceProvider, aliceProvider.rawValue) } }
    @Published var bobProvider: AIProvider { didSet { save(Keys.bobProvider, bobProvider.rawValue) } }
    @Published var aliceGeminiModel: String { didSet { save(Keys.aliceGeminiModel, aliceGeminiModel) } }
    @Published var bobGeminiModel: String { didSet { save(Keys.bobGeminiModel, bobGeminiModel) } }
    @Published var aliceOllamaModel: String { didSet { save(Keys.aliceOllamaModel, aliceOllamaModel) } }
    @Published var bobOllamaModel: String { didSet { save(Keys.bobOllamaModel, bobOllamaModel) } }

    @Published var chatMode: ChatMode { didSet { save(Keys.chatMode, chatMode.rawValue) } }
    @Published var showMessageCount: Bool { didSet { save(Keys.showMessageCount, showMessageCount) } }
    @Published var autonomousEnabled: Bool { didSet { save(Keys.autonomousEnabled, autonomousEnabled) } }
    @Published var interval: Double { didSet { save(Keys.interval, interval) } }
    @Published var backgroundOpacity: Double { didSet { save(Keys.backgroundOpacity, backgroundOpacity) } }
    @Published var backgroundBlur: Double { didSet { save(Keys.backgroundBlur, backgroundBlur) } }
    @Published var designMode: AppDesignMode { didSet { save(Keys.designMode, designMode.rawValue) } }
    @Published var transparentBackgroundOpacity: Double { didSet { save(Keys.transparentBackgroundOpacity, transparentBackgroundOpacity) } }
    @Published var transparentBackgroundBlur: Double { didSet { save(Keys.transparentBackgroundBlur, transparentBackgroundBlur) } }
    @Published var tintRed: Double { didSet { save(Keys.tintRed, tintRed) } }
    @Published var tintGreen: Double { didSet { save(Keys.tintGreen, tintGreen) } }
    @Published var tintBlue: Double { didSet { save(Keys.tintBlue, tintBlue) } }
    @Published var conversationTopic: String { didSet { save(Keys.conversationTopic, conversationTopic) } }
    @Published var memoryEnabled: Bool { didSet { save(Keys.memoryEnabled, memoryEnabled) } }
    @Published var doubleTextingEnabled: Bool { didSet { save(Keys.doubleTextingEnabled, doubleTextingEnabled) } }
    @Published var doubleTextChance: Double { didSet { save(Keys.doubleTextChance, doubleTextChance) } }
    @Published var autoFallbackToOllama: Bool { didSet { save(Keys.autoFallbackToOllama, autoFallbackToOllama) } }
    @Published var simulatedStreamingEnabled: Bool { didSet { save(Keys.simulatedStreamingEnabled, simulatedStreamingEnabled) } }
    @Published var webAccessEnabled: Bool { didSet { save(Keys.webAccessEnabled, webAccessEnabled) } }
    @Published var limitProtectionEnabled: Bool { didSet { save(Keys.limitProtectionEnabled, limitProtectionEnabled) } }
    @Published var geminiDailyRequestSoftLimit: Int { didSet { save(Keys.geminiDailyRequestSoftLimit, geminiDailyRequestSoftLimit) } }
    @Published var topicPromptCompleted: Bool { didSet { save(Keys.topicPromptCompleted, topicPromptCompleted) } }

    @Published var aliceName: String { didSet { save(Keys.aliceName, aliceName) } }
    @Published var aliceRole: String { didSet { save(Keys.aliceRole, aliceRole) } }
    @Published var alicePersonality: String { didSet { save(Keys.alicePersonality, alicePersonality) } }
    @Published var aliceCreativity: Double { didSet { save(Keys.aliceCreativity, aliceCreativity) } }
    @Published var aliceLanguage: String { didSet { save(Keys.aliceLanguage, aliceLanguage) } }

    @Published var bobName: String { didSet { save(Keys.bobName, bobName) } }
    @Published var bobRole: String { didSet { save(Keys.bobRole, bobRole) } }
    @Published var bobPersonality: String { didSet { save(Keys.bobPersonality, bobPersonality) } }
    @Published var bobCreativity: Double { didSet { save(Keys.bobCreativity, bobCreativity) } }
    @Published var bobLanguage: String { didSet { save(Keys.bobLanguage, bobLanguage) } }

    init(defaults: UserDefaults = .standard, hasGeminiKeyOverride: Bool? = nil) {
        self.defaults = defaults
        let hasGeminiKey = hasGeminiKeyOverride ?? !(KeychainStore.read() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let legacyProvider = AIProvider(rawValue: defaults.string(forKey: Keys.legacyProvider) ?? "")
            ?? (hasGeminiKey ? .gemini : .ollama)
        let legacyGemini = defaults.string(forKey: Keys.legacyGeminiModel) ?? "gemini-3.7-flash"
        let legacyOllama = defaults.string(forKey: Keys.legacyOllamaModel) ?? "qwen3.5:9b"
        let migrated = defaults.bool(forKey: Keys.participantMigrationV13)

        if migrated {
            aliceProvider = AIProvider(rawValue: defaults.string(forKey: Keys.aliceProvider) ?? "") ?? legacyProvider
            bobProvider = AIProvider(rawValue: defaults.string(forKey: Keys.bobProvider) ?? "") ?? legacyProvider
            aliceGeminiModel = defaults.string(forKey: Keys.aliceGeminiModel) ?? legacyGemini
            bobGeminiModel = defaults.string(forKey: Keys.bobGeminiModel) ?? legacyGemini
            aliceOllamaModel = defaults.string(forKey: Keys.aliceOllamaModel) ?? legacyOllama
            bobOllamaModel = defaults.string(forKey: Keys.bobOllamaModel) ?? legacyOllama
        } else {
            aliceProvider = legacyProvider
            bobProvider = legacyProvider
            aliceGeminiModel = legacyGemini
            bobGeminiModel = legacyGemini
            aliceOllamaModel = legacyOllama
            bobOllamaModel = legacyOllama
            defaults.set(true, forKey: Keys.participantMigrationV13)
        }

        chatMode = ChatMode(rawValue: defaults.string(forKey: Keys.chatMode) ?? "") ?? .group

        showMessageCount = defaults.object(forKey: Keys.showMessageCount) as? Bool ?? true
        autonomousEnabled = defaults.object(forKey: Keys.autonomousEnabled) as? Bool ?? true
        interval = defaults.object(forKey: Keys.interval) as? Double ?? 8.0
        backgroundOpacity = defaults.object(forKey: Keys.backgroundOpacity) as? Double
            ?? DesignDefaults.currentBackgroundOpacity
        backgroundBlur = defaults.object(forKey: Keys.backgroundBlur) as? Double
            ?? DesignDefaults.currentBackgroundBlur
        designMode = AppDesignMode(rawValue: defaults.string(forKey: Keys.designMode) ?? "") ?? .current
        transparentBackgroundOpacity = DesignDefaults.clampedOpacity(
            defaults.object(forKey: Keys.transparentBackgroundOpacity) as? Double
                ?? DesignDefaults.transparentBackgroundOpacity
        )
        transparentBackgroundBlur = DesignDefaults.clampedBlur(
            defaults.object(forKey: Keys.transparentBackgroundBlur) as? Double
                ?? DesignDefaults.transparentBackgroundBlur
        )
        tintRed = defaults.object(forKey: Keys.tintRed) as? Double ?? 0.34
        tintGreen = defaults.object(forKey: Keys.tintGreen) as? Double ?? 0.46
        tintBlue = defaults.object(forKey: Keys.tintBlue) as? Double ?? 0.95
        conversationTopic = defaults.string(forKey: Keys.conversationTopic) ?? ""
        memoryEnabled = defaults.object(forKey: Keys.memoryEnabled) as? Bool ?? true
        doubleTextingEnabled = defaults.object(forKey: Keys.doubleTextingEnabled) as? Bool ?? true
        doubleTextChance = defaults.object(forKey: Keys.doubleTextChance) as? Double ?? 0.25
        autoFallbackToOllama = defaults.object(forKey: Keys.autoFallbackToOllama) as? Bool ?? true

        // Bewusst bei jedem Start aus, wie gewünscht.
        simulatedStreamingEnabled = false
        defaults.set(false, forKey: Keys.simulatedStreamingEnabled)

        webAccessEnabled = defaults.object(forKey: Keys.webAccessEnabled) as? Bool ?? false
        limitProtectionEnabled = defaults.object(forKey: Keys.limitProtectionEnabled) as? Bool ?? true
        geminiDailyRequestSoftLimit = defaults.object(forKey: Keys.geminiDailyRequestSoftLimit) as? Int ?? 0
        topicPromptCompleted = defaults.object(forKey: Keys.topicPromptCompleted) as? Bool ?? false

        aliceName = defaults.string(forKey: Keys.aliceName) ?? "Alice"
        aliceRole = defaults.string(forKey: Keys.aliceRole) ?? "Kreative Ideengeberin"
        alicePersonality = defaults.string(forKey: Keys.alicePersonality)
            ?? "Neugierig, warm, intuitiv und ideenreich. Sucht ungewöhnliche Verbindungen und denkt gern einen Schritt weiter."
        aliceCreativity = defaults.object(forKey: Keys.aliceCreativity) as? Double ?? 0.78
        aliceLanguage = defaults.string(forKey: Keys.aliceLanguage) ?? "Deutsch"

        bobName = defaults.string(forKey: Keys.bobName) ?? "Bob"
        bobRole = defaults.string(forKey: Keys.bobRole) ?? "Analytischer Gegenpart"
        bobPersonality = defaults.string(forKey: Keys.bobPersonality)
            ?? "Ruhig, präzise und skeptisch. Prüft Annahmen, erkennt Schwachstellen und bringt begründete Gegenargumente mit trockenem Humor."
        bobCreativity = defaults.object(forKey: Keys.bobCreativity) as? Double ?? 0.52
        bobLanguage = defaults.string(forKey: Keys.bobLanguage) ?? "Deutsch"

        // Erst nachdem ALLE gespeicherten Eigenschaften initialisiert sind,
        // duerfen wir auf self / @Published-Werte zugreifen. Sonst meldet Swift:
        // "self used before all stored properties are initialized".
        func shouldMigrateGeminiModel(_ value: String) -> Bool {
            let lower = value.lowercased()
            return lower.contains("gemini-2.5-flash") ||
                   lower.contains("gemini-2.0-flash") ||
                   lower.contains("gemini-3.1-pro-preview")
        }
        if shouldMigrateGeminiModel(aliceGeminiModel) {
            aliceGeminiModel = "gemini-3.7-flash"
        }
        if shouldMigrateGeminiModel(bobGeminiModel) {
            bobGeminiModel = "gemini-3.7-flash"
        }

        // Ollama-Cloud-Modelle haben bei diesem Projekt wiederholt 403/Subscription-Fehler geliefert.
        // v15 migriert solche gespeicherten Auswahlen zurück auf "noch nicht gewählt"; beim Laden
        // lokaler Modelle wird automatisch ein vorhandenes lokales Modell gesetzt.
        if aliceOllamaModel.lowercased().contains(":cloud") {
            aliceOllamaModel = ""
        }
        if bobOllamaModel.lowercased().contains(":cloud") {
            bobOllamaModel = ""
        }

        isLoading = false
    }

    var tintColor: Color {
        Color(red: tintRed, green: tintGreen, blue: tintBlue)
    }

    func setTint(from color: Color) {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return }
        tintRed = rgb.redComponent
        tintGreen = rgb.greenComponent
        tintBlue = rgb.blueComponent
    }

    func resetTransparentGlassDesign() {
        transparentBackgroundOpacity = DesignDefaults.transparentBackgroundOpacity
        transparentBackgroundBlur = DesignDefaults.transparentBackgroundBlur
    }

    func name(for speaker: ChatSpeaker) -> String {
        switch speaker {
        case .alice:
            let trimmed = aliceName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Alice" : trimmed
        case .bob:
            let trimmed = bobName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Bob" : trimmed
        case .user:
            return "Du"
        }
    }

    func initial(for speaker: ChatSpeaker) -> String {
        String(name(for: speaker).prefix(1)).uppercased()
    }


    func chatDisplayName(for speaker: ChatSpeaker) -> String {
        guard chatMode == .single, speaker == .alice else { return name(for: speaker) }
        let provider = provider(for: speaker)
        let rawModel = model(for: speaker).trimmingCharacters(in: .whitespacesAndNewlines)
        if rawModel.isEmpty { return provider.displayName }
        return Self.prettyModelName(rawModel, provider: provider)
    }

    func chatInitial(for speaker: ChatSpeaker) -> String {
        String(chatDisplayName(for: speaker).prefix(1)).uppercased()
    }

    private static func prettyModelName(_ raw: String, provider: AIProvider) -> String {
        let lower = raw.lowercased()
        if provider == .gemini {
            return raw
                .replacingOccurrences(of: "gemini-", with: "Gemini ", options: [.caseInsensitive])
                .replacingOccurrences(of: "-preview", with: " Preview", options: [.caseInsensitive])
                .replacingOccurrences(of: "-flash", with: " Flash", options: [.caseInsensitive])
                .replacingOccurrences(of: "-lite", with: " Lite", options: [.caseInsensitive])
                .replacingOccurrences(of: "-pro", with: " Pro", options: [.caseInsensitive])
        }
        if lower.hasPrefix("llama3") {
            return raw.replacingOccurrences(of: "llama", with: "Llama ", options: [.caseInsensitive])
                .replacingOccurrences(of: ":latest", with: "", options: [.caseInsensitive])
        }
        return raw.replacingOccurrences(of: ":latest", with: "", options: [.caseInsensitive])
    }

    func provider(for speaker: ChatSpeaker) -> AIProvider {
        switch speaker {
        case .alice: return aliceProvider
        case .bob: return bobProvider
        case .user: return aliceProvider
        }
    }

    func model(for speaker: ChatSpeaker) -> String {
        switch speaker {
        case .alice:
            return aliceProvider == .gemini ? aliceGeminiModel : aliceOllamaModel
        case .bob:
            return bobProvider == .gemini ? bobGeminiModel : bobOllamaModel
        case .user:
            return ""
        }
    }

    func snapshot() -> PreferencesSnapshot {
        PreferencesSnapshot(
            chatMode: chatMode,
            aliceAI: ParticipantAISelectionSnapshot(
                provider: aliceProvider,
                geminiModel: aliceGeminiModel.trimmingCharacters(in: .whitespacesAndNewlines),
                ollamaModel: aliceOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            bobAI: ParticipantAISelectionSnapshot(
                provider: bobProvider,
                geminiModel: bobGeminiModel.trimmingCharacters(in: .whitespacesAndNewlines),
                ollamaModel: bobOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            conversationTopic: conversationTopic.trimmingCharacters(in: .whitespacesAndNewlines),
            memoryEnabled: memoryEnabled,
            doubleTextingEnabled: doubleTextingEnabled,
            doubleTextChance: min(max(doubleTextChance, 0), 1),
            autoFallbackToOllama: autoFallbackToOllama,
            simulatedStreamingEnabled: simulatedStreamingEnabled,
            webAccessEnabled: webAccessEnabled,
            limitProtectionEnabled: limitProtectionEnabled,
            geminiDailyRequestSoftLimit: max(0, geminiDailyRequestSoftLimit),
            alice: AIProfileSnapshot(
                name: name(for: .alice),
                role: aliceRole.trimmingCharacters(in: .whitespacesAndNewlines),
                personality: alicePersonality.trimmingCharacters(in: .whitespacesAndNewlines),
                creativity: min(max(aliceCreativity, 0), 1),
                preferredLanguage: aliceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Deutsch" : aliceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            bob: AIProfileSnapshot(
                name: name(for: .bob),
                role: bobRole.trimmingCharacters(in: .whitespacesAndNewlines),
                personality: bobPersonality.trimmingCharacters(in: .whitespacesAndNewlines),
                creativity: min(max(bobCreativity, 0), 1),
                preferredLanguage: bobLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Deutsch" : bobLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    func resetProfilesToDefaults() {
        aliceName = "Alice"
        aliceRole = "Kreative Ideengeberin"
        alicePersonality = "Neugierig, warm, intuitiv und ideenreich. Sucht ungewöhnliche Verbindungen und denkt gern einen Schritt weiter."
        aliceCreativity = 0.78
        aliceLanguage = "Deutsch"

        bobName = "Bob"
        bobRole = "Analytischer Gegenpart"
        bobPersonality = "Ruhig, präzise und skeptisch. Prüft Annahmen, erkennt Schwachstellen und bringt begründete Gegenargumente mit trockenem Humor."
        bobCreativity = 0.52
        bobLanguage = "Deutsch"
    }

    private func save(_ key: String, _ value: Any) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }
}
