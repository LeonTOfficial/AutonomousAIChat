import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var typingSpeaker: ChatSpeaker?
    @Published private(set) var memory: ConversationMemory = .empty
    @Published private(set) var isRefreshingMemory = false
    @Published var lastError: String?
    @Published var lastErrorEventID: String?
    @Published var providerNotice: String?
    @Published var streamTick: Int = 0

    @Published private(set) var sessions: [ChatSession] = []
    @Published private(set) var selectedSessionID: UUID?

    @Published private(set) var diagnosticStatus = "Noch nicht geprüft"
    @Published private(set) var diagnosticDetails = ""
    @Published private(set) var recentDiagnosticLog = "Noch keine Diagnose-Einträge vorhanden."
    @Published private(set) var isRunningDiagnostics = false
    @Published private(set) var usageStatuses: [AIProvider: AIService.ProviderUsageStatus] = [:]

    let preferences: Preferences
    let aiService = AIService()

    private var loopTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?

    private var pendingUserMessageID: UUID?
    private var pendingUserSpeakers: [ChatSpeaker] = []
    private var userRevision = 0
    private var persistenceRevision = 0

    init(preferences: Preferences) {
        self.preferences = preferences

        if let store = ConversationStore.loadSessions(), !store.sessions.isEmpty {
            sessions = store.sessions.map { Self.removingLegacySeedMessages($0) }
            selectedSessionID = sessions.contains(where: { $0.id == store.selectedSessionID })
                ? store.selectedSessionID
                : sessions[0].id
            loadSelectedSessionIntoView()
        } else {
            let session = makeEmptySession(title: "Erster Chat", mode: .group)
            sessions = [session]
            selectedSessionID = session.id
            messages = session.messages
            memory = session.memory
            persist()
        }
    }

    deinit {
        loopTask?.cancel()
        replyTask?.cancel()
        memoryTask?.cancel()
    }

    var selectedSessionTitle: String {
        sessions.first(where: { $0.id == selectedSessionID })?.title ?? "Chat"
    }

    var providerStatus: String {
        if preferences.chatMode == .single {
            return "KI-Chat · \(preferences.chatDisplayName(for: .alice)) · \(preferences.provider(for: .alice).displayName)"
        }
        return "\(preferences.name(for: .alice)): \(preferences.provider(for: .alice).displayName) · \(preferences.model(for: .alice))  |  \(preferences.name(for: .bob)): \(preferences.provider(for: .bob).displayName) · \(preferences.model(for: .bob))"
    }

    func start() {
        guard loopTask == nil else { return }

        Task {
            _ = await DiagnosticsLogger.shared.log(
                .info,
                source: "app.chat",
                message: "Chat-Schleife gestartet",
                metadata: [
                    "alice_provider": preferences.aliceProvider.rawValue,
                    "bob_provider": preferences.bobProvider.rawValue
                ]
            )
        }

        loopTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }

            while !Task.isCancelled {
                guard let self else { return }

                if self.preferences.chatMode == .group,
                   self.preferences.autonomousEnabled,
                   !self.messages.isEmpty,
                   !self.isGenerating,
                   self.lastError == nil,
                   self.pendingUserMessageID == nil {
                    let speaker = self.nextSpeaker()
                    let succeeded = await self.generateOne(
                        speaker: speaker,
                        replyMode: .autonomous,
                        focusedUserMessageID: nil
                    )
                    if succeeded {
                        await self.maybeDoubleText(speaker: speaker)
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(max(3.0, self.preferences.interval)))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        replyTask?.cancel()
        replyTask = nil
        memoryTask?.cancel()
        memoryTask = nil
        // A stopped window must never keep a stale pending reply. Otherwise a
        // later reopen looks idle, but new messages are silently blocked.
        resetPendingState()
        isRefreshingMemory = false
    }

    // MARK: - Sessions

    func createSession() {
        if preferences.chatMode == .single {
            startFreshSingleChat()
        } else {
            createGroupSession()
        }
    }

    func createGroupSession() {
        stop()
        persistCurrentSessionIntoArray()
        preferences.chatMode = .group
        // Der 1:1-KI-Chat ist temporär und soll nicht zwischen den gespeicherten Gruppen-Chats auftauchen.
        sessions.removeAll { ($0.mode ?? .group) == .single }

        let groupCount = sessions.filter { ($0.mode ?? .group) == .group }.count
        let session = makeEmptySession(title: "Neuer Chat \(groupCount + 1)", mode: .group)
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        messages = []
        memory = .empty
        resetPendingState()
        lastError = nil
        lastErrorEventID = nil
        providerNotice = nil
        persist()
        start()
    }

    func setChatMode(_ mode: ChatMode) {
        guard mode != preferences.chatMode else { return }
        stop()
        persistCurrentSessionIntoArray()
        preferences.chatMode = mode

        switch mode {
        case .single:
            createFreshSingleSessionWithoutRestart()
        case .group:
            // KI-Chats sind bewusst temporär und werden beim Verlassen verworfen.
            sessions.removeAll { ($0.mode ?? .group) == .single }
            if let group = sessions
                .filter({ ($0.mode ?? .group) == .group })
                .sorted(by: { $0.updatedAt > $1.updatedAt })
                .first {
                selectedSessionID = group.id
                loadSelectedSessionIntoView()
            } else {
                let session = makeEmptySession(title: "Neuer Chat", mode: .group)
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
                messages = []
                memory = .empty
            }
        }

        resetPendingState()
        lastError = nil
        lastErrorEventID = nil
        providerNotice = nil
        persist()
        start()
    }

    /// KI-Chat is intentionally ephemeral: every entry starts with an empty conversation.
    func startFreshSingleChat() {
        stop()
        persistCurrentSessionIntoArray()
        preferences.chatMode = .single
        createFreshSingleSessionWithoutRestart()
        resetPendingState()
        lastError = nil
        lastErrorEventID = nil
        providerNotice = nil
        persist()
        start()
    }

    private func createFreshSingleSessionWithoutRestart() {
        sessions.removeAll { ($0.mode ?? .group) == .single }
        let session = makeEmptySession(title: "KI-Chat", mode: .single)
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        messages = []
        memory = .empty
    }

    func selectSession(_ id: UUID) {
        guard id != selectedSessionID,
              let target = sessions.first(where: { $0.id == id }) else { return }
        stop()
        persistCurrentSessionIntoArray()
        selectedSessionID = id
        preferences.chatMode = target.mode ?? .group
        loadSelectedSessionIntoView()
        resetPendingState()
        persist()
        start()
    }

    func deleteSession(_ id: UUID) {
        guard sessions.count > 1 else {
            clearConversation()
            return
        }

        let wasSelected = selectedSessionID == id
        sessions.removeAll { $0.id == id }
        if wasSelected {
            selectedSessionID = sessions.first?.id
            loadSelectedSessionIntoView()
            resetPendingState()
        }
        persist()
    }

    func clearConversation() {
        stop()
        messages = []
        memory = .empty
        resetPendingState()
        lastError = nil
        lastErrorEventID = nil
        providerNotice = nil

        if let index = selectedSessionIndex {
            sessions[index].messages = messages
            sessions[index].memory = memory
            sessions[index].updatedAt = Date()
            sessions[index].mode = preferences.chatMode
            sessions[index].title = preferences.chatMode == .single ? "KI-Chat" : "Neuer Chat"
        }
        persist()
        start()
    }

    // MARK: - Messages

    func sendUserMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let message = ChatMessage(speaker: .user, text: text)
        messages.append(message)
        updateSessionTitleIfNeeded(from: text)
        persist()

        userRevision += 1
        pendingUserMessageID = message.id
        if preferences.chatMode == .single {
            pendingUserSpeakers = [.alice]
        } else {
            let firstSpeaker = nextSpeaker()
            pendingUserSpeakers = [firstSpeaker, firstSpeaker.otherAI]
        }
        lastError = nil
        lastErrorEventID = nil

        loopTask?.cancel()
        loopTask = nil
        replyTask?.cancel()
        replyTask = nil

        scheduleHumanReplies(to: message.id)
        start()
    }

    func retryLastFailure() async {
        if let pendingUserMessageID {
            await processHumanReplies(for: pendingUserMessageID)
        } else {
            let speaker = nextSpeaker()
            let succeeded = await generateOne(speaker: speaker, replyMode: .autonomous, focusedUserMessageID: nil)
            if succeeded { await maybeDoubleText(speaker: speaker) }
        }
    }

    func generateSingleStep() {
        guard !isGenerating, pendingUserMessageID == nil, replyTask == nil else { return }
        replyTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.generateOne(
                speaker: self.nextSpeaker(),
                replyMode: .autonomous,
                focusedUserMessageID: nil
            )
            if !Task.isCancelled { self.replyTask = nil }
        }
    }

    func dismissProviderNotice() {
        providerNotice = nil
    }

    func dismissCurrentIssue() {
        providerNotice = nil
        lastError = nil
        lastErrorEventID = nil
    }

    func cancelCurrentGeneration() {
        guard isGenerating || typingSpeaker != nil else { return }

        loopTask?.cancel()
        loopTask = nil
        replyTask?.cancel()
        replyTask = nil

        // Invalidate any response that may still arrive from a cancelled network request.
        userRevision &+= 1
        pendingUserMessageID = nil
        pendingUserSpeakers.removeAll()
        isGenerating = false
        typingSpeaker = nil

        providerNotice = "Antwort wurde abgebrochen. Du kannst direkt weiterschreiben."

        Task {
            _ = await DiagnosticsLogger.shared.log(
                .info,
                source: "chat.cancel",
                message: "Laufende Antwort vom Nutzer abgebrochen"
            )
        }

        start()
    }

    func refreshMemoryNow() async {
        guard preferences.memoryEnabled, !messages.isEmpty, !isRefreshingMemory else { return }
        memoryTask?.cancel()
        memoryTask = nil
        await refreshMemory(using: messages, existing: memory, snapshot: preferences.snapshot())
    }

    private func scheduleHumanReplies(to messageID: UUID) {
        replyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            while self.isGenerating && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(70))
            }
            guard !Task.isCancelled else { return }
            await self.processHumanReplies(for: messageID)
            if self.pendingUserMessageID == nil { self.replyTask = nil }
        }
    }

    private func processHumanReplies(for messageID: UUID) async {
        while !Task.isCancelled,
              pendingUserMessageID == messageID,
              let speaker = pendingUserSpeakers.first {
            if preferences.chatMode == .single && speaker != .alice {
                pendingUserSpeakers.removeAll()
                break
            }

            let mode: ReplyMode
            if preferences.chatMode == .single {
                mode = .directUser
            } else {
                mode = pendingUserSpeakers.count >= 2 ? .directUser : .followUpUser
            }
            let succeeded = await generateOne(
                speaker: speaker,
                replyMode: mode,
                focusedUserMessageID: messageID
            )
            guard pendingUserMessageID == messageID, succeeded else { return }
            if !pendingUserSpeakers.isEmpty { pendingUserSpeakers.removeFirst() }
        }

        if pendingUserMessageID == messageID, pendingUserSpeakers.isEmpty {
            pendingUserMessageID = nil
            lastError = nil
            lastErrorEventID = nil
            scheduleMemoryRefreshIfNeeded()
        }
    }

    @discardableResult
    private func generateOne(
        speaker: ChatSpeaker,
        replyMode: ReplyMode,
        focusedUserMessageID: UUID?
    ) async -> Bool {
        guard !isGenerating else { return false }

        if let focusedUserMessageID {
            guard pendingUserMessageID == focusedUserMessageID,
                  messages.contains(where: { $0.id == focusedUserMessageID && $0.speaker == .user }) else {
                return false
            }
        } else if pendingUserMessageID != nil {
            return false
        }

        isGenerating = true
        typingSpeaker = speaker
        let revisionAtStart = userRevision
        let messageDate = Date()
        let currentMessages = messages
        let currentMemory = memory
        let originalSnapshot = preferences.snapshot()

        defer {
            typingSpeaker = nil
            isGenerating = false
        }

        do {
            if try await shouldTriggerSoftLimitFallback(speaker: speaker, snapshot: originalSnapshot) {
                _ = await activateOllamaForSpeaker(
                    speaker,
                    snapshot: originalSnapshot,
                    reason: "Gemini-Sicherheitslimit der App erreicht"
                )
            }

            let activeSnapshot = preferences.snapshot()
            let reply = try await generateWithAutomaticFallback(
                speaker: speaker,
                messages: currentMessages,
                memory: currentMemory,
                snapshot: activeSnapshot,
                replyMode: replyMode,
                focusedUserMessageID: focusedUserMessageID
            )

            try Task.checkCancellation()
            if focusedUserMessageID == nil, revisionAtStart != userRevision { return false }
            if let focusedUserMessageID, pendingUserMessageID != focusedUserMessageID { return false }

            await appendGeneratedMessage(
                speaker: speaker,
                reply: reply,
                date: messageDate,
                streamed: activeSnapshot.simulatedStreamingEnabled
            )
            lastError = nil
            lastErrorEventID = nil
            scheduleMemoryRefreshIfNeeded()
            await refreshUsageDashboard()
            return true
        } catch is CancellationError {
            return false
        } catch {
            let selection = originalSnapshot.aiSelection(for: speaker)
            let message = error.localizedDescription
            let eventID = await DiagnosticsLogger.shared.log(
                .error,
                source: "chat.generate",
                message: message,
                metadata: [
                    "provider": selection.provider.rawValue,
                    "model": selection.activeModel,
                    "speaker": speaker.rawValue,
                    "mode": replyMode.rawValue
                ]
            )
            lastErrorEventID = eventID
            lastError = message
            await refreshRecentDiagnosticLog()
            return false
        }
    }

    private func generateWithAutomaticFallback(
        speaker: ChatSpeaker,
        messages: [ChatMessage],
        memory: ConversationMemory,
        snapshot: PreferencesSnapshot,
        replyMode: ReplyMode,
        focusedUserMessageID: UUID?
    ) async throws -> AIService.AIReply {
        do {
            return try await aiService.generateReply(
                speaker: speaker,
                messages: messages,
                memory: memory,
                preferences: snapshot,
                replyMode: replyMode,
                focusedUserMessageID: focusedUserMessageID
            )
        } catch {
            let selection = snapshot.aiSelection(for: speaker)

            // Wenn Google ein Modell abschaltet, automatisch auf das aktuelle empfohlene Flash-Modell wechseln
            // und dieselbe Nachricht erneut versuchen, statt den funktionierenden API-Key als Fehler darzustellen.
            if selection.provider == .gemini,
               AIService.isGeminiModelUnavailableError(error),
               selection.geminiModel != AIService.recommendedGeminiModel {
                activateRecommendedGeminiModel(for: speaker)
                providerNotice = "\(selection.geminiModel) ist nicht mehr verfügbar – \(preferences.chatDisplayName(for: speaker)) nutzt jetzt \(AIService.recommendedGeminiModel)."
                _ = await DiagnosticsLogger.shared.log(
                    .warning,
                    source: "provider.gemini-model-migration",
                    message: "Gemini-Modell automatisch aktualisiert",
                    metadata: ["speaker": speaker.rawValue, "old_model": selection.geminiModel, "new_model": AIService.recommendedGeminiModel]
                )
                return try await aiService.generateReply(
                    speaker: speaker,
                    messages: messages,
                    memory: memory,
                    preferences: preferences.snapshot(),
                    replyMode: replyMode,
                    focusedUserMessageID: focusedUserMessageID
                )
            }

            guard selection.provider == .gemini,
                  snapshot.autoFallbackToOllama,
                  AIService.isQuotaLimitError(error),
                  await activateOllamaForSpeaker(speaker, snapshot: snapshot, reason: "Gemini-Limit erreicht") else {
                throw error
            }

            return try await aiService.generateReply(
                speaker: speaker,
                messages: messages,
                memory: memory,
                preferences: preferences.snapshot(),
                replyMode: replyMode,
                focusedUserMessageID: focusedUserMessageID
            )
        }
    }

    private func activateRecommendedGeminiModel(for speaker: ChatSpeaker) {
        switch speaker {
        case .alice:
            preferences.aliceGeminiModel = AIService.recommendedGeminiModel
            preferences.aliceProvider = .gemini
        case .bob:
            preferences.bobGeminiModel = AIService.recommendedGeminiModel
            preferences.bobProvider = .gemini
        case .user:
            break
        }
    }

    private func shouldTriggerSoftLimitFallback(
        speaker: ChatSpeaker,
        snapshot: PreferencesSnapshot
    ) async throws -> Bool {
        let selection = snapshot.aiSelection(for: speaker)
        guard snapshot.limitProtectionEnabled,
              snapshot.autoFallbackToOllama,
              selection.provider == .gemini,
              snapshot.geminiDailyRequestSoftLimit > 0 else {
            return false
        }

        let usage = await aiService.usageStatus(for: .gemini)
        return usage.requestsToday >= snapshot.geminiDailyRequestSoftLimit
    }

    @discardableResult
    private func activateOllamaForSpeaker(
        _ speaker: ChatSpeaker,
        snapshot: PreferencesSnapshot,
        reason: String
    ) async -> Bool {
        guard snapshot.autoFallbackToOllama else { return false }
        let current = snapshot.aiSelection(for: speaker)

        do {
            let model = try await aiService.resolveOllamaModel(preferred: current.ollamaModel)
            switch speaker {
            case .alice:
                preferences.aliceOllamaModel = model
                preferences.aliceProvider = .ollama
            case .bob:
                preferences.bobOllamaModel = model
                preferences.bobProvider = .ollama
            case .user:
                return false
            }

            providerNotice = "\(reason) – \(preferences.chatDisplayName(for: speaker)) nutzt jetzt Ollama (\(model))."
            _ = await DiagnosticsLogger.shared.log(
                .warning,
                source: "provider.fallback",
                message: reason,
                metadata: ["speaker": speaker.rawValue, "ollama_model": model]
            )
            return true
        } catch {
            providerNotice = "\(reason). Wechsel zu Ollama war nicht möglich: \(error.localizedDescription)"
            lastErrorEventID = await DiagnosticsLogger.shared.log(
                .error,
                source: "provider.fallback",
                message: error.localizedDescription,
                metadata: ["speaker": speaker.rawValue]
            )
            return false
        }
    }

    private func appendGeneratedMessage(
        speaker: ChatSpeaker,
        reply: AIService.AIReply,
        date: Date,
        streamed: Bool
    ) async {
        let finalText = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return }

        if !streamed {
            messages.append(ChatMessage(
                speaker: speaker,
                text: finalText,
                date: date,
                sources: reply.sources,
                citations: reply.citations,
                researchStatus: reply.researchStatus
            ))
            persist()
            return
        }

        let messageID = UUID()
        messages.append(ChatMessage(id: messageID, speaker: speaker, text: "", date: date))
        streamTick &+= 1

        var partial = ""
        let tokens = finalText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0
        var renderedChunks = 0
        while index < tokens.count {
            guard !Task.isCancelled else {
                messages.removeAll { $0.id == messageID }
                streamTick &+= 1
                return
            }

            let chunkSize = min(tokens.count - index, Int.random(in: 2...5))
            let nextChunk = tokens[index..<(index + chunkSize)].joined(separator: " ")
            partial = partial.isEmpty ? nextChunk : partial + " " + nextChunk
            updateMessage(
                id: messageID,
                speaker: speaker,
                text: partial,
                date: date,
                sources: nil,
                citations: nil,
                researchStatus: nil
            )
            renderedChunks += 1
            if renderedChunks.isMultiple(of: 3) || index + chunkSize == tokens.count {
                streamTick &+= 1
            }
            index += chunkSize
            do {
                try await Task.sleep(for: .milliseconds(Int.random(in: 70...115)))
            } catch {
                messages.removeAll { $0.id == messageID }
                streamTick &+= 1
                return
            }
        }

        updateMessage(
            id: messageID,
            speaker: speaker,
            text: finalText,
            date: date,
            sources: reply.sources,
            citations: reply.citations,
            researchStatus: reply.researchStatus
        )
        persist()
        streamTick &+= 1
    }

    private func updateMessage(
        id: UUID,
        speaker: ChatSpeaker,
        text: String,
        date: Date,
        sources: [WebSource]?,
        citations: [InlineCitation]?,
        researchStatus: ResearchStatus?
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = ChatMessage(
            id: id,
            speaker: speaker,
            text: text,
            date: date,
            sources: sources,
            citations: citations,
            researchStatus: researchStatus
        )
    }

    private func maybeDoubleText(speaker: ChatSpeaker) async {
        let snapshot = preferences.snapshot()
        guard snapshot.chatMode == .group,
              snapshot.doubleTextingEnabled,
              pendingUserMessageID == nil,
              preferences.autonomousEnabled,
              Double.random(in: 0...1) < snapshot.doubleTextChance else { return }

        do {
            try await Task.sleep(for: .milliseconds(Int.random(in: 650...1500)))
        } catch {
            return
        }
        guard !Task.isCancelled,
              pendingUserMessageID == nil,
              !isGenerating,
              preferences.autonomousEnabled else { return }

        _ = await generateOne(speaker: speaker, replyMode: .doubleText, focusedUserMessageID: nil)
    }

    private func nextSpeaker() -> ChatSpeaker {
        if preferences.chatMode == .single { return .alice }
        for message in messages.reversed() {
            switch message.speaker {
            case .alice: return .bob
            case .bob: return .alice
            case .user: continue
            }
        }
        return .alice
    }

    // MARK: - Memory

    private func scheduleMemoryRefreshIfNeeded() {
        guard preferences.memoryEnabled,
              memoryTask == nil,
              messages.count >= 10,
              messages.count - memory.coveredMessageCount >= 8 else { return }

        let currentMessages = messages
        let currentMemory = memory
        let snapshot = preferences.snapshot()
        isRefreshingMemory = true
        memoryTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshMemory(using: currentMessages, existing: currentMemory, snapshot: snapshot)
        }
    }

    private func refreshMemory(
        using currentMessages: [ChatMessage],
        existing currentMemory: ConversationMemory,
        snapshot: PreferencesSnapshot
    ) async {
        isRefreshingMemory = true
        defer {
            isRefreshingMemory = false
            memoryTask = nil
        }

        do {
            memory = try await aiService.refreshMemory(
                existing: currentMemory,
                messages: currentMessages,
                preferences: snapshot
            )
            persist()
            await refreshUsageDashboard()
        } catch {
            // Das Gedächtnis darf den sichtbaren Chat nicht blockieren.
        }
    }

    // MARK: - Usage

    func refreshUsageDashboard() async {
        var values: [AIProvider: AIService.ProviderUsageStatus] = [:]
        for provider in AIProvider.allCases {
            values[provider] = await aiService.usageStatus(for: provider)
        }
        usageStatuses = values
    }

    func resetUsageDashboard() async {
        await aiService.resetUsageCounters()
        await refreshUsageDashboard()
    }

    // MARK: - Diagnostics

    func runDiagnostics() async {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }

        var lines: [String] = []
        var hasWarning = false
        var hasError = false
        let snapshot = preferences.snapshot()

        let diagnosticSpeakers: [ChatSpeaker] = snapshot.chatMode == .group ? [.alice, .bob] : [.alice]
        let geminiKey = (KeychainStore.read() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var testedGeminiModels = Set<String>()

        for speaker in diagnosticSpeakers {
            let selection = snapshot.aiSelection(for: speaker)
            lines.append("\(preferences.chatDisplayName(for: speaker)): \(selection.provider.displayName) · \(selection.activeModel)")
            if selection.provider == .gemini {
                if geminiKey.isEmpty {
                    lines.append("  Gemini-Key fehlt")
                    hasError = true
                } else {
                    let model = selection.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    if model.isEmpty {
                        lines.append("  Kein Gemini-Modell gewählt")
                        hasError = true
                    } else if testedGeminiModels.insert(model.lowercased()).inserted {
                        do {
                            _ = try await aiService.testGemini(model: model, apiKey: geminiKey)
                            lines.append("  Modell-Test \(model): OK")
                        } catch {
                            lines.append("  Modell-Test \(model): \(error.localizedDescription)")
                            hasError = true
                        }
                    }
                }
            }
        }

        do {
            let models = try await aiService.listOllamaModels()
            lines.append("Ollama: erreichbar · \(models.count) lokale Modell(e)")
            for speaker in diagnosticSpeakers where snapshot.aiSelection(for: speaker).provider == .ollama {
                let selected = snapshot.aiSelection(for: speaker).ollamaModel
                if models.contains(where: { $0.name.caseInsensitiveCompare(selected) == .orderedSame }) {
                    lines.append("  \(preferences.chatDisplayName(for: speaker)): \(selected) lokal verfügbar")
                    let lower = selected.lowercased()
                    if lower == "llama3:latest" || (lower.hasPrefix("llama3:") && !lower.hasPrefix("llama3.1") && !lower.hasPrefix("llama3.2")) {
                        lines.append("    Hinweis: älteres Llama-3-Modell. Für natürlicheres Deutsch sind neuere Qwen-/Gemma-/Llama-Varianten oft die bessere Wahl.")
                        hasWarning = true
                    }
                } else {
                    lines.append("  \(preferences.chatDisplayName(for: speaker)): \(selected.isEmpty ? "kein Modell gewählt" : selected + " lokal nicht gefunden")")
                    hasWarning = true
                }
            }
        } catch {
            lines.append("Ollama: nicht erreichbar · \(error.localizedDescription)")
            if snapshot.aliceAI.provider == .ollama || snapshot.bobAI.provider == .ollama || snapshot.autoFallbackToOllama {
                hasWarning = true
            }
        }

        if snapshot.webAccessEnabled && diagnosticSpeakers.contains(where: { snapshot.aiSelection(for: $0).provider == .ollama }) {
            let hasOllamaWebKey = !(KeychainStore.read(account: KeychainStore.ollamaWebSearchAccount) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            if hasOllamaWebKey {
                lines.append("Ollama-Websuche: API-Key vorhanden")
            } else {
                lines.append("Ollama-Websuche: kein API-Key – Live-Websuche mit lokalen Modellen ist nicht verfügbar")
                hasWarning = true
            }
        }

        lines.append("Sitzungen: \(sessions.filter { ($0.mode ?? .group) == .group }.count) gespeicherte Gruppen-Chats")
        if let folder = try? ConversationStore.supportFolderURL() {
            lines.append("Lokale Daten: \(folder.path)")
        }

        diagnosticStatus = hasError ? "Fehler" : (hasWarning ? "Hinweis" : "Alles okay")
        diagnosticDetails = lines.joined(separator: "\n")

        _ = await DiagnosticsLogger.shared.log(
            hasError ? .error : (hasWarning ? .warning : .info),
            source: "diagnostics.health",
            message: "Diagnose abgeschlossen",
            metadata: ["status": diagnosticStatus]
        )
        await refreshRecentDiagnosticLog()
    }

    func refreshRecentDiagnosticLog() async {
        recentDiagnosticLog = await DiagnosticsLogger.shared.recentLines(limit: 120)
    }

    func clearDiagnosticLog() async {
        await DiagnosticsLogger.shared.clear()
        recentDiagnosticLog = "Diagnose-Log wurde geleert."
        _ = await DiagnosticsLogger.shared.log(.info, source: "diagnostics.log", message: "Diagnose-Log geleert")
        await refreshRecentDiagnosticLog()
    }

    // MARK: - Persistence helpers

    private var selectedSessionIndex: Int? {
        guard let selectedSessionID else { return nil }
        return sessions.firstIndex(where: { $0.id == selectedSessionID })
    }

    private func persist() {
        persistCurrentSessionIntoArray()
        guard let selectedSessionID else { return }

        persistenceRevision &+= 1
        let revision = persistenceRevision
        let store = PersistedSessionStore(selectedSessionID: selectedSessionID, sessions: sessions)

        // Disk-I/O can become expensive with long conversations. Keep it off the MainActor
        // so the macOS UI stays responsive even with many messages/sessions.
        Task(priority: .utility) {
            await ConversationPersistenceWorker.shared.save(store, revision: revision)
        }
    }

    private func persistCurrentSessionIntoArray() {
        guard let index = selectedSessionIndex else { return }
        sessions[index].messages = messages
        sessions[index].memory = memory
        sessions[index].mode = preferences.chatMode
        sessions[index].updatedAt = Date()
    }

    private func loadSelectedSessionIntoView() {
        guard let index = selectedSessionIndex else { return }
        messages = sessions[index].messages
        memory = sessions[index].memory
    }

    private func resetPendingState() {
        pendingUserMessageID = nil
        pendingUserSpeakers.removeAll()
        userRevision += 1
        isGenerating = false
        typingSpeaker = nil
    }

    private func updateSessionTitleIfNeeded(from text: String) {
        guard let index = selectedSessionIndex else { return }
        let old = sessions[index].title
        if old.hasPrefix("Neuer Chat") || old == "Erster Chat" || old == "KI-Chat" {
            let compact = text.replacingOccurrences(of: "\n", with: " ")
            sessions[index].title = String(compact.prefix(44))
        }
    }

    private static func removingLegacySeedMessages(_ session: ChatSession) -> ChatSession {
        let oldAlice = "Ich würde gern mit einer einfachen Frage anfangen: Wann wird aus einer guten Idee eigentlich eine wirklich interessante Idee?"
        let oldBob = "Für mich dann, wenn sie nicht nur plausibel klingt, sondern eine Annahme infrage stellt, die vorher selbstverständlich wirkte."

        var cleaned = session
        if cleaned.messages.first?.speaker == .alice,
           cleaned.messages.first?.text == oldAlice {
            cleaned.messages.removeFirst()
            if cleaned.messages.first?.speaker == .bob,
               cleaned.messages.first?.text == oldBob {
                cleaned.messages.removeFirst()
            }
            cleaned.memory = .empty
            cleaned.updatedAt = Date()
        }
        return cleaned
    }

    private func makeEmptySession(title: String, mode: ChatMode) -> ChatSession {
        ChatSession(title: title, messages: [], memory: .empty, mode: mode)
    }

}
