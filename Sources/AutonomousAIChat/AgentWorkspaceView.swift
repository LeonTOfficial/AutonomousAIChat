import SwiftUI

struct AgentWorkspaceView: View {
    @Binding var workspaceMode: MainWorkspaceMode
    @ObservedObject var agent: AgentViewModel
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var prompt = ""

    private var agentSelection: AgentModelSelection {
        AgentModelSelection(
            provider: preferences.agentProvider,
            geminiModel: preferences.agentGeminiModel,
            ollamaModel: preferences.agentOllamaModel
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.16)

            HSplitView {
                planAndActivity
                    .frame(minWidth: 238, idealWidth: 270, maxWidth: 325)

                taskArea
                    .frame(minWidth: 390)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent-Arbeitsbereich")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(agent.isUsingSandbox ? "Sicherer Sandkasten" : (agent.workspaceURL?.lastPathComponent ?? "Kein Arbeitsbereich verfügbar"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Picker("Bereich", selection: $workspaceMode) {
                ForEach(MainWorkspaceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 190)

            headerActions
        }
        .padding(.leading, 86)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 58)
        .transparentGlassContrastHalo()
    }

    private var headerActions: some View {
        HStack(spacing: 1) {
            Menu {
                Button("Ordner wählen…") { agent.chooseWorkspace() }
                if !agent.isUsingSandbox {
                    Button("Zum Sandkasten wechseln") { agent.useSandbox() }
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .help("Arbeitsbereich wählen")

            Divider()
                .frame(height: 16)
                .opacity(0.32)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Einstellungen öffnen")
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .adaptiveGlass(in: Capsule(), tint: .white.opacity(0.04), interactive: true)
    }

    private var planAndActivity: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    safetyCard

                    if !agent.plan.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Live-Plan", systemImage: "checklist")
                            ForEach(agent.plan) { step in
                                HStack(alignment: .top, spacing: 9) {
                                    planIcon(step.status)
                                        .frame(width: 16, height: 16)
                                    Text(step.title)
                                        .font(.system(size: 11.5, weight: step.status == .active ? .semibold : .medium))
                                        .foregroundStyle(step.status == .waiting ? .secondary : .primary)
                                }
                            }
                        }
                        .agentSidebarSection()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Aktivitäten", systemImage: "waveform.path.ecg")

                        if agent.activities.isEmpty {
                            Text("Werkzeugaufrufe und nachgewiesene Ergebnisse erscheinen hier.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(agent.activities.suffix(16).reversed())) { activity in
                                activityRow(activity)
                            }
                        }
                    }
                    .agentSidebarSection()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .background(.black.opacity(0.035))
    }

    private var taskArea: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: agent.isRunning ? "ellipsis.circle.fill" : "message.fill")
                            .foregroundStyle(agent.isRunning ? .orange : preferences.tintColor)
                        Text(agent.currentStatus)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(agentSelection.displayLabel)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)

                    if agent.workspaceURL == nil { welcomeCard }

                    ForEach(agent.conversation) { entry in
                        conversationRow(entry)
                    }

                    if let action = agent.pendingAction {
                        approvalCard(action)
                    }

                    if let error = agent.lastError {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                            Text(error).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Erneut versuchen") { agent.retryLastRun() }
                                .buttonStyle(.bordered)
                        }
                        .agentPanel(tint: .orange.opacity(0.06))
                    }

                    if let result = agent.lastWrittenURL {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Datei wurde geschrieben")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(result.lastPathComponent)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Im Finder zeigen") { agent.revealLastResult() }
                                .buttonStyle(.bordered)
                        }
                        .agentPanel(tint: .green.opacity(0.08))
                    }

                    if agent.isRunning {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Agent arbeitet")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("Du kannst jederzeit stoppen. Ausstehende Änderungen werden verworfen.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Stoppen", role: .destructive) { agent.cancel() }
                                .buttonStyle(.bordered)
                        }
                        .agentPanel(tint: .orange.opacity(0.08))
                    }
                }
                .frame(maxWidth: 760)
                .padding(24)
                .frame(maxWidth: .infinity)
            }

            composer
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Divider().opacity(0.10)

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $prompt)
                    .font(.system(size: 13.5))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 52, maxHeight: 82)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Zum Beispiel: Erstelle Geschichte.txt mit einer kurzen Geschichte und zeige die Datei danach im Finder.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Label("Schreiben nur nach deiner Freigabe", systemImage: "lock.shield")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        let task = prompt
                        prompt = ""
                        agent.run(prompt: task, selection: agentSelection)
                    } label: {
                        Label("Agent starten", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(preferences.tintColor)
                    .disabled(
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        agent.workspaceURL == nil ||
                        agent.isRunning ||
                        agent.pendingAction != nil
                    )
                }
            }
            .padding(8)
            .agentComposerSurface(
                transparent: preferences.designMode == .transparentGlass && !reduceTransparency,
                tint: preferences.tintColor
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Sicher begrenzt")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Spacer()
                Text("LOKAL")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.09), in: Capsule())
            }
            safetyLine(agent.isUsingSandbox ? "Eigener Sandkasten" : "Gewählter Ordner", icon: "folder.badge.checkmark")
            safetyLine("Keine Shell", icon: "terminal.fill")
            safetyLine("Schreiben nur nach Freigabe", icon: "hand.raised.fill")
        }
        .agentSidebarSection()
    }

    private var welcomeCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(preferences.tintColor)
            Text("Gib dem Agenten einen sicheren Arbeitsbereich")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("Der Agent kann darin Textdateien lesen, Ordner überblicken und Änderungen vorbereiten. Nichts wird außerhalb dieses Ordners geöffnet oder geschrieben.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button {
                agent.chooseWorkspace()
            } label: {
                Label("Arbeitsordner wählen", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(preferences.tintColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .agentPanel(tint: preferences.tintColor.opacity(0.035))
    }

    private var readyCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(preferences.tintColor.opacity(0.10))
                    .frame(width: 54, height: 54)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(preferences.tintColor)
            }
            Text("Bereit für eine Aufgabe")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Beschreibe unten einfach das gewünschte Ergebnis. Der Agent zeigt dir jede Änderung, bevor etwas geschrieben wird.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func conversationRow(_ entry: AgentConversationEntry) -> some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 72) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: entry.role == .user ? "person.fill" : "sparkles")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(entry.role == .user ? "Du" : "Agent")
                        .font(.system(size: 10.5, weight: .semibold))
                    if let provider = entry.providerLabel {
                        Text(provider)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(entry.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 570, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                entry.role == .user ? preferences.tintColor.opacity(0.14) : .black.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(entry.role == .user ? 0.14 : 0.08), lineWidth: 0.7)
            )
            if entry.role == .agent { Spacer(minLength: 72) }
        }
    }

    private func approvalCard(_ action: AgentPendingAction) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.kind == .writeFile ? "Dateiänderung freigeben?" : "Finder-Aktion freigeben?")
                        .font(.system(size: 14, weight: .semibold))
                    Text(action.relativePath)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            if !action.reason.isEmpty {
                Text(action.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if action.kind == .writeFile, let content = action.proposedContent {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(action.previousContent == nil ? "Neue Datei" : "Vollständiger neuer Inhalt")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(content.utf8.count) Bytes")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    ScrollView(.vertical) {
                        Text(content)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                    }
                    .frame(maxHeight: 240)
                    .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if action.revealAfterWrite {
                Label("Nach dem Schreiben wird genau diese Datei im Finder markiert.", systemImage: "folder")
                    .font(.system(size: 10.8, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Ablehnen") { agent.rejectPendingAction() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(action.kind == .writeFile ? "Schreiben freigeben" : "Finder öffnen") {
                    agent.approvePendingAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .agentPanel(tint: .orange.opacity(0.09))
    }

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
    }

    private func safetyLine(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10.8, weight: .medium))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func planIcon(_ status: AgentPlanStatus) -> some View {
        switch status {
        case .waiting:
            Circle().stroke(.secondary.opacity(0.55), lineWidth: 1.2)
        case .active:
            ProgressView().controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func activityRow(_ activity: AgentActivity) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: activitySymbol(activity.kind))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(activityColor(activity.kind))
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.title)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(activity.date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                if !activity.detail.isEmpty {
                    Text(activity.detail)
                        .font(.system(size: 10.2))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func activitySymbol(_ kind: AgentActivityKind) -> String {
        switch kind {
        case .info: return "info.circle.fill"
        case .working: return "ellipsis.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    private func activityColor(_ kind: AgentActivityKind) -> Color {
        switch kind {
        case .info: return preferences.tintColor
        case .working: return .orange
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }
}

private extension View {
    func agentPanel(tint: Color) -> some View {
        padding(15)
            .stableGlass(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: tint
            )
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }

    func agentSidebarSection() -> some View {
        padding(.vertical, 2)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    func agentComposerSurface(transparent: Bool, tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if transparent {
            background(Color.clear, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.8))
                .transparentGlassContrastHalo()
        } else {
            adaptiveGlass(in: shape, tint: tint.opacity(0.07))
        }
    }
}
