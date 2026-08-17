import Foundation

actor AIService {
    static let recommendedGeminiModel = "gemini-3.7-flash"

    enum AIServiceError: LocalizedError {
        case missingGeminiKey
        case missingModel
        case noOllamaModels
        case missingOllamaWebSearchKey
        case invalidURL
        case badResponse
        case server(status: Int, message: String)
        case emptyReply
        case requestTimedOut

        var errorDescription: String? {
            switch self {
            case .missingGeminiKey:
                return "Gemini-API-Key fehlt. Öffne Einstellungen (⌘,)."
            case .missingModel:
                return "Bitte wähle zuerst ein Modell in den Einstellungen."
            case .noOllamaModels:
                return "Kein lokales Ollama-Modell verfügbar. Lade zuerst ein Modell im Ollama-Katalog herunter."
            case .missingOllamaWebSearchKey:
                return "Für Live-Websuche mit Ollama fehlt der Ollama Web Search API-Key. Du kannst ihn in Einstellungen → Allgemein → Internet hinterlegen."
            case .invalidURL:
                return "Die API-Adresse ist ungültig."
            case .badResponse:
                return "Die KI hat eine unerwartete Antwort gesendet."
            case .server(let status, let message):
                return "API-Fehler \(status): \(message)"
            case .emptyReply:
                return "Die KI hat keine Textantwort geliefert."
            case .requestTimedOut:
                return "Die Antwort hat zu lange gedauert und wurde beendet. Bitte erneut versuchen oder ein schnelleres Modell wählen."
            }
        }
    }

    struct AIReply: Sendable {
        let text: String
        let sources: [WebSource]
        let citations: [InlineCitation]
        let researchStatus: ResearchStatus?

        init(
            text: String,
            sources: [WebSource] = [],
            citations: [InlineCitation] = [],
            researchStatus: ResearchStatus? = nil
        ) {
            self.text = text
            self.sources = sources
            self.citations = citations
            self.researchStatus = researchStatus
        }
    }

    struct ProviderUsageStatus: Identifiable, Sendable {
        var id: String { provider.rawValue }
        let provider: AIProvider
        let requestsToday: Int
        let inputTokensToday: Int
        let outputTokensToday: Int
        let dateKey: String
        let note: String?

        var totalTokensToday: Int { inputTokensToday + outputTokensToday }
    }

    struct OllamaModel: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let sizeBytes: Int64?
        let parameterSize: String?
        let family: String?
    }

    struct OllamaCatalogModel: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let sizeBytes: Int64?
        let specialization: String
        let summary: String

        var sizeLabel: String? {
            guard let sizeBytes = effectiveSizeBytes, sizeBytes > 0 else { return nil }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: sizeBytes)
        }

        var effectiveSizeBytes: Int64? {
            if let sizeBytes, sizeBytes > 0 { return sizeBytes }
            switch name.lowercased() {
            case "qwen3.5:9b", "qwen3.5:latest": return 6_600_000_000
            case "qwen3.5:27b": return 17_000_000_000
            case "qwen3.5:35b", "qwen3.5:35b-a3b": return 24_000_000_000
            default: return nil
            }
        }

        var isCloud: Bool {
            name.lowercased().contains(":cloud")
        }
    }

    struct OllamaPullProgress: Sendable {
        let status: String
        let completed: Int64?
        let total: Int64?

        var fraction: Double? {
            guard let completed, let total, total > 0 else { return nil }
            return min(max(Double(completed) / Double(total), 0), 1)
        }
    }

    private struct UsageRecord: Codable {
        var dateKey: String
        var requests: Int
        var inputTokens: Int
        var outputTokens: Int
    }

    private let usageDefaults = UserDefaults.standard

    // MARK: - Public generation

    func generateReply(
        speaker: ChatSpeaker,
        messages: [ChatMessage],
        memory: ConversationMemory,
        preferences: PreferencesSnapshot,
        replyMode: ReplyMode,
        focusedUserMessageID: UUID? = nil
    ) async throws -> AIReply {
        let selection = preferences.aiSelection(for: speaker)
        let profile = preferences.profile(for: speaker)
        let systemPrompt = Self.systemPrompt(
            for: speaker,
            preferences: preferences,
            memory: preferences.memoryEnabled ? memory : .empty
        )

        let requestedSearchQuery = Self.searchQuery(
            messages: messages,
            focusedUserMessageID: focusedUserMessageID,
            replyMode: replyMode
        )
        let webRequested = preferences.webAccessEnabled && requestedSearchQuery.map(Self.shouldUseWebSearch) == true
        let focusedText = focusedUserMessageID.flatMap { id in
            messages.first(where: { $0.id == id && $0.speaker == .user })?.text
        } ?? requestedSearchQuery ?? ""
        let responseIntent = ResponseIntent.detect(userText: focusedText, webRequested: webRequested)

        var externalWebContext: WebContext?
        if webRequested, let query = requestedSearchQuery {
            // Wenn ein Ollama-Web-Search-Key vorhanden ist, kann dieselbe neutrale Websuche
            // sowohl lokale Ollama-Modelle als auch Gemini mit frischem Kontext versorgen.
            // Dadurch hängt Live-Recherche nicht ausschließlich vom Google-Grounding-Tier ab.
            if let ollamaWebKey = KeychainStore.read(account: KeychainStore.ollamaWebSearchAccount),
               !ollamaWebKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    externalWebContext = try await fetchOllamaWebContext(for: query, apiKey: ollamaWebKey)
                } catch {
                    if selection.provider == .ollama {
                        externalWebContext = WebContext(
                            text: "Die Live-Websuche ist fehlgeschlagen. Sage dem Nutzer ehrlich, dass du gerade keine aktuellen Webdaten abrufen konntest, statt Informationen zu erfinden.",
                            sources: [],
                            evidence: [],
                            query: query,
                            resultCount: 0,
                            fetchedPageCount: 0
                        )
                    }
                    // Bei Gemini darf anschließend noch das native Google-Search-Grounding versuchen.
                }
            } else if selection.provider == .ollama {
                externalWebContext = WebContext(
                    text: "Der Nutzer möchte eine aktuelle Internetrecherche, aber für Ollama ist kein Web-Search-API-Key eingerichtet. Sage das klar und erfinde keine aktuellen Fakten.",
                    sources: [],
                    evidence: [],
                    query: query,
                    resultCount: 0,
                    fetchedPageCount: 0
                )
            }
        }

        if selection.provider == .ollama,
           webRequested,
           externalWebContext?.sources.isEmpty != false {
            return AIReply(
                text: "Ich konnte gerade keine verlässlichen Live-Quellen abrufen. Prüfe bitte den Ollama-Web-Search-Key und versuche es erneut; ich erfinde dafür keine aktuellen Fakten.",
                researchStatus: ResearchStatus(
                    query: requestedSearchQuery ?? "",
                    resultCount: 0,
                    fetchedPageCount: 0,
                    mode: .unavailable
                )
            )
        }

        let transcript = Self.transcriptPrompt(
            nextSpeaker: speaker,
            messages: messages,
            preferences: preferences,
            focusedUserMessageID: focusedUserMessageID,
            replyMode: replyMode,
            webContext: externalWebContext?.text,
            responseIntent: responseIntent
        )

        switch selection.provider {
        case .gemini:
            let model = Self.normalizedGeminiModel(selection.geminiModel)
            guard !model.isEmpty else { throw AIServiceError.missingModel }
            guard let key = KeychainStore.read(), !key.isEmpty else { throw AIServiceError.missingGeminiKey }

            let useNativeGoogleSearch = webRequested && externalWebContext == nil
            let geminiReply: AIReply
            do {
                geminiReply = try await callGemini(
                    model: model,
                    apiKey: key,
                    systemPrompt: systemPrompt,
                    input: transcript,
                    maxOutputTokens: 720,
                    thinkingLevel: Self.geminiThinkingLevel(for: model),
                    googleSearchEnabled: useNativeGoogleSearch
                )
            } catch {
                if useNativeGoogleSearch && Self.isGeminiSearchUnavailableError(error) {
                    let noSearchTranscript = Self.transcriptPrompt(
                        nextSpeaker: speaker,
                        messages: messages,
                        preferences: preferences,
                        focusedUserMessageID: focusedUserMessageID,
                        replyMode: replyMode,
                        webContext: "Die Live-Websuche ist im aktuellen Gemini-API-Zugang gerade nicht verfügbar. Sage das kurz und klar. Erfinde keine aktuellen Fakten, Termine oder Releases. Für echte Live-Recherche kann in der App ein Ollama Web Search API-Key hinterlegt werden."
                    )
                    geminiReply = try await callGemini(
                        model: model,
                        apiKey: key,
                        systemPrompt: systemPrompt,
                        input: noSearchTranscript,
                        maxOutputTokens: 720,
                        thinkingLevel: Self.geminiThinkingLevel(for: model),
                        googleSearchEnabled: false
                    )
                } else {
                    throw error
                }
            }
            if let externalWebContext, !externalWebContext.sources.isEmpty {
                guard Self.hasValidSourceMarkers(
                    geminiReply.text,
                    sourceCount: externalWebContext.sources.count
                ) else {
                    return AIReply(
                        text: "Die erzeugte Antwort war nicht sauber mit den gefundenen Quellen verknüpft und wurde deshalb verworfen.",
                        sources: externalWebContext.sources,
                        researchStatus: ResearchStatus(
                            query: externalWebContext.query,
                            resultCount: externalWebContext.resultCount,
                            fetchedPageCount: externalWebContext.fetchedPageCount,
                            mode: .ollamaSearch
                        )
                    )
                }
                return AIReply(
                    text: geminiReply.text,
                    sources: externalWebContext.sources,
                    citations: geminiReply.citations,
                    researchStatus: ResearchStatus(
                        query: externalWebContext.query,
                        resultCount: externalWebContext.resultCount,
                        fetchedPageCount: externalWebContext.fetchedPageCount,
                        mode: .ollamaSearch
                    )
                )
            }
            return geminiReply

        case .ollama:
            let model = try await resolveOllamaModel(preferred: selection.ollamaModel)
            let localTokenLimit: Int
            if responseIntent.isStructured {
                localTokenLimit = responseIntent.isResearch ? 900 : 640
            } else {
                switch replyMode {
                case .doubleText: localTokenLimit = 96
                case .directUser, .followUpUser: localTokenLimit = 220
                case .autonomous: localTokenLimit = 180
                }
            }

            return try await generateOllamaIntentReply(
                model: model,
                systemPrompt: systemPrompt,
                transcript: transcript,
                maxOutputTokens: localTokenLimit,
                temperature: responseIntent.isStructured ? 0 : Self.ollamaTemperature(from: profile.creativity),
                speaker: speaker,
                preferences: preferences,
                intent: responseIntent,
                webContext: externalWebContext
            )
        }
    }

    func refreshMemory(
        existing: ConversationMemory,
        messages: [ChatMessage],
        preferences: PreferencesSnapshot
    ) async throws -> ConversationMemory {
        guard !messages.isEmpty else { return .empty }

        let startIndex = min(max(existing.coveredMessageCount, 0), messages.count)
        let newMessages = messages.dropFirst(startIndex)
        guard !newMessages.isEmpty else { return existing }

        let newTranscript = newMessages.map { message in
            "\(Self.displayName(for: message.speaker, preferences: preferences)): \(message.text)"
        }.joined(separator: "\n")

        let oldMemory = existing.summary.isEmpty ? "Noch keine Erinnerung." : existing.summary
        let topicLine = preferences.conversationTopic.isEmpty
            ? "Kein festes Gesprächsthema."
            : "Gesprächsthema: \(preferences.conversationTopic)"

        let memoryContext = preferences.chatMode == .single
            ? "eines privaten KI-Chats mit \(preferences.alice.name) und dem Menschen"
            : "eines privaten Gruppen-Chats mit \(preferences.alice.name), \(preferences.bob.name) und dem Menschen"

        let prompt = """
        Aktualisiere die Langzeit-Erinnerung \(memoryContext).
        \(topicLine)

        Bisherige Erinnerung:
        \(oldMemory)

        Neue Nachrichten:
        \(newTranscript)

        Erstelle eine kompakte, sachliche Erinnerung für zukünftige Gesprächszüge. Bewahre wichtige Aussagen, Standpunkte, Entscheidungen, offene Fragen, persönliche Präferenzen des Menschen und erkennbare Meinungsänderungen. Entferne Belangloses und Wiederholungen. Maximal etwa 1200 Zeichen. Gib nur die aktualisierte Erinnerung aus.
        """

        // Für das Gedächtnis verwenden wir bevorzugt Alices aktiven Provider.
        let selection = preferences.aliceAI
        let result: String
        switch selection.provider {
        case .gemini:
            guard let key = KeychainStore.read(), !key.isEmpty else { throw AIServiceError.missingGeminiKey }
            let model = Self.normalizedGeminiModel(selection.geminiModel.isEmpty ? Self.recommendedGeminiModel : selection.geminiModel)
            result = try await callGemini(
                model: model,
                apiKey: key,
                systemPrompt: "Du pflegst ausschließlich eine kompakte Langzeit-Erinnerung für einen Gruppenchat.",
                input: prompt,
                maxOutputTokens: 520,
                thinkingLevel: Self.geminiThinkingLevel(for: model),
                googleSearchEnabled: false
            ).text
        case .ollama:
            let model = try await resolveOllamaModel(preferred: selection.ollamaModel)
            result = try await callOllama(
                model: model,
                systemPrompt: "Du pflegst ausschließlich eine kompakte Langzeit-Erinnerung für einen Gruppenchat.",
                transcript: prompt,
                maxOutputTokens: 520,
                temperature: 0.25,
                expectedSpeaker: nil,
                preferences: preferences
            )
        }

        return ConversationMemory(
            summary: result.trimmingCharacters(in: .whitespacesAndNewlines),
            coveredMessageCount: messages.count,
            updatedAt: Date()
        )
    }

    func testGemini(model: String, apiKey: String) async throws -> String {
        let trimmedModel = Self.normalizedGeminiModel(model)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIServiceError.missingModel }
        guard !trimmedKey.isEmpty else { throw AIServiceError.missingGeminiKey }

        return try await callGemini(
            model: trimmedModel,
            apiKey: trimmedKey,
            systemPrompt: "Du bist ein sehr kurzer Verbindungstest.",
            input: "Antworte ausschließlich mit: OK",
            maxOutputTokens: 160,
            thinkingLevel: Self.geminiThinkingLevel(for: trimmedModel),
            googleSearchEnabled: false,
            recordUsage: false
        ).text
    }

    nonisolated static func isQuotaLimitError(_ error: Error) -> Bool {
        guard let serviceError = error as? AIServiceError else { return false }
        if case .server(let status, let message) = serviceError {
            return status == 429 || message.localizedCaseInsensitiveContains("RESOURCE_EXHAUSTED")
        }
        return false
    }

    nonisolated static func isGeminiModelUnavailableError(_ error: Error) -> Bool {
        guard let serviceError = error as? AIServiceError else { return false }
        if case .server(let status, let message) = serviceError {
            let lower = message.lowercased()
            return status == 404 && (
                lower.contains("no longer available") ||
                lower.contains("not found") ||
                lower.contains("model") && lower.contains("available")
            )
        }
        return false
    }


    nonisolated private static func isGeminiSearchUnavailableError(_ error: Error) -> Bool {
        guard let serviceError = error as? AIServiceError else { return false }
        if case .server(let status, let message) = serviceError, status == 400 || status == 403 {
            let lower = message.lowercased()
            return lower.contains("google_search") ||
                   lower.contains("google search") ||
                   lower.contains("grounding") ||
                   lower.contains("paid tier") ||
                   lower.contains("billing") ||
                   lower.contains("tool")
        }
        return false
    }

    // MARK: - Usage dashboard

    func usageStatus(for provider: AIProvider) -> ProviderUsageStatus {
        let record = loadUsage(for: provider)
        let note: String?
        switch provider {
        case .gemini:
            note = "App-interner Verbrauch. Das echte Projektlimit siehst du zusätzlich in Google AI Studio."
        case .ollama:
            note = "Lokale Ollama-Nutzung aus den Antworten dieser App; lokale Modelle haben kein API-Kontingent."
        }
        return ProviderUsageStatus(
            provider: provider,
            requestsToday: record.requests,
            inputTokensToday: record.inputTokens,
            outputTokensToday: record.outputTokens,
            dateKey: record.dateKey,
            note: note
        )
    }

    func resetUsageCounters() {
        for provider in AIProvider.allCases {
            usageDefaults.removeObject(forKey: usageKey(for: provider))
        }
    }

    // MARK: - Ollama models

    func resolveOllamaModel(preferred: String) async throws -> String {
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = try await listOllamaModels()
        guard !models.isEmpty else { throw AIServiceError.noOllamaModels }

        if let exact = models.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact.name
        }

        if !trimmed.isEmpty {
            let preferredBase = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            if let compatible = models.first(where: { model in
                let modelBase = model.name.split(separator: ":", maxSplits: 1).first.map(String.init) ?? model.name
                return modelBase.caseInsensitiveCompare(preferredBase) == .orderedSame
            }) {
                return compatible.name
            }
        }

        return models[0].name
    }

    func listOllamaModels() async throws -> [OllamaModel] {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { throw AIServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.requestTimedOut
        }
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.server(status: http.statusCode, message: Self.errorText(from: data))
        }

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models
            .filter {
                let lower = $0.name.lowercased()
                return !lower.contains(":cloud") &&
                       !lower.contains("embed") &&
                       !lower.contains("embedding") &&
                       !lower.contains("bge-") &&
                       !lower.contains("nomic-embed")
            }
            .map {
                OllamaModel(
                    id: $0.name,
                    name: $0.name,
                    sizeBytes: $0.size,
                    parameterSize: $0.details?.parameterSize,
                    family: $0.details?.family
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func listOllamaCatalogModels() async throws -> [OllamaCatalogModel] {
        var byName: [String: OllamaCatalogModel] = [:]

        // Öffentlicher Ollama-Katalog. In v18 übernehmen wir daraus bewusst nur lokale/downloadbare Modelle.
        if let url = URL(string: "https://ollama.com/api/tags") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let decoded = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data) {
                for model in decoded.models where !model.name.lowercased().contains(":cloud") {
                    let info = Self.ollamaCatalogInfo(for: model.name)
                    byName[model.name.lowercased()] = OllamaCatalogModel(
                        id: model.name,
                        name: model.name,
                        sizeBytes: model.size,
                        specialization: info.specialization,
                        summary: info.summary
                    )
                }
            }
        }

        // Cloud-Modelle bleiben in v18 ausgeblendet, weil sie je nach Ollama-Account ein kostenpflichtiges Abo verlangen.

        // Kleine, sinnvolle lokale Basis-Auswahl. So bleibt der Katalog auch dann nützlich,
        // wenn der öffentliche Ollama-Endpunkt gerade keine vollständige Library-Liste liefert.
        for name in Self.curatedOllamaLocalModelNames where byName[name.lowercased()] == nil {
            let info = Self.ollamaCatalogInfo(for: name)
            byName[name.lowercased()] = OllamaCatalogModel(
                id: name,
                name: name,
                sizeBytes: nil,
                specialization: info.specialization,
                summary: info.summary
            )
        }

        // Bereits lokal installierte Modelle ebenfalls in den Katalog aufnehmen, auch wenn der
        // öffentliche Katalog gerade nicht erreichbar ist.
        if let local = try? await listOllamaModels() {
            for model in local where byName[model.name.lowercased()] == nil {
                let info = Self.ollamaCatalogInfo(for: model.name)
                byName[model.name.lowercased()] = OllamaCatalogModel(
                    id: model.name,
                    name: model.name,
                    sizeBytes: nil,
                    specialization: info.specialization,
                    summary: info.summary
                )
            }
        }

        let result = Array(byName.values)
            .filter { !$0.isCloud }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !result.isEmpty else { throw AIServiceError.badResponse }
        return result
    }

    func pullOllamaModel(
        _ rawName: String,
        onProgress: (@Sendable (OllamaPullProgress) -> Void)? = nil
    ) async throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AIServiceError.missingModel }

        if name.lowercased().contains(":cloud") {
            throw AIServiceError.server(status: 403, message: "Ollama-Cloud-Modelle sind in dieser App-Version ausgeblendet, weil sie je nach Account ein kostenpflichtiges Abo erfordern. Bitte wähle ein lokales Modell.")
        }

        guard let url = URL(string: "http://127.0.0.1:11434/api/pull") else { throw AIServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 * 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaPullRequest(model: name, stream: true))

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIServiceError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw AIServiceError.server(status: http.statusCode, message: "Ollama-Download konnte nicht gestartet werden.")
            }

            var finalStatus = ""
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let progress = try? JSONDecoder().decode(OllamaPullResponse.self, from: data) else { continue }
                if let error = progress.error, !error.isEmpty {
                    throw AIServiceError.server(status: http.statusCode, message: error)
                }
                finalStatus = progress.status
                onProgress?(OllamaPullProgress(
                    status: progress.status,
                    completed: progress.completed,
                    total: progress.total
                ))
            }
            guard finalStatus.localizedCaseInsensitiveContains("success") else {
                throw AIServiceError.server(status: http.statusCode, message: finalStatus.isEmpty ? "Unvollständiger Download" : finalStatus)
            }
            return name
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.requestTimedOut
        }
    }

    func checkOllamaHealth() async throws -> String {
        let models = try await listOllamaModels()
        return "Ollama erreichbar · \(models.count) lokale Modell(e)"
    }

    // MARK: - Gemini Interactions API

    private func callGemini(
        model: String,
        apiKey: String,
        systemPrompt: String,
        input: String,
        maxOutputTokens: Int,
        thinkingLevel: String,
        googleSearchEnabled: Bool,
        recordUsage shouldRecordUsage: Bool = true
    ) async throws -> AIReply {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body = GeminiInteractionRequest(
            model: model,
            input: input,
            systemInstruction: systemPrompt,
            stream: false,
            store: false,
            tools: googleSearchEnabled ? [GeminiTool(type: "google_search")] : nil,
            generationConfig: .init(
                maxOutputTokens: maxOutputTokens,
                thinkingLevel: Self.supportsThinkingLevel(model) ? thinkingLevel : nil,
                thinkingSummaries: nil
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.requestTimedOut
        }
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.server(status: http.statusCode, message: Self.errorText(from: data))
        }

        let decoded = try JSONDecoder().decode(GeminiInteractionResponse.self, from: data)
        let contents = decoded.steps
            .filter { $0.type == "model_output" }
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "text" }

        var text = ""
        var sourceByURL: [String: WebSource] = [:]
        var sourceOrder: [String] = []
        var citationDrafts: [(source: WebSource, start: Int?, end: Int?)] = []

        for content in contents {
            guard let part = content.text else { continue }
            if !text.isEmpty { text.append("\n") }
            let baseOffset = text.utf8.count
            text.append(part)

            for annotation in content.annotations ?? [] where annotation.type == "url_citation" {
                guard let rawURL = annotation.url, !rawURL.isEmpty else { continue }
                let source: WebSource
                if let existing = sourceByURL[rawURL] {
                    source = existing
                } else {
                    source = WebSource(
                        title: annotation.title?.isEmpty == false ? annotation.title! : Self.hostName(from: rawURL),
                        url: rawURL
                    )
                    sourceByURL[rawURL] = source
                    sourceOrder.append(rawURL)
                }
                citationDrafts.append((
                    source: source,
                    start: annotation.startIndex.map { baseOffset + $0 },
                    end: annotation.endIndex.map { baseOffset + $0 }
                ))
            }
        }

        let sources = sourceOrder.compactMap { sourceByURL[$0] }
        let sourceNumberByID = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.element.id, $0.offset + 1) })
        let markedText = Self.insertingCitationMarkers(
            into: text,
            citations: citationDrafts.compactMap { draft in
                guard let end = draft.end,
                      let number = sourceNumberByID[draft.source.id] else { return nil }
                return (end, number)
            }
        )
        let final = Self.clean(markedText)
        guard !final.isEmpty else { throw AIServiceError.emptyReply }

        let citations = citationDrafts.map {
            InlineCitation(
                sourceID: $0.source.id,
                startUTF8Offset: $0.start,
                endUTF8Offset: $0.end
            )
        }

        if shouldRecordUsage {
            recordUsage(
                provider: .gemini,
                inputTokens: decoded.usage?.totalInputTokens ?? 0,
                outputTokens: decoded.usage?.totalOutputTokens ?? 0
            )
        }

        return AIReply(
            text: final,
            sources: sources,
            citations: citations,
            researchStatus: googleSearchEnabled && !sources.isEmpty
                ? ResearchStatus(
                    query: "Google Search",
                    resultCount: sources.count,
                    fetchedPageCount: sources.count,
                    mode: .geminiGrounding
                )
                : nil
        )
    }

    // MARK: - Ollama

    private func callOllama(
        model: String,
        systemPrompt: String,
        transcript: String,
        maxOutputTokens: Int,
        temperature: Double,
        expectedSpeaker: ChatSpeaker?,
        preferences: PreferencesSnapshot,
        format: OllamaJSONSchema = .singleMessageSchema,
        unwrapStructuredEnvelope: Bool = true,
        contextLength: Int? = nil
    ) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else { throw AIServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Local models should fail visibly instead of keeping the UI in an
        // endless-looking wait. Research gets a little more time than chat.
        request.timeoutInterval = (contextLength ?? 0) > 8_192 ? 90 : 55
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaChatRequest(
            model: model,
            messages: [
                .init(
                    role: "system",
                    content: systemPrompt + "\n\nWICHTIG FÜR OLLAMA: Erzeuge genau EINE Nachricht des erwarteten Teilnehmers. Simuliere niemals einen Dialog und schreibe niemals weitere Sprecher wie Alice:, Bob: oder Du:. Wenn der Nutzer Deutsch schreibt, antworte in sauberem, idiomatischem Deutsch mit natürlicher Wortstellung. Übersetze keine englischen Redewendungen wörtlich und erfinde keine persönliche Erfahrung oder Unsicherheit, wenn eine sachliche Antwort möglich ist."
                ),
                .init(role: "user", content: transcript)
            ],
            stream: false,
            // Qwen 3.5 enables a reasoning channel by default. With a constrained
            // output budget it can spend every token there and return empty visible
            // content. The app validates rich output itself, so disable hidden thinking.
            think: OllamaRuntimePolicy.allowsHiddenThinking,
            format: format,
            options: .init(
                numPredict: maxOutputTokens,
                temperature: temperature,
                stop: Self.ollamaStopSequences(preferences: preferences),
                numCtx: contextLength
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.requestTimedOut
        }
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.server(status: http.statusCode, message: Self.errorText(from: data))
        }

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let rawContent = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        let structuredText = unwrapStructuredEnvelope
            ? Self.unwrapOllamaStructuredReply(rawContent)
            : Self.unwrapMarkdownJSON(rawContent)

        let final: String
        if expectedSpeaker == nil {
            final = structuredText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            final = Self.cleanSingleSpeakerReply(
                structuredText,
                expectedSpeaker: expectedSpeaker,
                preferences: preferences
            )
        }
        guard !final.isEmpty else { throw AIServiceError.emptyReply }

        recordUsage(
            provider: .ollama,
            inputTokens: decoded.promptEvalCount ?? 0,
            outputTokens: decoded.evalCount ?? 0
        )
        return final
    }

    private func generateOllamaIntentReply(
        model: String,
        systemPrompt: String,
        transcript: String,
        maxOutputTokens: Int,
        temperature: Double,
        speaker: ChatSpeaker,
        preferences: PreferencesSnapshot,
        intent: ResponseIntent,
        webContext: WebContext?
    ) async throws -> AIReply {
        switch intent {
        case .plain, .coloredText:
            let reply = try await callOllama(
                model: model,
                systemPrompt: systemPrompt,
                transcript: transcript,
                maxOutputTokens: maxOutputTokens,
                temperature: temperature,
                expectedSpeaker: speaker,
                preferences: preferences
            )
            return AIReply(text: reply)

        case .table:
            let raw = try await callOllama(
                model: model,
                systemPrompt: systemPrompt,
                transcript: transcript + "\nAntworte im vorgegebenen Tabellenschema. intro und note dürfen leer sein.",
                maxOutputTokens: maxOutputTokens,
                temperature: 0,
                expectedSpeaker: nil,
                preferences: preferences,
                format: .tableSchema,
                unwrapStructuredEnvelope: false,
                contextLength: 8_192
            )
            guard let data = raw.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(OllamaTableEnvelope.self, from: data),
                  let text = envelope.canonicalText() else { throw AIServiceError.emptyReply }
            return AIReply(text: text)

        case .chart:
            let raw = try await callOllama(
                model: model,
                systemPrompt: systemPrompt,
                transcript: transcript + "\nAntworte im vorgegebenen Diagrammschema. Nutze nur vorhandene Zahlen; intro und note dürfen leer sein.",
                maxOutputTokens: maxOutputTokens,
                temperature: 0,
                expectedSpeaker: nil,
                preferences: preferences,
                format: .chartSchema,
                unwrapStructuredEnvelope: false,
                contextLength: 8_192
            )
            guard let data = raw.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(OllamaChartEnvelope.self, from: data),
                  let text = envelope.canonicalText() else { throw AIServiceError.emptyReply }
            return AIReply(text: text)

        case .research(let presentation):
            guard let webContext, !webContext.evidence.isEmpty else {
                return AIReply(
                    text: "Die Recherche hat keine belastbaren Inhalte geliefert. Ich zeige deshalb keine unbelegten Aussagen an.",
                    researchStatus: ResearchStatus(
                        query: webContext?.query ?? "",
                        resultCount: 0,
                        fetchedPageCount: 0,
                        mode: .unavailable
                    )
                )
            }

            let researchInstruction = """
            Antworte ausschließlich als JSON im vorgegebenen claims-Schema. Jede claim braucht mindestens einen evidence-Eintrag. source_id ist die Zahl aus [S1], [S2] usw. quote muss ein kurzes, wörtlich im jeweiligen INHALT vorkommendes Textstück sein. Keine Einleitung außerhalb des JSON. Erfinde nichts.
            """
            var validated: ValidatedResearchAnswer?
            for attempt in 0..<2 where validated == nil {
                let repair = attempt == 0 ? "" : "\nDer vorige Versuch war nicht belegbar. Korrigiere Quellen-IDs und verwende ausschließlich exakte Zitate aus INHALT."
                let raw = try await callOllama(
                    model: model,
                    systemPrompt: systemPrompt,
                    transcript: transcript + "\n" + researchInstruction + repair,
                    maxOutputTokens: maxOutputTokens,
                    temperature: 0,
                    expectedSpeaker: nil,
                    preferences: preferences,
                    format: .researchSchema,
                    unwrapStructuredEnvelope: false,
                    contextLength: 16_384
                )
                if let data = raw.data(using: .utf8),
                   let envelope = try? JSONDecoder().decode(OllamaResearchEnvelope.self, from: data) {
                    validated = ResearchAnswerValidator.validate(envelope, evidence: webContext.evidence)
                }
            }

            guard let answer = validated else {
                return AIReply(
                    text: "Die gefundenen Quellen ließen sich nicht sicher mit der erzeugten Antwort verknüpfen. Deshalb wurde die unbelegte Antwort verworfen.",
                    sources: webContext.sources,
                    researchStatus: ResearchStatus(
                        query: webContext.query,
                        resultCount: webContext.resultCount,
                        fetchedPageCount: webContext.fetchedPageCount,
                        mode: .ollamaSearch
                    )
                )
            }

            let renderedText: String
            switch presentation {
            case .text:
                renderedText = answer.text
            case .chart:
                renderedText = answer.canonicalChartText() ?? answer.text
            case .table:
                let rows = answer.text.components(separatedBy: "\n\n").map {
                    "| " + $0.replacingOccurrences(of: "|", with: "\\|") + " |"
                }.joined(separator: "\n")
                renderedText = "| Belegte Aussage |\n| --- |\n" + rows
            }
            return AIReply(
                text: renderedText,
                sources: answer.sources,
                citations: answer.citations,
                researchStatus: ResearchStatus(
                    query: webContext.query,
                    resultCount: webContext.resultCount,
                    fetchedPageCount: webContext.fetchedPageCount,
                    mode: .ollamaSearch
                )
            )
        }
    }

    // MARK: - Web context for Ollama

    private struct WebContext: Sendable {
        let text: String
        let sources: [WebSource]
        let evidence: [ResearchEvidence]
        let query: String
        let resultCount: Int
        let fetchedPageCount: Int
    }

    func testOllamaWebSearch(apiKey: String) async throws -> Int {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingOllamaWebSearchKey }
        let context = try await fetchOllamaWebContext(for: "Ollama", apiKey: key)
        return context?.sources.count ?? 0
    }

    private func fetchOllamaWebContext(for query: String, apiKey: String) async throws -> WebContext? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: "https://ollama.com/api/web_search") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(OllamaWebSearchRequest(query: trimmed, maxResults: 5))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.requestTimedOut
        }
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.server(status: http.statusCode, message: Self.errorText(from: data))
        }

        let decoded = try JSONDecoder().decode(OllamaWebSearchResponse.self, from: data)
        guard !decoded.results.isEmpty else { return nil }

        var seenURLs = Set<String>()
        let results = decoded.results.filter { seenURLs.insert($0.url).inserted }.prefix(5)
        guard !results.isEmpty else { return nil }

        let indexedResults = Array(results.enumerated())
        let fetched = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, result) in indexedResults.prefix(3) {
                group.addTask {
                    let content = await Self.fetchOllamaWebPage(url: result.url, apiKey: apiKey)
                    return (index, content)
                }
            }
            var pages: [Int: String] = [:]
            for await (index, content) in group {
                if let content, !content.isEmpty { pages[index] = content }
            }
            return pages
        }

        var sources: [WebSource] = []
        var evidence: [ResearchEvidence] = []
        var contextParts: [String] = []
        for (index, result) in indexedResults {
            let source = WebSource(title: result.title, url: result.url)
            let rawEvidence = fetched[index] ?? result.content
            let bounded = String(rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
            sources.append(source)
            evidence.append(ResearchEvidence(sourceNumber: index + 1, source: source, content: bounded))
            contextParts.append("""
            [S\(index + 1)] \(result.title)
            URL: \(result.url)
            INHALT: \(bounded)
            """)
        }

        return WebContext(
            text: contextParts.joined(separator: "\n\n"),
            sources: sources,
            evidence: evidence,
            query: trimmed,
            resultCount: indexedResults.count,
            fetchedPageCount: fetched.count
        )
    }

    nonisolated private static func fetchOllamaWebPage(url rawURL: String, apiKey: String) async -> String? {
        guard let endpoint = URL(string: "https://ollama.com/api/web_fetch") else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(OllamaWebFetchRequest(url: rawURL))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(OllamaWebFetchResponse.self, from: data) else {
            return nil
        }
        return decoded.content
    }

    // MARK: - Prompting

    private static func systemPrompt(
        for speaker: ChatSpeaker,
        preferences: PreferencesSnapshot,
        memory: ConversationMemory
    ) -> String {
        let profile = preferences.profile(for: speaker)
        let other = preferences.profile(for: speaker.otherAI)
        let topicSection = preferences.conversationTopic.isEmpty
            ? "Es gibt kein festes Thema. Entwickle das Gespräch organisch."
            : "Aktuelles Gesprächsthema: \(preferences.conversationTopic)"
        let memorySection = memory.summary.isEmpty
            ? "Es gibt noch keine verdichtete Langzeit-Erinnerung."
            : """
              Langzeit-Erinnerung aus früheren Nachrichten:
              \(memory.summary)
              Nutze sie nur, wenn sie relevant ist. Behandle sie als Kontext, nicht als Text zum Wiederholen.
              """

        let conversationRole: String
        let identitySection: String
        if preferences.chatMode == .single {
            let selection = preferences.aiSelection(for: speaker)
            let modelName = selection.activeModel.isEmpty ? selection.provider.displayName : selection.activeModel
            conversationRole = "Du bist ein KI-Assistent in einem normalen privaten Chat mit einem Menschen. Es gibt in diesem Modus keinen zweiten KI-Teilnehmer. Antworte direkt, hilfreich und natürlich."
            identitySection = """
            Deine sichtbare Identität in diesem Chat:
            - Anbieter: \(selection.provider.displayName)
            - Modell: \(modelName)
            - Verwende NICHT den Namen Alice oder Bob. Wenn du nach deinem Namen oder Modell gefragt wirst, nenne den Anbieter bzw. das Modell oben.
            - Bevorzugte Sprache: \(profile.preferredLanguage)
            """
        } else {
            conversationRole = "Du bist \(profile.name) in einem privaten Gruppenchat mit \(other.name) und einem Menschen."
            identitySection = """
            Dein Profil:
            - Name: \(profile.name)
            - Rolle: \(profile.role.isEmpty ? "Eigenständiger Gesprächspartner" : profile.role)
            - Persönlichkeit: \(profile.personality.isEmpty ? "Natürlich, eigenständig und glaubwürdig." : profile.personality)
            - Kreativität: \(creativityDescription(profile.creativity))
            - Bevorzugte Sprache: \(profile.preferredLanguage)
            """
        }

        return """
        \(conversationRole)

        \(identitySection)

        \(topicSection)
        \(memorySection)

        Verhalte dich natürlich und eigenständig. Im Gruppenmodus bist du ein echter Teilnehmer mit eigener Position; im KI-Chat-Modus antwortest du direkt und hilfreich auf den Menschen, ohne so zu tun, als gäbe es einen zweiten KI-Teilnehmer. Greife konkrete Aussagen auf und ignoriere den Menschen niemals.

        Stilregeln:
        - Schreibe nur die eigentliche Antwort ohne Namenspräfix oder Rollenlabel.
        - Schreibe in natürlichem, idiomatischem Hochdeutsch. Vermeide holprige Übersetzungen, unnötige Anglizismen und Formulierungen wie „ich habe nicht viel Erfahrung“, wenn du stattdessen sachlich antworten kannst.
        - Wenn aktueller Web-Kontext bereitgestellt wurde, nutze ihn konkret und widersprich ihm nicht ohne guten Grund. Fasse Web-Inhalte in natürlichem Deutsch zusammen; kopiere keine README-Dateien, Rohdaten, JSON, escaped \n-Sequenzen oder Suchmaschinen-Snippets in die Antwort, außer der Nutzer verlangt ausdrücklich Rohdaten oder Code. Wenn keine Live-Daten verfügbar sind, erfinde keine aktuellen Nachrichten, Releases oder Termine.
        - Wenn der Nutzer ausdrücklich farbige Hervorhebungen möchte, darfst du ausschließlich diese sicheren Tags benutzen: [red]...[/red], [green]...[/green], [blue]...[/blue], [yellow]...[/yellow], [purple]...[/purple], [mark]...[/mark]. Verwende keine HTML-Tags.
        - Wenn der Nutzer ausdrücklich ein Diagramm möchte, darfst du einen ```mermaid```-Codeblock ausgeben. Wenn er ein Diagramm/Chart aus Zahlen möchte, darfst du einen ```chart```-Codeblock mit reinem Chart.js-kompatiblem JSON ausgeben. Keine ausführbaren JavaScript-Funktionen in Chart-Konfigurationen.
        - Passe die Länge an die Situation an: einfache Chat-Reaktionen meist 1 kurzer Satz, normale Antworten 1 bis 3 Sätze, komplexe Fragen nur bei Bedarf länger.
        - Im Doppeltext-Modus 1 bis 2 kurze Sätze.
        - Keine Listen oder Überschriften, außer sie sind ausdrücklich sinnvoll.
        - Nicht jede Nachricht muss mit einer Frage enden.
        - Wiederhole nicht einfach die letzte Nachricht.
        - Simuliere niemals die anderen Teilnehmer. Deine Ausgabe enthält genau eine einzelne Nachricht von dir selbst.
        - Schreibe vollständig und brich niemals mitten im Satz ab.
        """
    }

    private static func transcriptPrompt(
        nextSpeaker: ChatSpeaker,
        messages: [ChatMessage],
        preferences: PreferencesSnapshot,
        focusedUserMessageID: UUID?,
        replyMode: ReplyMode,
        webContext: String?,
        responseIntent: ResponseIntent = .plain
    ) -> String {
        let transcript = PromptBudget.boundedTranscript(
            messages: messages,
            preferences: preferences
        )

        let nextName = displayName(for: nextSpeaker, preferences: preferences)
        let focusedMessage = focusedUserMessageID.flatMap { id in
            messages.first(where: { $0.id == id && $0.speaker == .user })
        }

        let instruction: String
        switch replyMode {
        case .autonomous:
            if preferences.chatMode == .single {
                instruction = "Antworte als \(nextName) kurz und natürlich auf den letzten menschlichen Gedanken. Erfinde keinen zweiten KI-Teilnehmer."
            } else {
                instruction = "Die beiden KI-Teilnehmer führen das Gespräch selbstständig weiter. Schreibe die nächste natürliche Nachricht von \(nextName) und entwickle den letzten relevanten Gedanken weiter."
            }
        case .directUser:
            instruction = "WICHTIG: Der Mensch hat gerade geschrieben: „\(focusedMessage?.text ?? "")“\nAntworte als \(nextName) zuerst direkt und konkret auf diese Nachricht."
        case .followUpUser:
            if preferences.chatMode == .single {
                instruction = "Der Mensch hat gerade geschrieben: „\(focusedMessage?.text ?? "")“\nAntworte als \(nextName) direkt darauf. Es gibt keinen zweiten KI-Teilnehmer."
            } else {
                instruction = "Der Mensch hat gerade geschrieben: „\(focusedMessage?.text ?? "")“\nDie andere KI hat bereits reagiert. Reagiere als \(nextName) auf den Menschen UND auf die unmittelbar vorherige KI-Antwort und bringe einen eigenen Gedanken ein."
            }
        case .doubleText:
            instruction = "Du hast gerade selbst geschrieben. Sende als \(nextName) eine kurze zweite Nachricht direkt hinterher, die den Gedanken sinnvoll ergänzt."
        }

        let webSection: String
        if let webContext, !webContext.isEmpty {
            webSection = """
            Zusätzlicher Internet-Kontext:
            \(webContext)
            Nutze ihn nur, wenn er relevant ist. Antworte daraus in eigenem, natürlichem Deutsch und fasse die relevanten Fakten zusammen. Gib niemals den Suchkontext als Rohtext, JSON, Dateiinhalt oder kopierte README-Passage aus, außer der Nutzer verlangt ausdrücklich den Originaltext. Behaupte bei unsicheren Informationen nichts als sichere Tatsache.
            """
        } else {
            webSection = ""
        }

        let transcriptTitle = preferences.chatMode == .single ? "Aktueller KI-Chat:" : "Aktueller Gruppenchat:"
        let formatInstruction = Self.formatInstruction(for: responseIntent)

        return """
        \(transcriptTitle)
        \(transcript)

        \(webSection)

        \(instruction)

        \(formatInstruction)

        Gib ausschließlich den vollständigen Nachrichtentext von \(nextName) aus.
        """
    }

    private static func formatInstruction(for intent: ResponseIntent) -> String {
        switch intent {
        case .plain:
            return ""
        case .coloredText:
            return "Nutze die angeforderten sicheren Farbtags exakt und schließe jeden geöffneten Tag."
        case .table:
            return "Erzeuge eine echte Tabelle mit klaren Spalten und konsistenten Zeilen. Erfinde keine fehlenden Daten; frage stattdessen nach."
        case .chart:
            return "Erzeuge ein Diagramm ausschließlich aus tatsächlich vorhandenen Zahlen. Erfinde keine Datenpunkte."
        case .research(let presentation):
            let presentationRule: String
            switch presentation {
            case .text: presentationRule = "Formuliere kurze, einzelne belegbare Aussagen."
            case .table: presentationRule = "Ordne die belegten Fakten tabellarisch; jede Datenzeile muss auf Quellen verweisen."
            case .chart: presentationRule = "Nutze nur belegte Zahlen für das gewünschte Diagramm."
            }
            return """
            STRENGER RECHERCHEMODUS: Verwende ausschließlich den bereitgestellten Internet-Kontext. Keine eigenen Erinnerungen, Vermutungen, persönlichen Erfahrungen oder Behauptungen über eingesetzte Werkzeuge. Jede Tatsachenbehauptung braucht unmittelbar eine Quellenmarke wie [S1]. Wenn die Quellen etwas nicht belegen, sage genau das. \(presentationRule)
            """
        }
    }

    private static func searchQuery(
        messages: [ChatMessage],
        focusedUserMessageID: UUID?,
        replyMode: ReplyMode
    ) -> String? {
        guard replyMode == .directUser || replyMode == .followUpUser,
              let id = focusedUserMessageID,
              let index = messages.firstIndex(where: { $0.id == id && $0.speaker == .user }) else {
            return nil
        }

        let current = messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return nil }

        // Follow-up commands such as "schau im Internet nach" need the previous subject,
        // otherwise a search engine would only receive the generic command itself.
        let lower = current.lowercased()
        let genericSearchCommand = current.count < 55 && (
            lower.contains("internet") || lower.contains("web") ||
            lower.contains("such") || lower.contains("recherch") || lower.contains("nachschau")
        )

        if genericSearchCommand, index > 0,
           let previousUser = messages[..<index].reversed().first(where: { $0.speaker == .user }) {
            let previous = previousUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !previous.isEmpty {
                return previous + " — " + current
            }
        }

        return current
    }

    // MARK: - Usage persistence

    private func recordUsage(provider: AIProvider, inputTokens: Int, outputTokens: Int) {
        var record = loadUsage(for: provider)
        record.requests += 1
        record.inputTokens += max(0, inputTokens)
        record.outputTokens += max(0, outputTokens)
        if let data = try? JSONEncoder().encode(record) {
            usageDefaults.set(data, forKey: usageKey(for: provider))
        }
    }

    private func loadUsage(for provider: AIProvider) -> UsageRecord {
        let today = Self.todayKey()
        if let data = usageDefaults.data(forKey: usageKey(for: provider)),
           let decoded = try? JSONDecoder().decode(UsageRecord.self, from: data),
           decoded.dateKey == today {
            return decoded
        }
        return UsageRecord(dateKey: today, requests: 0, inputTokens: 0, outputTokens: 0)
    }

    private func usageKey(for provider: AIProvider) -> String {
        "AutonomousAIChat.v13.usage.\(provider.rawValue)"
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Helpers

    private static func shouldUseWebSearch(_ query: String) -> Bool {
        let lower = query.lowercased()
        let markers = [
            "internet", "web", "suche", "such nach", "nachschauen", "nachsehen",
            "aktuell", "aktuelle", "aktuellen", "neueste", "neuestes", "heute", "gerade",
            "news", "release", "veröffentlicht", "preis", "wann kommt", "stand 2026"
        ]
        return markers.contains { lower.contains($0) }
    }

    static func displayName(for speaker: ChatSpeaker, preferences: PreferencesSnapshot) -> String {
        if preferences.chatMode == .single, speaker == .alice {
            let selection = preferences.aliceAI
            return selection.activeModel.isEmpty ? selection.provider.displayName : selection.activeModel
        }
        switch speaker {
        case .alice: return preferences.alice.name
        case .bob: return preferences.bob.name
        case .user: return "Du"
        }
    }

    private static func creativityDescription(_ value: Double) -> String {
        switch value {
        case ..<0.34: return "niedrig – eher nüchtern, fokussiert und vorhersehbar"
        case ..<0.67: return "mittel – ausgewogen zwischen Präzision und neuen Ideen"
        default: return "hoch – experimentierfreudig und assoziativ, aber weiterhin sinnvoll"
        }
    }

    private static func ollamaTemperature(from creativity: Double) -> Double {
        0.25 + min(max(creativity, 0), 1) * 0.75
    }

    private static func normalizedGeminiModel(_ raw: String) -> String {
        var model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.lowercased().hasPrefix("models/") {
            model = String(model.dropFirst("models/".count))
        }
        return model
    }

    private static func geminiThinkingLevel(for model: String) -> String {
        // `minimal` is not supported by Gemini 3.1 Pro Preview. `low` is supported
        // across the Gemini 3 chat models we expose and is a good low-latency default.
        "low"
    }

    private static func supportsThinkingLevel(_ model: String) -> Bool {
        model.lowercased().hasPrefix("gemini-3")
    }

    private static func ollamaStopSequences(preferences: PreferencesSnapshot) -> [String] {
        let names = [preferences.alice.name, preferences.bob.name, "Du", "User", "Human"]
        return names.flatMap { ["\n\($0):", "\n\($0) :"] }
    }

    static func unwrapOllamaStructuredReply(_ raw: String) -> String {
        let candidate = unwrapMarkdownJSON(raw)
        guard !candidate.isEmpty else { return "" }

        if let data = candidate.data(using: .utf8) {
            if let envelope = try? JSONDecoder().decode(OllamaSingleReplyEnvelope.self, from: data) {
                return envelope.message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["message"] as? String {
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Defensive Fallback für fast-korrekte Antworten wie {"message":"..."}, bei denen
        // das Modell außen noch Text ergänzt hat. Nur die Envelope wird entfernt; echter
        // JSON-Code innerhalb von `message` bleibt erhalten.
        if let start = candidate.range(of: "{\"message\"")?.lowerBound,
           let end = candidate.lastIndex(of: "}") {
            let possibleJSON = String(candidate[start...end])
            if let data = possibleJSON.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(OllamaSingleReplyEnvelope.self, from: data) {
                return envelope.message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Never render an incomplete JSON envelope as chat text. Qwen can hit
        // num_predict in the middle of a long value; raw JSON then creates a
        // huge unbroken Text view and can overwhelm dynamic glass rendering.
        if candidate.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return ""
        }
        return candidate
    }

    private static func unwrapMarkdownJSON(_ raw: String) -> String {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```") {
            let lines = candidate.components(separatedBy: .newlines)
            if lines.count >= 3,
               lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                candidate = lines.dropFirst().dropLast().joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return candidate
    }

    private static func cleanSingleSpeakerReply(
        _ text: String,
        expectedSpeaker: ChatSpeaker?,
        preferences: PreferencesSnapshot
    ) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let allSpeakerNames = [preferences.alice.name, preferences.bob.name, "Du", "User", "Human"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let expectedSpeaker {
            let ownName = displayName(for: expectedSpeaker, preferences: preferences)
            for prefix in ["\(ownName):", "\(ownName) :"] {
                if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                    cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        let lines = cleaned.components(separatedBy: .newlines)
        var kept: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let beginsWithSpeaker = allSpeakerNames.contains { name in
                trimmed.lowercased().hasPrefix("\(name.lowercased()):") ||
                trimmed.lowercased().hasPrefix("\(name.lowercased()) :")
            }
            if beginsWithSpeaker && !kept.isEmpty { break }
            kept.append(line)
        }
        return clean(kept.joined(separator: "\n"))
    }

    private static func clean(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Alice:", "Bob:", "Alice :", "Bob :"] {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return cleaned
    }

    private static func uniqueSources(_ sources: [WebSource]) -> [WebSource] {
        var seen = Set<String>()
        var result: [WebSource] = []
        for source in sources where seen.insert(source.url).inserted {
            result.append(source)
        }
        return Array(result.prefix(6))
    }

    private static func insertingCitationMarkers(
        into text: String,
        citations: [(endUTF8Offset: Int, sourceNumber: Int)]
    ) -> String {
        let grouped = Dictionary(grouping: citations, by: \.endUTF8Offset)
        var result = text
        for offset in grouped.keys.sorted(by: >) {
            guard offset >= 0,
                  offset <= result.utf8.count,
                  let utf8Index = result.utf8.index(
                    result.utf8.startIndex,
                    offsetBy: offset,
                    limitedBy: result.utf8.endIndex
                  ),
                  let stringIndex = String.Index(utf8Index, within: result) else { continue }
            let numbers = Set(grouped[offset, default: []].map(\.sourceNumber)).sorted()
            let markers = numbers.map { "[S\($0)]" }.joined()
            result.insert(contentsOf: " " + markers, at: stringIndex)
        }
        return result
    }

    private static func hasValidSourceMarkers(_ text: String, sourceCount: Int) -> Bool {
        guard sourceCount > 0,
              let regex = try? NSRegularExpression(pattern: "\\[S([0-9]+)\\]", options: [.caseInsensitive]) else {
            return false
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return false }
        let identifiers = matches.compactMap { match -> Int? in
            guard match.range(at: 1).location != NSNotFound else { return nil }
            return Int(ns.substring(with: match.range(at: 1)))
        }
        guard identifiers.count == matches.count,
              identifiers.allSatisfy({ (1...sourceCount).contains($0) }) else { return false }

        let substantialParagraphs = text.components(separatedBy: "\n\n").filter { paragraph in
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 24 && !trimmed.hasPrefix("```")
        }
        return substantialParagraphs.allSatisfy { paragraph in
            regex.firstMatch(
                in: paragraph,
                range: NSRange(location: 0, length: (paragraph as NSString).length)
            ) != nil
        }
    }

    private static func hostName(from rawURL: String) -> String {
        URL(string: rawURL)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Quelle"
    }

    private static let curatedOllamaLocalModelNames: [String] = [
        "qwen3.5:4b",
        "qwen3.5:9b",
        "qwen3.5:27b",
        "qwen3.5:35b",
        "gemma4:e2b",
        "gemma4:e4b",
        "gemma4:12b",
        "qwen3:4b",
        "qwen3:8b",
        "deepseek-r1:7b",
        "deepseek-r1:8b",
        "llama3.2:3b",
        "llama3.1:8b",
        "mistral:7b",
        "gemma3:4b",
        "phi4:14b"
    ]

    private static func ollamaCatalogInfo(for rawName: String) -> (specialization: String, summary: String) {
        let name = rawName.lowercased()
        if name.contains("embed") || name.contains("embedding") || name.contains("bge-") {
            return ("Embeddings", "Für semantische Suche und Vektoren; nicht als normaler Chat-Teilnehmer gedacht.")
        }
        if name.contains("coder") || name.contains("code") || name.contains("devstral") || name.contains("codestral") || name.contains("starcoder") || name.contains("deepcoder") {
            return ("Programmieren", "Auf Code, Debugging und technische Aufgaben spezialisiert.")
        }
        if name.contains("vl") || name.contains("vision") || name.contains("llava") || name.contains("gemma4") {
            return ("Multimodal", "Kann je nach Variante neben Text auch Bilder oder multimodale Aufgaben verarbeiten.")
        }
        if name.contains("reason") || name.contains("r1") || name.contains("qwq") || name.contains("thinking") || name.contains("deepseek") {
            return ("Reasoning", "Für komplexeres Schlussfolgern, Analyse, Mathematik und längere Denkaufgaben.")
        }
        if name.contains("qwen") {
            return ("Allround / Coding", "Starke Allround-Familie mit guter Mehrsprachigkeit und häufig guten Coding-Fähigkeiten.")
        }
        if name.contains("mistral") || name.contains("ministral") || name.contains("mixtral") {
            return ("Allround / Mehrsprachig", "Effiziente Mehrzweckmodelle; gut für Chat, Text und häufig auch Coding.")
        }
        if name.contains("llama") {
            return ("Allround", "Meta-Llama-Familie für allgemeinen Chat, Schreiben und Wissen.")
        }
        if name.contains("gemma") {
            return ("Allround", "Google-Gemma-Familie für Chat, Reasoning und je nach Variante multimodale Aufgaben.")
        }
        if name.contains("phi") {
            return ("Kompakt", "Kompakte Modellfamilie; interessant für lokale Geräte und effiziente Aufgaben.")
        }
        if name.contains("gpt-oss") {
            return ("Reasoning / Allround", "Open-Weight-Modell für anspruchsvollere allgemeine Aufgaben, Reasoning und Coding.")
        }
        return ("Allround", "Allgemeines Ollama-Modell. Eignung und Funktionen hängen von der konkreten Variante ab.")
    }

    private static func errorText(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = object["error"] as? String, !message.isEmpty { return message }
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty { return message }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(420))
        }
        return "Unbekannter Fehler"
    }
}

// MARK: - Gemini payloads

private struct GeminiInteractionRequest: Encodable {
    let model: String
    let input: String
    let systemInstruction: String
    let stream: Bool
    let store: Bool
    let tools: [GeminiTool]?
    let generationConfig: GeminiInteractionGenerationConfig

    enum CodingKeys: String, CodingKey {
        case model, input, stream, store, tools
        case systemInstruction = "system_instruction"
        case generationConfig = "generation_config"
    }
}

private struct GeminiTool: Encodable {
    let type: String
}

private struct GeminiInteractionGenerationConfig: Encodable {
    let maxOutputTokens: Int
    let thinkingLevel: String?
    let thinkingSummaries: String?

    enum CodingKeys: String, CodingKey {
        case maxOutputTokens = "max_output_tokens"
        case thinkingLevel = "thinking_level"
        case thinkingSummaries = "thinking_summaries"
    }
}

private struct GeminiInteractionResponse: Decodable {
    let steps: [GeminiInteractionStep]
    let usage: GeminiInteractionUsage?
}

private struct GeminiInteractionUsage: Decodable {
    let totalInputTokens: Int?
    let totalOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
    }
}

