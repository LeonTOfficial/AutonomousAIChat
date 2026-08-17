import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var viewModel: ChatViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let appUpdater = AppUpdater.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var geminiKey = ""
    @State private var keyStatus = ""
    @State private var isTestingGemini = false
    @State private var ollamaWebKey = ""
    @State private var ollamaWebStatus = ""
    @State private var isTestingOllamaWeb = false

    @State private var ollamaModels: [AIService.OllamaModel] = []
    @State private var ollamaCatalog: [AIService.OllamaCatalogModel] = []
    @State private var ollamaCatalogSearch = ""
    @State private var selectedCatalogModelID = ""
    @State private var catalogTarget: ChatSpeaker = .alice
    @State private var isLoadingModels = false
    @State private var isLoadingCatalog = false
    @State private var isPullingModel = false
    @State private var modelPullProgress: Double?
    @State private var modelPullStatus = ""
    @State private var modelPullTask: Task<Void, Never>?
    @State private var ollamaStatus = ""

    @State private var isRefreshingMemory = false
    @State private var showDiagnosticLog = false

    private let geminiModels = [
        "gemini-3.7-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite"
    ]

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "Allgemein"
        case ai = "KI"
        case people = "Personen"
        case chats = "Chats"
        case memory = "Gedächtnis"
        case design = "Design"
        case diagnostics = "Diagnose"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .ai: return "sparkles"
            case .people: return "person.2"
            case .chats: return "rectangle.stack"
            case .memory: return "brain"
            case .design: return "paintbrush"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (Build \(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView(selection: $selectedTab) {
                generalTab.tag(SettingsTab.general)
                aiTab.tag(SettingsTab.ai)
                peopleTab.tag(SettingsTab.people)
                chatsTab.tag(SettingsTab.chats)
                memoryTab.tag(SettingsTab.memory)
                designTab.tag(SettingsTab.design)
                diagnosticsTab.tag(SettingsTab.diagnostics)
            }
        }
        .frame(width: 760, height: 760)
        .onAppear {
            if let stored = KeychainStore.read(), !stored.isEmpty {
                geminiKey = stored
                keyStatus = "✅ Key ist im macOS-Schlüsselbund gespeichert"
            }
            if let stored = KeychainStore.read(account: KeychainStore.ollamaWebSearchAccount), !stored.isEmpty {
                ollamaWebKey = stored
                ollamaWebStatus = "✅ Ollama-Websuche ist eingerichtet"
            }
            loadOllamaModels()
            loadOllamaCatalog()
            Task {
                await viewModel.refreshUsageDashboard()
                await viewModel.refreshRecentDiagnosticLog()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preferences.chatMode == .group ? "Autonomer KI-Gruppenchat" : "KI-Chat")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(appVersionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                providerBadge(.alice)
                if preferences.chatMode == .group {
                    providerBadge(.bob)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func providerBadge(_ speaker: ChatSpeaker) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(speaker == .alice ? Color.pink : Color.cyan)
                .frame(width: 6, height: 6)
            Text("\(preferences.chatDisplayName(for: speaker)): \(preferences.provider(for: speaker).displayName)")
                .font(.system(size: 10.5, weight: .medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.035), in: Capsule())
    }

    private var generalTab: some View {
        Form {
            Section("Chat-Modus") {
                Picker("Modus", selection: Binding(
                    get: { preferences.chatMode },
                    set: { viewModel.setChatMode($0) }
                )) {
                    ForEach(ChatMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(preferences.chatMode == .group
                     ? "Gruppe: Alice und Bob reagieren auf dich und können danach selbstständig weiterreden."
                     : "KI-Chat: Ein temporärer normaler KI-Chat. Jedes Öffnen startet bewusst leer und neu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gespräch") {
                TextField("Gesprächsthema (optional)", text: $preferences.conversationTopic)
                    .textFieldStyle(.roundedBorder)

                if preferences.chatMode == .group {
                    Toggle("KI-Teilnehmer selbstständig weiterschreiben lassen", isOn: $preferences.autonomousEnabled)

                    HStack {
                        Text("Abstand")
                        Slider(value: $preferences.interval, in: 3...60, step: 1)
                        Text("\(Int(preferences.interval)) s")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }

                    Toggle("Doppeltexten erlauben", isOn: $preferences.doubleTextingEnabled)
                    if preferences.doubleTextingEnabled {
                        HStack {
                            Text("Wahrscheinlichkeit")
                            Slider(value: $preferences.doubleTextChance, in: 0.05...0.70, step: 0.05)
                            Text("\(Int(preferences.doubleTextChance * 100)) %")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                Toggle("Antworten schrittweise erscheinen lassen", isOn: $preferences.simulatedStreamingEnabled)
                Text("Diese Option startet bei jedem App-Start automatisch AUS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Nachrichten-Zähler anzeigen", isOn: $preferences.showMessageCount)
            }

            Section("Internet") {
                Toggle("Internetzugriff für aktuelle Infos erlauben", isOn: $preferences.webAccessEnabled)
                Text("Mit einem Ollama Web Search API-Key kann die App dieselbe Live-Websuche für Gemini und lokale Ollama-Modelle verwenden. Ohne diesen Key versucht Gemini – sofern dein API-Tier es erlaubt – sein natives Google Search Grounding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("Ollama Web Search API Key (optional)", text: $ollamaWebKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(isTestingOllamaWeb ? "Teste…" : "Ollama-Websuche speichern & testen") {
                        testAndSaveOllamaWebKey()
                    }
                    .disabled(isTestingOllamaWeb || ollamaWebKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Ollama API-Key-Seite ↗") {
                        openURL("https://ollama.com/settings/keys")
                    }

                    Spacer()

                    Button("Web-Key löschen", role: .destructive) {
                        KeychainStore.delete(account: KeychainStore.ollamaWebSearchAccount)
                        ollamaWebKey = ""
                        ollamaWebStatus = "Web-Key gelöscht"
                    }
                }

                if !ollamaWebStatus.isEmpty {
                    Text(ollamaWebStatus)
                        .font(.caption)
                        .foregroundStyle(ollamaWebStatus.hasPrefix("✅") ? .green : .secondary)
                        .textSelection(.enabled)
                }

                Text("Der Ollama-Web-Key ist nur für die Websuche gedacht. Lokale Ollama-Modelle selbst benötigen weiterhin keinen API-Key und kein Abo. Er ist besonders praktisch, wenn Google Search Grounding im kostenlosen Gemini-Tier nicht verfügbar ist.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Softwareupdates") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sparkle-Updates")
                            .font(.body.weight(.medium))
                        Text(appUpdater.automaticallyChecksForUpdates
                             ? "Automatische Prüfung ist aktiviert."
                             : "Automatische Prüfung ist noch nicht aktiviert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Jetzt prüfen …") {
                        appUpdater.checkForUpdates()
                    }
                    .disabled(!appUpdater.canCheckForUpdates)
                }

                Text("Diese erste Sparkle-Version muss noch einmal per DMG installiert werden. Danach kann die App signierte Updates selbst finden und installieren, sobald der öffentliche Update-Kanal veröffentlicht ist.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .tabItem { Label(SettingsTab.general.rawValue, systemImage: SettingsTab.general.icon) }
    }

    private var aiTab: some View {
        Form {
            Section("Gemini") {
                SecureField("Gemini API Key", text: $geminiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(isTestingGemini ? "Teste…" : "Key speichern & testen") {
                        testAndSaveGeminiKey()
                    }
                    .disabled(isTestingGemini || geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("API-Key-Seite ↗") {
                        openURL("https://aistudio.google.com/app/apikey")
                    }

                    Spacer()

                    Button("Key löschen", role: .destructive) {
                        KeychainStore.delete()
                        geminiKey = ""
                        keyStatus = "Key gelöscht"
                    }
                }

                if !keyStatus.isEmpty {
                    Text(keyStatus)
                        .font(.caption)
                        .foregroundStyle(keyStatus.hasPrefix("✅") ? .green : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Alice – Modell") {
                participantModelSettings(.alice)
            }

            if preferences.chatMode == .group {
                Section("Bob – Modell") {
                    participantModelSettings(.bob)
                }
            }

            Section("Fallback & Limit-Schutz") {
                Toggle("Bei Gemini-Limit automatisch auf Ollama wechseln", isOn: $preferences.autoFallbackToOllama)
                Toggle("Zusätzlichen App-Limit-Schutz verwenden", isOn: $preferences.limitProtectionEnabled)

                if preferences.limitProtectionEnabled {
                    HStack {
                        Text("Gemini Soft-Limit pro Tag")
                        Spacer()
                        TextField("0", value: $preferences.geminiDailyRequestSoftLimit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                    Text("0 = nur auf echten Gemini-Fehler 429 reagieren. Wenn du dein Tageslimit aus AI Studio kennst, kannst du hier einen niedrigeren Sicherheitswert eintragen; dann wechselt die App vorher zu Ollama.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Verbrauch heute") {
                usageDashboard
            }

            Section("Ollama-Modellkatalog") {
                ollamaCatalogView
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .tabItem { Label(SettingsTab.ai.rawValue, systemImage: SettingsTab.ai.icon) }
    }

    @ViewBuilder
    private func participantModelSettings(_ speaker: ChatSpeaker) -> some View {
        let providerBinding = providerBinding(for: speaker)
        let geminiBinding = geminiModelBinding(for: speaker)
        let ollamaBinding = ollamaModelBinding(for: speaker)

        Picker("Anbieter", selection: providerBinding) {
            Text("Gemini").tag(AIProvider.gemini)
            Text("Ollama").tag(AIProvider.ollama)
        }
        .pickerStyle(.segmented)

        if providerBinding.wrappedValue == .gemini {
            Picker("Gemini-Modell", selection: geminiBinding) {
                ForEach(geminiModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            Text(geminiDescription(geminiBinding.wrappedValue))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Ollama-Fallback: \(ollamaBinding.wrappedValue.isEmpty ? "noch nicht gewählt" : ollamaBinding.wrappedValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ollamaPicker(binding: ollamaBinding)
        }

        HStack(spacing: 7) {
            Text("AKTIV")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.10), in: Capsule())
            Text("\(providerBinding.wrappedValue.displayName) · \(providerBinding.wrappedValue == .gemini ? geminiBinding.wrappedValue : ollamaBinding.wrappedValue)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    @ViewBuilder
    private func ollamaPicker(binding: Binding<String>) -> some View {
        if ollamaModels.isEmpty {
            TextField("Ollama-Modell", text: binding)
                .textFieldStyle(.roundedBorder)
        } else {
            Picker("Ollama-Modell", selection: binding) {
                if !binding.wrappedValue.isEmpty,
                   !ollamaModels.contains(where: { $0.name == binding.wrappedValue }) {
                    Text("Nicht lokal verfügbar · " + binding.wrappedValue)
                        .tag(binding.wrappedValue)
                }
                ForEach(ollamaModels) { model in
                    Text(modelLabel(model)).tag(model.name)
                }
            }
        }

        HStack {
            Button(isLoadingModels ? "Suche…" : "Lokale Modelle neu laden") { loadOllamaModels() }
                .disabled(isLoadingModels)
            Spacer()
            Text(ollamaStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var usageDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AIProvider.allCases) { provider in
                let status = viewModel.usageStatuses[provider]
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(provider.displayName)
                            .fontWeight(.semibold)
                        Spacer()
                        if let status {
                            Text("\(status.requestsToday) Requests · \(status.totalTokensToday) Tokens")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if provider == .gemini,
                       preferences.geminiDailyRequestSoftLimit > 0,
                       let status {
                        let limit = max(1, preferences.geminiDailyRequestSoftLimit)
                        ProgressView(value: Double(min(status.requestsToday, limit)), total: Double(limit))
                        Text("App-Sicherheitslimit: \(status.requestsToday) / \(limit) Requests")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let note = status?.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack {
                Button("Aktualisieren") {
                    Task { await viewModel.refreshUsageDashboard() }
                }
                Button("Google AI Studio Limits ↗") {
                    openURL("https://aistudio.google.com/usage")
                }
                Spacer()
                Button("Lokale Zähler zurücksetzen") {
                    Task { await viewModel.resetUsageDashboard() }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var ollamaCatalogView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Picker("Für", selection: $catalogTarget) {
                    Text(preferences.name(for: .alice)).tag(ChatSpeaker.alice)
                    if preferences.chatMode == .group {
                        Text(preferences.name(for: .bob)).tag(ChatSpeaker.bob)
                    }
                }
                .frame(width: 170)

                TextField("Modelle durchsuchen…", text: $ollamaCatalogSearch)
                    .textFieldStyle(.roundedBorder)

                Button(isLoadingCatalog ? "Lade…" : "Katalog aktualisieren") {
                    loadOllamaCatalog()
                }
                .disabled(isLoadingCatalog)
            }

            if ollamaCatalog.isEmpty {
                Text(isLoadingCatalog ? "Ollama-Katalog wird geladen…" : "Noch kein Katalog geladen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Label("\(ollamaModels.count) bereits lokal", systemImage: "internaldrive")
                    Spacer()
                    Text("v18 zeigt nur lokale Modelle. Qwen 3.5 9B ist für diesen 16-GB-Mac empfohlen; deutlich größere Modelle erhalten eine Speicherwarnung.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .font(.caption)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredCatalog) { model in
                            let fit = memoryFit(for: model)
                            Button {
                                selectedCatalogModelID = model.id
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(model.name)
                                                .font(.system(size: 12.5, weight: .semibold))
                                            Text(model.specialization)
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.black.opacity(0.045), in: Capsule())
                                            if isRecommendedOllamaChatModel(model.name) {
                                                Text("EMPFOHLEN FÜR DIESEN MAC")
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .foregroundStyle(.blue)
                                            }
                                            if let fit {
                                                Text(fit.label)
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .foregroundStyle(fit.color)
                                            }
                                            if ollamaModels.contains(where: { $0.name == model.name }) {
                                                Text("LOKAL")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.green)
                                            } else {
                                                Text("DOWNLOAD")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.orange)
                                            }
                                            if preferences.aliceProvider == .ollama && preferences.aliceOllamaModel == model.name {
                                                Text("\(preferences.name(for: .alice).uppercased()) AKTIV")
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .foregroundStyle(.pink)
                                            }
                                            if preferences.chatMode == .group,
                                               preferences.bobProvider == .ollama,
                                               preferences.bobOllamaModel == model.name {
                                                Text("\(preferences.name(for: .bob).uppercased()) AKTIV")
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .foregroundStyle(.cyan)
                                            }
                                        }
                                        Text(model.summary)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    if let size = model.sizeLabel {
                                        Text(size)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }

                                    Image(systemName: selectedCatalogModelID == model.id ? "checkmark.circle.fill" : "circle")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    selectedCatalogModelID == model.id ? Color.accentColor.opacity(0.10) : Color.black.opacity(0.018),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 230)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LOKAL = installiert. Die Speicherampel vergleicht die Modelldatei mit deinem gemeinsamen Arbeitsspeicher.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if isPullingModel {
                            if let modelPullProgress {
                                ProgressView(value: modelPullProgress)
                                    .frame(width: 220)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(modelPullStatus.isEmpty ? "Download wird vorbereitet…" : modelPullStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let model = selectedCatalogModel,
                                  let fit = memoryFit(for: model) {
                            Text(fit.detail)
                                .font(.caption2)
                                .foregroundStyle(fit.color)
                        }
                    }
                    Spacer()
                    Button(isPullingModel ? "Download abbrechen" : actionTitleForSelectedModel) {
                        if isPullingModel {
                            modelPullTask?.cancel()
                            modelPullTask = nil
                            isPullingModel = false
                            modelPullProgress = nil
                            modelPullStatus = "Download abgebrochen"
                        } else {
                            useSelectedCatalogModel()
                        }
                    }
                    .disabled(!isPullingModel && selectedCatalogModel == nil)
                }
            }
        }
    }

    private func isRecommendedOllamaChatModel(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "qwen3.5:9b" || lower == "qwen3.5:latest"
    }

    private func memoryFit(for model: AIService.OllamaCatalogModel) -> (label: String, detail: String, color: Color)? {
        guard let size = model.effectiveSizeBytes, size > 0 else { return nil }
        let physical = Double(ProcessInfo.processInfo.physicalMemory)
        let ratio = Double(size) / physical
        if ratio <= 0.50 {
            return ("PASST GUT", "Gute Größenreserve für macOS, Kontext und die Chat-App.", .green)
        }
        if ratio <= 0.80 {
            return ("KNAPP", "Kann funktionieren, lässt aber wenig Reserve für großen Kontext.", .orange)
        }
        return ("ZU GROSS", "Wahrscheinlich starker Speicherdruck und Auslagerung. Nur bewusst als Test verwenden.", .red)
    }

    private var peopleTab: some View {
        Form {
            Section("\(preferences.name(for: .alice)) – Persönlichkeit") {
                profileFields(
                    name: $preferences.aliceName,
                    role: $preferences.aliceRole,
                    personality: $preferences.alicePersonality,
                    creativity: $preferences.aliceCreativity,
                    language: $preferences.aliceLanguage
                )
            }

            Section("\(preferences.name(for: .bob)) – Persönlichkeit") {
                profileFields(
                    name: $preferences.bobName,
                    role: $preferences.bobRole,
                    personality: $preferences.bobPersonality,
                    creativity: $preferences.bobCreativity,
                    language: $preferences.bobLanguage
                )
            }

            Section {
                Button("Persönlichkeiten zurücksetzen") {
                    preferences.resetProfilesToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .tabItem { Label(SettingsTab.people.rawValue, systemImage: SettingsTab.people.icon) }
    }

    private var chatsTab: some View {
        Form {
            Section("Chat-Sitzungen") {
                Text("Gruppen-Chats werden gespeichert. Der normale KI-Chat ist bewusst temporär und startet bei jedem Öffnen leer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(viewModel.sessions.filter { ($0.mode ?? .group) == .group }.count) Gruppen-Chat(s)")
                    Spacer()
                    Button("Neuer Gruppen-Chat") { viewModel.createGroupSession() }
                }

                ForEach(viewModel.sessions.filter { ($0.mode ?? .group) == .group }) { session in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(session.title)
                                    .fontWeight(session.id == viewModel.selectedSessionID ? .semibold : .regular)
                                if session.id == viewModel.selectedSessionID {
                                    Text("AKTIV")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.green)
                                }
                            }
                            Text("\(session.messages.count) Nachrichten · zuletzt \(session.updatedAt, format: .dateTime.day().month().hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if session.id != viewModel.selectedSessionID {
                            Button("Öffnen") { viewModel.selectSession(session.id) }
                        }
                        Button(role: .destructive) {
                            viewModel.deleteSession(session.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }

            Section("Aktueller Chat") {
                Button("Aktuelle Sitzung zurücksetzen", role: .destructive) {
                    viewModel.clearConversation()
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .tabItem { Label(SettingsTab.chats.rawValue, systemImage: SettingsTab.chats.icon) }
    }

    private var memoryTab: some View {
        Form {
            Section("Langzeit-Gedächtnis") {
                Toggle("Langzeit-Gedächtnis verwenden", isOn: $preferences.memoryEnabled)

                if preferences.memoryEnabled {
                    let covered = min(viewModel.memory.coveredMessageCount, viewModel.messages.count)
                    Text(viewModel.memory.summary.isEmpty
                         ? "Gedächtnis baut sich nach mehreren Nachrichten automatisch auf."
                         : "Aktuell sind etwa \(covered) Nachrichten verdichtet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !viewModel.memory.summary.isEmpty {
                        Text(viewModel.memory.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }

                    HStack {
                        Button(isRefreshingMemory ? "Aktualisiere…" : "Gedächtnis aktualisieren") {
                            isRefreshingMemory = true
                            Task {
                                await viewModel.refreshMemoryNow()
                                await MainActor.run { isRefreshingMemory = false }
                            }
                        }
                        .disabled(isRefreshingMemory || viewModel.messages.isEmpty)

                        Button("Datei öffnen") { openMemoryFile() }
                        Button("Im Finder zeigen") { revealMemoryFile() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .tabItem { Label(SettingsTab.memory.rawValue, systemImage: SettingsTab.memory.icon) }
    }

    private var designTab: some View {
        Form {
            Section("Design-Modus") {
                Picker("Darstellung", selection: $preferences.designMode) {
                    ForEach(AppDesignMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(preferences.designMode == .current
                     ? "Das bisherige v18-Design bleibt vollständig erhalten."
                     : "Ein separater transparenter Fenstermodus mit eigenen, dauerhaft gespeicherten Werten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(preferences.designMode.displayName) {
                ColorPicker(
                    "Hintergrundfarbe",
                    selection: Binding(
                        get: { preferences.tintColor },
                        set: { preferences.setTint(from: $0) }
                    ),
                    supportsOpacity: false
                )

                if preferences.designMode == .current {
                    HStack {
                        Text("Deckkraft")
                        Slider(value: $preferences.backgroundOpacity, in: 0.05...0.85, step: 0.01)
                        Text("\(Int(preferences.backgroundOpacity * 100)) %")
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }

                    HStack {
                        Text("Weichzeichnung")
                        Slider(value: $preferences.backgroundBlur, in: 0...24, step: 1)
                        Text("\(Int(preferences.backgroundBlur))")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                } else {
                    HStack {
                        Text("Hintergrunddeckkraft")
                        Slider(value: $preferences.transparentBackgroundOpacity, in: 0...1, step: 0.01)
                        Text("\(Int(preferences.transparentBackgroundOpacity * 100)) %")
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }

                    HStack {
                        Text("Weichzeichnung")
                        Slider(value: $preferences.transparentBackgroundBlur, in: 0...24, step: 1)
                        Text("\(Int(preferences.transparentBackgroundBlur))")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }

                    Text(preferences.transparentBackgroundOpacity == 0
                         ? "0 %: Der Fensterhintergrund ist vollständig transparent; Inhalte behalten eigene lesbare Glasflächen."
                         : "Deckkraft und Blur werden ohne dauerhafte Animation direkt in der Vorschau und im Chat aktualisiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Transparent Glass zurücksetzen") {
                            preferences.resetTransparentGlassDesign()
                        }
                    }
                }
            }

            Section("Live-Vorschau") {
                DesignModePreview(
                    mode: preferences.designMode,
                    tint: preferences.tintColor,
                    currentOpacity: preferences.backgroundOpacity,
                    currentBlur: preferences.backgroundBlur,
                    transparentOpacity: preferences.transparentBackgroundOpacity,
                    transparentBlur: preferences.transparentBackgroundBlur
                )

                if reduceTransparency || reduceMotion {
                    Text(reduceTransparency
                         ? "„Transparenz reduzieren“ ist aktiv: Transparent Glass verwendet automatisch einen soliden, gut lesbaren Hintergrund."
                         : "„Bewegung reduzieren“ ist aktiv: Zustandswechsel erfolgen ohne dekorative Animationen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .tabItem { Label(SettingsTab.design.rawValue, systemImage: SettingsTab.design.icon) }
    }

    private var diagnosticsTab: some View {
        Form {
            Section("Fehleranalyse & Systemstatus") {
                HStack(spacing: 8) {
                    Circle().fill(diagnosticColor).frame(width: 9, height: 9)
                    Text(viewModel.diagnosticStatus).fontWeight(.semibold)
                    Spacer()
                    Button(viewModel.isRunningDiagnostics ? "Prüfe…" : "Diagnose ausführen") {
                        Task { await viewModel.runDiagnostics() }
                    }
                    .disabled(viewModel.isRunningDiagnostics)
                }

                if !viewModel.diagnosticDetails.isEmpty {
                    Text(viewModel.diagnosticDetails)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }

                if let eventID = viewModel.lastErrorEventID {
                    Text("Letzte Fehler-ID: \(eventID)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Log öffnen") { openDiagnosticLog() }
                    Button("Im Finder zeigen") { revealDiagnosticLog() }
                    Button("Neu laden") { Task { await viewModel.refreshRecentDiagnosticLog() } }
                    Spacer()
                    Button("Log leeren", role: .destructive) { Task { await viewModel.clearDiagnosticLog() } }
                }

                DisclosureGroup("Letzte Diagnose-Einträge", isExpanded: $showDiagnosticLog) {
                    ScrollView {
                        Text(viewModel.recentDiagnosticLog)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .frame(height: 220)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .tabItem { Label(SettingsTab.diagnostics.rawValue, systemImage: SettingsTab.diagnostics.icon) }
    }

    // MARK: - Bindings

    private func providerBinding(for speaker: ChatSpeaker) -> Binding<AIProvider> {
        switch speaker {
        case .alice: return $preferences.aliceProvider
        case .bob: return $preferences.bobProvider
        case .user: return .constant(.gemini)
        }
    }

    private func geminiModelBinding(for speaker: ChatSpeaker) -> Binding<String> {
        switch speaker {
        case .alice: return $preferences.aliceGeminiModel
        case .bob: return $preferences.bobGeminiModel
        case .user: return .constant("")
        }
    }

    private func ollamaModelBinding(for speaker: ChatSpeaker) -> Binding<String> {
        switch speaker {
        case .alice: return $preferences.aliceOllamaModel
        case .bob: return $preferences.bobOllamaModel
        case .user: return .constant("")
        }
    }

    // MARK: - Actions

    private func testAndSaveGeminiKey() {
        let trimmed = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            keyStatus = "Bitte zuerst einen Key eingeben"
            return
        }

        isTestingGemini = true
        keyStatus = "Gemini-Verbindung wird geprüft…"
        let model = AIService.recommendedGeminiModel

        Task {
            do {
                _ = try await viewModel.aiService.testGemini(model: model, apiKey: trimmed)
                try KeychainStore.save(trimmed)
                await MainActor.run {
                    if preferences.aliceGeminiModel.hasPrefix("gemini-2.") {
                        preferences.aliceGeminiModel = model
                    }
                    if preferences.bobGeminiModel.hasPrefix("gemini-2.") {
                        preferences.bobGeminiModel = model
                    }
                    keyStatus = "✅ Gemini-Key funktioniert · Test mit \(model)"
                    isTestingGemini = false
                    viewModel.lastError = nil
                }
                await viewModel.refreshUsageDashboard()
            } catch {
                await MainActor.run {
                    keyStatus = "❌ \(error.localizedDescription)"
                    isTestingGemini = false
                }
            }
        }
    }

    private func testAndSaveOllamaWebKey() {
        let trimmed = ollamaWebKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isTestingOllamaWeb = true
        ollamaWebStatus = "Ollama-Websuche wird geprüft…"

        Task {
            do {
                let sourceCount = try await viewModel.aiService.testOllamaWebSearch(apiKey: trimmed)
                try KeychainStore.save(trimmed, account: KeychainStore.ollamaWebSearchAccount)
                await MainActor.run {
                    ollamaWebStatus = "✅ Websuche funktioniert · \(sourceCount) Testquelle(n)"
                    isTestingOllamaWeb = false
                }
            } catch {
                await MainActor.run {
                    ollamaWebStatus = "❌ \(error.localizedDescription)"
                    isTestingOllamaWeb = false
                }
            }
        }
    }

    private func loadOllamaModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        ollamaStatus = ""
        Task {
            do {
                let models = try await viewModel.aiService.listOllamaModels()
                await MainActor.run {
                    ollamaModels = models
                    ollamaStatus = "\(models.count) lokal"
                    assignFirstOllamaModelIfNeeded(models)
                    isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    ollamaStatus = "Ollama nicht erreichbar"
                    isLoadingModels = false
                }
            }
        }
    }

    private func assignFirstOllamaModelIfNeeded(_ models: [AIService.OllamaModel]) {
        guard let first = models.first else { return }

        func isAvailable(_ name: String) -> Bool {
            models.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        if preferences.aliceOllamaModel.isEmpty ||
            preferences.aliceOllamaModel.lowercased().contains(":cloud") ||
            !isAvailable(preferences.aliceOllamaModel) {
            preferences.aliceOllamaModel = first.name
        }
        if preferences.bobOllamaModel.isEmpty ||
            preferences.bobOllamaModel.lowercased().contains(":cloud") ||
            !isAvailable(preferences.bobOllamaModel) {
            preferences.bobOllamaModel = first.name
        }
    }

    private func loadOllamaCatalog() {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        Task {
            do {
                let models = try await viewModel.aiService.listOllamaCatalogModels()
                await MainActor.run {
                    ollamaCatalog = models
                    if selectedCatalogModelID.isEmpty { selectedCatalogModelID = models.first?.id ?? "" }
                    isLoadingCatalog = false
                }
            } catch {
                await MainActor.run {
                    ollamaStatus = "Katalog nicht erreichbar: \(error.localizedDescription)"
                    isLoadingCatalog = false
                }
            }
        }
    }

    private var filteredCatalog: [AIService.OllamaCatalogModel] {
        let query = ollamaCatalogSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ollamaCatalog }
        return ollamaCatalog.filter {
            $0.name.lowercased().contains(query) ||
            $0.specialization.lowercased().contains(query) ||
            $0.summary.lowercased().contains(query)
        }
    }

    private var selectedCatalogModel: AIService.OllamaCatalogModel? {
        ollamaCatalog.first(where: { $0.id == selectedCatalogModelID })
    }

    private var actionTitleForSelectedModel: String {
        guard let model = selectedCatalogModel else { return "Modell verwenden" }
        if ollamaModels.contains(where: { $0.name == model.name }) { return "Lokales Modell verwenden" }
        return "Herunterladen & verwenden"
    }

    private func useSelectedCatalogModel() {
        guard let model = selectedCatalogModel else { return }
        isPullingModel = true
        modelPullProgress = nil
        modelPullStatus = ""

        modelPullTask = Task {
            do {
                let resolved: String
                if ollamaModels.contains(where: { $0.name == model.name }) {
                    resolved = model.name
                } else {
                    resolved = try await viewModel.aiService.pullOllamaModel(model.name) { progress in
                        Task { @MainActor in
                            modelPullProgress = progress.fraction
                            if let fraction = progress.fraction {
                                modelPullStatus = "\(progress.status) · \(Int(fraction * 100)) %"
                            } else {
                                modelPullStatus = progress.status
                            }
                        }
                    }
                }

                await MainActor.run {
                    ollamaModelBinding(for: catalogTarget).wrappedValue = resolved
                    providerBinding(for: catalogTarget).wrappedValue = .ollama
                    ollamaStatus = "✅ \(resolved) bereit"
                    isPullingModel = false
                    modelPullProgress = nil
                    modelPullTask = nil
                }
                loadOllamaModels()
            } catch is CancellationError {
                await MainActor.run {
                    ollamaStatus = "Download abgebrochen"
                    isPullingModel = false
                    modelPullProgress = nil
                    modelPullTask = nil
                }
            } catch {
                await MainActor.run {
                    ollamaStatus = "❌ \(error.localizedDescription)"
                    isPullingModel = false
                    modelPullProgress = nil
                    modelPullTask = nil
                }
            }
        }
    }

    private func profileFields(
        name: Binding<String>,
        role: Binding<String>,
        personality: Binding<String>,
        creativity: Binding<Double>,
        language: Binding<String>
    ) -> some View {
        Group {
            TextField("Name", text: name).textFieldStyle(.roundedBorder)
            TextField("Rolle", text: role).textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 5) {
                Text("Persönlichkeit").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: personality)
                    .font(.system(size: 12.5))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Text("Kreativität")
                Slider(value: creativity, in: 0...1, step: 0.05)
                Text("\(Int(creativity.wrappedValue * 100)) %")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            TextField("Bevorzugte Sprache", text: language).textFieldStyle(.roundedBorder)
        }
    }

    private func geminiDescription(_ model: String) -> String {
        switch model {
        case "gemini-3.7-flash":
            return "Empfohlen: aktuelles schnelles Flash-Modell für starken Allround-Chat, Coding, Agenten und komplexere mehrstufige Aufgaben."
        case "gemini-3.6-flash":
            return "Stabiles Flash-Modell mit guter Balance aus Geschwindigkeit, Reasoning und multimodalen Fähigkeiten."
        case "gemini-3.5-flash":
            return "Schneller Allrounder für normale Chat- und Coding-Aufgaben."
        case "gemini-3.5-flash-lite":
            return "Sehr leicht und schnell; gut für viele kurze Nachrichten und niedrige Latenz."
        case "gemini-3.1-flash-lite":
            return "Kompaktes Flash-Lite-Modell für einfache, schnelle Aufgaben."
        default:
            return "Gemini-Modell für Chat und allgemeine Aufgaben. Falls Google es abschaltet, wechselt die App bei einem 404 automatisch auf \(AIService.recommendedGeminiModel)."
        }
    }

    private func modelLabel(_ model: AIService.OllamaModel) -> String {
        var details: [String] = []
        if let size = model.parameterSize, !size.isEmpty { details.append(size) }
        if let bytes = model.sizeBytes, bytes > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            details.append(formatter.string(fromByteCount: bytes))
        }
        return details.isEmpty ? model.name : "\(model.name) · \(details.joined(separator: " · "))"
    }

    private var diagnosticColor: Color {
        switch viewModel.diagnosticStatus {
        case "Alles okay": return .green
        case "Fehler": return .red
        case "Hinweis": return .orange
        default: return .secondary
        }
    }

    private func openMemoryFile() {
        do { NSWorkspace.shared.open(try ConversationStore.memoryFileURL()) }
        catch { viewModel.lastError = "Gedächtnis-Datei konnte nicht geöffnet werden: \(error.localizedDescription)" }
    }

    private func revealMemoryFile() {
        do { NSWorkspace.shared.activateFileViewerSelecting([try ConversationStore.memoryFileURL()]) }
        catch { viewModel.lastError = "Gedächtnis-Datei konnte nicht gezeigt werden: \(error.localizedDescription)" }
    }

    private func openDiagnosticLog() {
        if let url = try? DiagnosticsLogger.logFileURL() { NSWorkspace.shared.open(url) }
    }

    private func revealDiagnosticLog() {
        if let url = try? DiagnosticsLogger.logFileURL() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func openURL(_ raw: String) {
        if let url = URL(string: raw) { NSWorkspace.shared.open(url) }
    }
}

private struct DesignModePreview: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let mode: AppDesignMode
    let tint: Color
    let currentOpacity: Double
    let currentBlur: Double
    let transparentOpacity: Double
    let transparentBlur: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo, Color.cyan.opacity(0.85), Color.pink.opacity(0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: 120, height: 120)
                .offset(x: 240, y: -35)

            previewWindow
                .padding(14)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        }
        .environment(\.transparentGlassModeEnabled, mode == .transparentGlass)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live-Vorschau für \(mode.displayName)")
    }

    private var previewWindow: some View {
        ZStack {
            previewBackground

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.green)
                }

                HStack {
                    Text("Eine gut lesbare Chat-Nachricht")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .stableGlass(
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                            tint: Color.cyan.opacity(0.13)
                        )
                    Spacer(minLength: 40)
                }

                HStack(spacing: 6) {
                    ForEach([0.42, 0.72, 0.55], id: \.self) { height in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.gradient)
                            .frame(width: 22, height: 34 * height)
                            .frame(height: 34, alignment: .bottom)
                    }
                    Text("Tabelle · Chart")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .transparentGlassReadabilityPanel(cornerRadius: 10)

                previewComposerSurface {
                    HStack(spacing: 6) {
                        Text("Nachricht schreiben…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 22, height: 22)
                            .adaptiveGlass(in: Circle(), tint: tint.opacity(0.18), interactive: true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private func previewComposerSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if mode == .transparentGlass && !reduceTransparency {
            content()
                .background(Color.clear, in: shape)
                .overlay(shape.stroke(.white.opacity(0.22), lineWidth: 0.8))
                .transparentGlassContrastHalo()
        } else {
            content()
                .adaptiveGlass(in: shape, tint: .white.opacity(0.028))
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        if mode == .current {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: currentBlur * 0.08)
                tint.opacity(currentOpacity).blendMode(.softLight)
                LinearGradient(
                    colors: [.white.opacity(0.075), .clear, .black.opacity(0.045)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if transparentOpacity <= 0 {
            Color.clear
        } else {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(transparentOpacity)
                    .blur(radius: transparentBlur * 0.08)
                tint.opacity(transparentOpacity * 0.30).blendMode(.softLight)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}
