import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var viewModel: ChatViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft = ""
    @State private var showParticipants = false
    @State private var showTopicEditor = false
    @State private var isAtBottom = true
    @State private var newestMessageScrollRequest = 0
    @State private var isHoveringNewChat = false
    @State private var showIssueDetails = false
    @State private var pendingScrollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .transparentGlassContrastHalo()
                Divider().opacity(0.16)
                conversation
                issueArea
                composer
            }
        }
        .environment(\.transparentGlassModeEnabled, preferences.designMode == .transparentGlass)
        .clipShape(TopRoundedRectangle(radius: 28))
        .background(WindowAccessor())
        .popover(isPresented: $showTopicEditor, arrowEdge: .top) {
            TopicEditorPopover()
                .environmentObject(preferences)
                .frame(width: 360)
                .padding(14)
        }
        .onAppear {
            if preferences.chatMode == .single {
                viewModel.startFreshSingleChat()
            } else {
                viewModel.start()
            }
            newestMessageScrollRequest &+= 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.start()
                newestMessageScrollRequest &+= 1
            } else if phase == .background {
                viewModel.stop()
            }
        }
        .onDisappear {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
            viewModel.stop()
        }
    }

    @ViewBuilder
    private var background: some View {
        switch preferences.designMode {
        case .current:
            // This is the original v18 background. Keep this branch visually
            // unchanged so switching back restores the exact current design.
            ZStack {
                VisualEffectBackdrop(material: .hudWindow)
                    .blur(radius: preferences.backgroundBlur * 0.22)

                preferences.tintColor
                    .opacity(preferences.backgroundOpacity)
                    .blendMode(.softLight)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.075),
                        Color.clear,
                        Color.black.opacity(0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

        case .transparentGlass:
            transparentGlassBackground
        }
    }

    @ViewBuilder
    private var transparentGlassBackground: some View {
        if reduceTransparency {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                preferences.tintColor.opacity(0.08)
            }
        } else if preferences.transparentBackgroundOpacity <= 0 {
            Color.clear
        } else {
            ZStack {
                VisualEffectBackdrop(material: .underWindowBackground)
                    .opacity(preferences.transparentBackgroundOpacity)
                    .blur(radius: preferences.transparentBackgroundBlur * 0.22)

                preferences.tintColor
                    .opacity(preferences.transparentBackgroundOpacity * 0.30)
                    .blendMode(.softLight)

                LinearGradient(
                    colors: [
                        Color.white.opacity(preferences.transparentBackgroundOpacity * 0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preferences.chatMode == .group ? "Autonomer KI-Gruppenchat" : "KI-Chat")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            if let speaker = viewModel.typingSpeaker {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("\(preferences.chatDisplayName(for: speaker)) schreibt…")
                    Button {
                        viewModel.cancelCurrentGeneration()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Antwort abbrechen")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            } else if viewModel.isRefreshingMemory {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text("Gedächtnis wird aktualisiert")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }

            if preferences.showMessageCount {
                Text("\(viewModel.messages.count) Nachrichten")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .adaptiveGlass(in: Capsule(), tint: .white.opacity(0.035))
            }

            if preferences.chatMode == .single {
                Button {
                    performAnimation(.easeOut(duration: 0.16)) {
                        viewModel.startFreshSingleChat()
                        draft = ""
                        isAtBottom = true
                        newestMessageScrollRequest &+= 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12.5, weight: .bold))
                            .frame(width: 18, height: 18)

                        if isHoveringNewChat {
                            Text("Neuer Chat")
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .frame(width: isHoveringNewChat ? 104 : 34, height: 30)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .adaptiveGlass(in: Capsule(), tint: .white.opacity(0.055), interactive: true)
                .onHover { hovering in
                    performAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        isHoveringNewChat = hovering
                    }
                }
                .help("Leeren KI-Chat starten")
            }

            Button {
                performAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showParticipants.toggle()
                }
            } label: {
                Image(systemName: "person.2")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveGlass(in: Capsule(), tint: .white.opacity(0.055), interactive: true)
            .help("Teilnehmer")
            .popover(isPresented: $showParticipants, arrowEdge: .top) {
                ParticipantsPopover(onEditTopic: {
                    showParticipants = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        showTopicEditor = true
                    }
                })
                    .environmentObject(preferences)
                    .environmentObject(viewModel)
                    .frame(width: 270)
                    .padding(14)
                    .adaptiveGlass(
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                        tint: preferences.tintColor.opacity(0.10)
                    )
                    .padding(6)
            }
        }
        .padding(.leading, 86)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 58)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(
                                speaker: message.speaker,
                                displayName: preferences.chatDisplayName(for: message.speaker),
                                initial: preferences.chatInitial(for: message.speaker),
                                text: message.text,
                                date: message.date,
                                sources: message.sources ?? [],
                                citations: message.citations ?? [],
                                researchStatus: message.researchStatus
                            )
                            .id(message.id)
                            .transition(
                                .move(edge: .bottom)
                                .combined(with: .opacity)
                            )
                        }

                        if viewModel.messages.isEmpty,
                           EmptyConversationPolicy.shouldShowPlaceholder(
                               chatMode: preferences.chatMode,
                               designMode: preferences.designMode
                           ) {
                            EmptyConversationView(mode: preferences.chatMode, aiName: preferences.chatDisplayName(for: .alice))
                                .transparentGlassReadabilityPanel(cornerRadius: 20)
                                .padding(.top, 70)
                                .padding(.bottom, 30)
                        }

                        if let speaker = viewModel.typingSpeaker {
                            TypingChatBubble(
                                speaker: speaker,
                                displayName: preferences.chatDisplayName(for: speaker),
                                initial: preferences.chatInitial(for: speaker)
                            )
                            .id("typing-indicator")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom")
                            .onAppear { isAtBottom = true }
                            .onDisappear { isAtBottom = false }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    // Always open the chat at the newest message.
                    scheduleScrollToBottom(proxy, delayMilliseconds: 120, animated: false)
                }
                .onChange(of: newestMessageScrollRequest) { _, _ in
                    scheduleScrollToBottom(proxy, delayMilliseconds: 60, animated: false)
                }
                .onChange(of: viewModel.selectedSessionID) { _, _ in
                    scheduleScrollToBottom(proxy, delayMilliseconds: 80, animated: false)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    let shouldFollow = isAtBottom || viewModel.messages.last?.speaker == .user
                    if shouldFollow {
                        scheduleScrollToBottom(proxy, delayMilliseconds: 20, animated: true)
                    }
                }
                .onChange(of: viewModel.streamTick) { _, _ in
                    guard isAtBottom else { return }
                    scheduleScrollToBottom(proxy, delayMilliseconds: 55, animated: false)
                }
                .onChange(of: viewModel.typingSpeaker) { _, speaker in
                    guard speaker != nil, isAtBottom else { return }
                    scheduleScrollToBottom(proxy, delayMilliseconds: 35, animated: true)
                }

                if !isAtBottom, !viewModel.messages.isEmpty {
                    Button {
                        scrollToBottom(proxy, animated: true)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .adaptiveGlass(in: Circle(), tint: preferences.tintColor.opacity(0.18), interactive: true)
                    .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
                    .padding(.trailing, 24)
                    .padding(.bottom, 18)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .help("Zu den neuesten Nachrichten")
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.28)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
        isAtBottom = true
    }

    private func scheduleScrollToBottom(
        _ proxy: ScrollViewProxy,
        delayMilliseconds: Int,
        animated: Bool
    ) {
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy, animated: animated)
        }
    }

    @ViewBuilder
    private var issueArea: some View {
        if viewModel.lastError != nil || viewModel.providerNotice != nil {
            HStack {
                Spacer(minLength: 18)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        Image(systemName: viewModel.lastError == nil
                              ? "arrow.triangle.2.circlepath.circle.fill"
                              : "exclamationmark.triangle.fill")
                            .foregroundStyle(viewModel.lastError == nil ? .orange : .red)
                        Text(issueSummary)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if viewModel.lastError != nil {
                            Button("Wiederholen") {
                                Task { await viewModel.retryLastFailure() }
                            }
                            .buttonStyle(.borderless)
                        }
                        Button {
                            performAnimation(.easeOut(duration: 0.16)) {
                                showIssueDetails.toggle()
                            }
                        } label: {
                            Image(systemName: showIssueDetails ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .help("Details")
                        Button {
                            viewModel.dismissCurrentIssue()
                            showIssueDetails = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Hinweis schließen")
                    }

                    if showIssueDetails {
                        VStack(alignment: .leading, spacing: 4) {
                            if let notice = viewModel.providerNotice {
                                Text(notice)
                            }
                            if let error = viewModel.lastError {
                                Text(error)
                                    .textSelection(.enabled)
                            }
                            if let eventID = viewModel.lastErrorEventID {
                                Text("Fehler-ID: \(eventID)")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 620)
                .adaptiveGlass(
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    tint: (viewModel.lastError == nil ? Color.orange : Color.red).opacity(0.09)
                )
                .shadow(color: .black.opacity(0.045), radius: 9, y: 3)
                Spacer(minLength: 18)
            }
            .padding(.vertical, 7)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var issueSummary: String {
        guard let error = viewModel.lastError else {
            return viewModel.providerNotice ?? "Anbieterhinweis"
        }
        let lower = error.lowercased()
        if lower.contains("429") || lower.contains("quota") { return "Anbieter-Limit erreicht" }
        if lower.contains("timed out") || lower.contains("zu lange") { return "Antwort hat zu lange gedauert" }
        if lower.contains("kein lokales ollama") || lower.contains("no ollama") { return "Kein lokales Ollama-Modell verfügbar" }
        if lower.contains("web") || lower.contains("search") { return "Webrecherche fehlgeschlagen" }
        return "Antwort konnte nicht erzeugt werden"
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.10)

            composerInputSurface {
                HStack(spacing: 10) {
                    TextField(preferences.chatMode == .group ? "Nachricht an die Gruppe…" : "Nachricht schreiben…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .lineLimit(1...4)
                        .padding(.leading, 16)
                        .padding(.vertical, 12)
                        .onSubmit(send)

                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                    .adaptiveGlass(
                        in: Circle(),
                        tint: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.white.opacity(0.025)
                            : preferences.tintColor.opacity(0.20),
                        interactive: true
                    )
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(7)
            }
            .shadow(color: .black.opacity(0.050), radius: 13, y: 4)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .background {
            if preferences.designMode == .current || reduceTransparency {
                Color.white.opacity(0.050)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func composerInputSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if preferences.designMode == .transparentGlass && !reduceTransparency {
            content()
                .background(Color.clear, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.8))
                .transparentGlassContrastHalo()
        } else {
            content()
                .adaptiveGlass(in: shape, tint: .white.opacity(0.028))
        }
    }

    private var headerSubtitle: String {
        if preferences.chatMode == .single {
            let provider = preferences.provider(for: .alice).displayName
            return "\(preferences.chatDisplayName(for: .alice))  ·  \(provider)"
        }
        return "\(preferences.name(for: .alice))  •  \(preferences.name(for: .bob))  ·  \(viewModel.selectedSessionTitle)"
    }

    private func send() {
        let message = draft
        draft = ""
        isAtBottom = true
        viewModel.sendUserMessage(message)
    }

    private func performAnimation(_ animation: Animation, updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

private struct TypingChatBubble: View {
    let speaker: ChatSpeaker
    let displayName: String
    let initial: String

    private var tint: Color {
        switch speaker {
        case .alice: return .pink
        case .bob: return .cyan
        case .user: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if speaker == .bob || speaker == .user {
                Spacer(minLength: 90)
            }

            if speaker == .alice {
                avatar
            }

            VStack(alignment: speaker == .alice ? .leading : .trailing, spacing: 4) {
                Text("\(displayName) schreibt…")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.90))
                    .padding(.horizontal, 7)

                TypingDots()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .stableGlass(
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                        tint: tint.opacity(0.11)
                    )
                    .shadow(color: .black.opacity(0.045), radius: 8, y: 3)
            }

            if speaker == .bob { avatar }
            if speaker == .alice { Spacer(minLength: 90) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName) schreibt")
    }

    private var avatar: some View {
        Text(initial)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .frame(width: 28, height: 28)
            .stableGlass(in: Circle(), tint: tint.opacity(0.16))
    }
}

private struct TypingDots: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6.5, height: 6.5)
                    .opacity(0.42 + Double(index) * 0.20)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

private struct EmptyConversationView: View {
    let mode: ChatMode
    let aiName: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: mode == .group ? "bubble.left.and.bubble.right" : "bubble.left")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text(mode == .group ? "Du startest das Gespräch" : "Neuer KI-Chat")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(mode == .group
                 ? "Schreib einfach die erste Nachricht. Alice und Bob reagieren darauf und führen das Gespräch danach weiter."
                 : "Schreib deine erste Nachricht an \(aiName). Es gibt keine automatisch erzeugte Startnachricht.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ChatBubble: View {
    let speaker: ChatSpeaker
    let displayName: String
    let initial: String
    let text: String
    let date: Date
    let sources: [WebSource]
    let citations: [InlineCitation]
    let researchStatus: ResearchStatus?

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if speaker == .bob || speaker == .user {
                Spacer(minLength: 90)
            }

            if speaker == .alice {
                avatar
            }

            VStack(alignment: speaker == .alice ? .leading : .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Text(displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(nameColor)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(date, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                }
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 8)

                sizedBubble

                if let researchStatus {
                    HStack(spacing: 5) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(researchStatus.displayText)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10.2, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                }

                if !sources.isEmpty {
                    SourceChips(sources: sources)
                        .padding(.horizontal, 6)
                }
            }
            .frame(maxWidth: 570, alignment: speaker == .alice ? .leading : .trailing)

            if speaker == .bob {
                avatar
            }

            if speaker == .alice {
                Spacer(minLength: 90)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var sizedBubble: some View {
        bubbleSurface
            .frame(width: ChatBubbleLayoutPolicy.preferredWidth(for: text), alignment: .leading)
    }

    private var bubbleSurface: some View {
        RichMessageContent(text: text, sources: sources)
            .font(.system(size: 14.5, weight: .regular))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .stableGlass(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: bubbleTint
            )
            .shadow(color: .black.opacity(0.055), radius: 10, y: 3)
    }

    private var avatar: some View {
        Text(initial)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .frame(width: 30, height: 30)
            .stableGlass(in: Circle(), tint: bubbleTint.opacity(0.88))
    }

    private var bubbleTint: Color {
        switch speaker {
        case .alice: return Color.pink.opacity(0.17)
        case .bob: return Color.cyan.opacity(0.14)
        case .user: return Color.white.opacity(0.095)
        }
    }

    private var nameColor: Color {
        switch speaker {
        case .alice: return .pink
        case .bob: return .cyan
        case .user: return .secondary
        }
    }
}

private struct SourceChips: View {
    let sources: [WebSource]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(sources.prefix(3)) { source in
                Button {
                    if let url = URL(string: source.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(source.title)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.045), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(source.url)
            }
        }
        .transparentGlassReadabilityPanel(cornerRadius: 12)
    }
}

private struct ParticipantsPopover: View {
    let onEditTopic: () -> Void
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Chat")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(viewModel.selectedSessionTitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Picker("Modus", selection: Binding(
                get: { preferences.chatMode },
                set: { viewModel.setChatMode($0) }
            )) {
                ForEach(ChatMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                Button {
                    viewModel.createSession()
                } label: {
                    Label(preferences.chatMode == .group ? "Neuer Gruppen-Chat" : "Neuer KI-Chat", systemImage: "plus")
                }

                Divider()

                if preferences.chatMode == .group {
                    ForEach(viewModel.sessions.filter { ($0.mode ?? .group) == .group }) { session in
                        Button {
                            viewModel.selectSession(session.id)
                        } label: {
                            if session.id == viewModel.selectedSessionID {
                                Label(session.title, systemImage: "checkmark")
                            } else {
                                Text(session.title)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                    Text(preferences.chatMode == .group ? "Chats & neuer Chat" : "Neuen KI-Chat starten")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton)

            Divider().opacity(0.42)

            Text(preferences.chatMode == .group ? "Teilnehmer" : "Aktive KI")
                .font(.system(size: 12.5, weight: .semibold))

            participant(
                speaker: .alice,
                color: .pink,
                subtitle: viewModel.typingSpeaker == .alice ? "schreibt…" : "\(preferences.provider(for: .alice).displayName) · \(preferences.model(for: .alice))"
            )

            if preferences.chatMode == .group {
                participant(
                    speaker: .bob,
                    color: .cyan,
                    subtitle: viewModel.typingSpeaker == .bob ? "schreibt…" : "\(preferences.provider(for: .bob).displayName) · \(preferences.model(for: .bob))"
                )
                participant(speaker: .user, color: .secondary, subtitle: "Beobachter / Teilnehmer")
            }

            Divider().opacity(0.42)

            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gesprächsthema")
                        .font(.system(size: 11.5, weight: .semibold))
                    let topic = preferences.conversationTopic.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(topic.isEmpty ? "Freies Gespräch" : topic)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Ändern") { onEditTopic() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5, weight: .medium))
            }

            Divider().opacity(0.42)

            if preferences.chatMode == .group {
                HStack {
                    Circle()
                        .fill(preferences.autonomousEnabled ? .green : .secondary)
                        .frame(width: 7, height: 7)
                    Text(preferences.autonomousEnabled ? "Autonomes Gespräch läuft" : "Autonomes Gespräch pausiert")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $preferences.autonomousEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            } else {
                Label("Normaler KI-Chat: Die KI antwortet nur auf dich.", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func participant(speaker: ChatSpeaker, color: Color, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.72))
                .frame(width: 24, height: 24)
                .overlay {
                    Text(preferences.chatInitial(for: speaker))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(preferences.chatDisplayName(for: speaker))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(subtitle.isEmpty ? "KI" : subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

private struct TopicEditorPopover: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var draftTopic = ""

    private let suggestions = ["KI in 2035", "Neue App-Ideen", "Philosophie"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tag")
                Text("Gesprächsthema")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            TextField("Freies Gespräch", text: $draftTopic)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { draftTopic = suggestion }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack {
                Button("Freies Gespräch") {
                    draftTopic = ""
                    preferences.conversationTopic = ""
                }
                Spacer()
                Button("Übernehmen") {
                    preferences.conversationTopic = draftTopic.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Das Thema ist optional. Ein neuer Chat startet trotzdem erst, wenn du selbst die erste Nachricht sendest.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { draftTopic = preferences.conversationTopic }
    }
}