private struct GeminiInteractionStep: Decodable {
    let type: String
    let content: [GeminiInteractionContent]?
}

private struct GeminiInteractionContent: Decodable {
    let type: String
    let text: String?
    let annotations: [GeminiAnnotation]?
}

private struct GeminiAnnotation: Decodable {
    let type: String
    let url: String?
    let title: String?
    let startIndex: Int?
    let endIndex: Int?

    enum CodingKeys: String, CodingKey {
        case type, url, title
        case startIndex = "start_index"
        case endIndex = "end_index"
    }
}

// MARK: - Ollama payloads

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let think: Bool
    let format: OllamaJSONSchema
    let options: OllamaOptions
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaOptions: Encodable {
    let numPredict: Int
    let temperature: Double
    let stop: [String]
    let numCtx: Int?

    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
        case numCtx = "num_ctx"
        case temperature, stop
    }
}

private indirect enum OllamaJSONSchema: Encodable, Sendable {
    case object(properties: [String: OllamaJSONSchema], required: [String])
    case array(items: OllamaJSONSchema)
    case string(allowed: [String]? = nil)
    case number

    static let singleMessageSchema: OllamaJSONSchema = .object(
        properties: ["message": .string()],
        required: ["message"]
    )

    static let tableSchema: OllamaJSONSchema = .object(
        properties: [
            "intro": .string(),
            "columns": .array(items: .string()),
            "rows": .array(items: .array(items: .string())),
            "note": .string()
        ],
        required: ["intro", "columns", "rows", "note"]
    )

    static let chartSchema: OllamaJSONSchema = .object(
        properties: [
            "intro": .string(),
            "type": .string(allowed: ["bar", "line", "area"]),
            "title": .string(),
            "seriesName": .string(),
            "labels": .array(items: .string()),
            "values": .array(items: .number),
            "note": .string()
        ],
        required: ["intro", "type", "title", "seriesName", "labels", "values", "note"]
    )

    static let researchSchema: OllamaJSONSchema = .object(
        properties: [
            "claims": .array(items: .object(
                properties: [
                    "text": .string(),
                    "evidence": .array(items: .object(
                        properties: [
                            "source_id": .number,
                            "quote": .string()
                        ],
                        required: ["source_id", "quote"]
                    ))
                ],
                required: ["text", "evidence"]
            ))
        ],
        required: ["claims"]
    )

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .object(let properties, let required):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
            try container.encode(false, forKey: .additionalProperties)
        case .array(let items):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
        case .string(let allowed):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(allowed, forKey: .allowedValues)
        case .number:
            try container.encode("number", forKey: .type)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, properties, required, items
        case additionalProperties = "additionalProperties"
        case allowedValues = "enum"
    }
}

enum OllamaRuntimePolicy {
    /// Visible, schema-constrained output is the product contract. Reasoning-only
    /// tokens stay disabled so Qwen 3.5 cannot exhaust `num_predict` before content.
    static let allowsHiddenThinking = false
}

enum PromptBudget {
    static let maximumTranscriptCharacters = 18_000
    static let maximumMessageCharacters = 2_400
    static let maximumMessages = 28

    static func boundedTranscript(
        messages: [ChatMessage],
        preferences: PreferencesSnapshot
    ) -> String {
        var lines: [String] = []
        var remaining = maximumTranscriptCharacters

        for message in messages.suffix(maximumMessages).reversed() {
            let content = String(message.text.prefix(maximumMessageCharacters))
            let line = "\(AIService.displayName(for: message.speaker, preferences: preferences)): \(content)"
            guard !line.isEmpty, remaining > 0 else { break }
            let boundedLine = String(line.prefix(remaining))
            lines.append(boundedLine)
            remaining -= boundedLine.count + 1
        }

        return lines.reversed().joined(separator: "\n")
    }
}

private struct OllamaSingleReplyEnvelope: Decodable { let message: String }

private struct OllamaChatResponse: Decodable {
    let message: OllamaMessage
    let promptEvalCount: Int?
    let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

private struct OllamaTagsResponse: Decodable { let models: [OllamaTag] }
private struct OllamaTag: Decodable {
    let name: String
    let size: Int64?
    let details: OllamaTagDetails?
}
private struct OllamaTagDetails: Decodable {
    let family: String?
    let parameterSize: String?
    enum CodingKeys: String, CodingKey {
        case family
        case parameterSize = "parameter_size"
    }
}
private struct OllamaPullRequest: Encodable { let model: String; let stream: Bool }
private struct OllamaPullResponse: Decodable {
    let status: String
    let completed: Int64?
    let total: Int64?
    let error: String?
}


// MARK: - Ollama Web Search payloads

private struct OllamaWebSearchRequest: Encodable {
    let query: String
    let maxResults: Int

    enum CodingKeys: String, CodingKey {
        case query
        case maxResults = "max_results"
    }
}

private struct OllamaWebSearchResponse: Decodable {
    let results: [OllamaWebSearchResult]
}

private struct OllamaWebSearchResult: Decodable {
    let title: String
    let url: String
    let content: String
}

private struct OllamaWebFetchRequest: Encodable {
    let url: String
}

private struct OllamaWebFetchResponse: Decodable {
    let title: String?
    let content: String
    let links: [String]?
}
