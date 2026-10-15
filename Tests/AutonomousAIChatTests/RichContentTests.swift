import XCTest
@testable import AutonomousAIChat

final class RichContentTests: XCTestCase {
    func testAgentRejectsTraversalAbsoluteAndSensitivePaths() throws {
        XCTAssertThrowsError(try AgentWorkspaceFileSystem.validatedRelativePath("../secret.txt"))
        XCTAssertThrowsError(try AgentWorkspaceFileSystem.validatedRelativePath("/tmp/secret.txt"))
        XCTAssertThrowsError(try AgentWorkspaceFileSystem.validatedRelativePath(".env"))
        XCTAssertThrowsError(try AgentWorkspaceFileSystem.validatedRelativePath("notes/.ssh/key"))
        XCTAssertEqual(
            try AgentWorkspaceFileSystem.validatedRelativePath("Geschichten/abend.txt"),
            "Geschichten/abend.txt"
        )
    }

    func testAgentWriteNeedsCommitAndCreatesFileAtomically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileSystem = AgentWorkspaceFileSystem(root: root)
        let action = try await fileSystem.prepareWrite(
            relativePath: "Geschichten/kurz.txt",
            content: "Es war einmal.",
            reason: "Test",
            revealAfterWrite: false
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: action.targetURL.path))

        let writtenURL = try await fileSystem.commit(action)
        XCTAssertEqual(try String(contentsOf: writtenURL, encoding: .utf8), "Es war einmal.")
    }

    func testAgentWriteStopsOnConcurrentChange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("notiz.txt")
        try "Alt".write(to: target, atomically: true, encoding: .utf8)

        let fileSystem = AgentWorkspaceFileSystem(root: root)
        let action = try await fileSystem.prepareWrite(
            relativePath: "notiz.txt",
            content: "Neu",
            reason: "Test",
            revealAfterWrite: false
        )
        try "Änderung des Nutzers".write(to: target, atomically: true, encoding: .utf8)

        do {
            _ = try await fileSystem.commit(action)
            XCTFail("Konflikt muss das Schreiben verhindern")
        } catch let error as AgentFileSystemError {
            XCTAssertEqual(error, .conflict)
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "Änderung des Nutzers")
    }

    func testAgentBlocksSymlinkEscape() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideFile = outside.appendingPathComponent("secret.txt")
        try "privat".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"),
            withDestinationURL: outsideFile
        )

        let fileSystem = AgentWorkspaceFileSystem(root: root)
        do {
            _ = try await fileSystem.readFile(relativePath: "link.txt")
            XCTFail("Symlink-Flucht muss blockiert werden")
        } catch let error as AgentFileSystemError {
            XCTAssertEqual(error, .pathOutsideWorkspace)
        }
    }

    func testFileTasksCannotBeReportedCompleteWithoutToolEvidence() {
        XCTAssertTrue(AgentTaskPolicy.requiresFileTool("Erstelle eine Datei und öffne sie im Finder"))
        XCTAssertTrue(AgentTaskPolicy.requiresFileTool("Schreibe eine kurze Geschichte in notiz.txt"))
        XCTAssertFalse(AgentTaskPolicy.requiresFileTool("Erkläre mir kurz, was ein Agent ist"))
    }
    @MainActor
    func testDesignModesPersistWithoutChangingCurrentDesignDefaults() throws {
        let suiteName = "AutonomousAIChatTests.Design.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = Preferences(defaults: defaults, hasGeminiKeyOverride: false)
        XCTAssertEqual(initial.designMode, .current)
        XCTAssertEqual(initial.backgroundOpacity, DesignDefaults.currentBackgroundOpacity)
        XCTAssertEqual(initial.backgroundBlur, DesignDefaults.currentBackgroundBlur)

        initial.designMode = .transparentGlass
        initial.transparentBackgroundOpacity = 0
        initial.transparentBackgroundBlur = 19

        let reloaded = Preferences(defaults: defaults, hasGeminiKeyOverride: false)
        XCTAssertEqual(reloaded.designMode, .transparentGlass)
        XCTAssertEqual(reloaded.transparentBackgroundOpacity, 0)
        XCTAssertEqual(reloaded.transparentBackgroundBlur, 19)
        XCTAssertEqual(reloaded.backgroundOpacity, DesignDefaults.currentBackgroundOpacity)
        XCTAssertEqual(reloaded.backgroundBlur, DesignDefaults.currentBackgroundBlur)
    }

    @MainActor
    func testTransparentGlassResetAndStoredValueClamping() throws {
        let suiteName = "AutonomousAIChatTests.DesignClamp.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(4.2, forKey: "transparentBackgroundOpacityV18")
        defaults.set(-8.0, forKey: "transparentBackgroundBlurV18")
        let preferences = Preferences(defaults: defaults, hasGeminiKeyOverride: false)
        XCTAssertEqual(preferences.transparentBackgroundOpacity, 1)
        XCTAssertEqual(preferences.transparentBackgroundBlur, 0)

        preferences.resetTransparentGlassDesign()
        XCTAssertEqual(preferences.transparentBackgroundOpacity, DesignDefaults.transparentBackgroundOpacity)
        XCTAssertEqual(preferences.transparentBackgroundBlur, DesignDefaults.transparentBackgroundBlur)
    }

    func testTransparentGlassHidesOnlyTheEmptySingleChatPlaceholder() {
        XCTAssertFalse(EmptyConversationPolicy.shouldShowPlaceholder(
            chatMode: .single,
            designMode: .transparentGlass
        ))
        XCTAssertTrue(EmptyConversationPolicy.shouldShowPlaceholder(
            chatMode: .group,
            designMode: .transparentGlass
        ))
        XCTAssertTrue(EmptyConversationPolicy.shouldShowPlaceholder(
            chatMode: .single,
            designMode: .current
        ))
    }

    func testSparkleUpdateChannelUsesHTTPSAndValidEd25519PublicKey() throws {
        XCTAssertEqual(UpdateChannelPolicy.feedURL.scheme, "https")
        XCTAssertEqual(UpdateChannelPolicy.feedURL.lastPathComponent, "appcast.xml")
        XCTAssertEqual(Data(base64Encoded: UpdateChannelPolicy.publicEdKey)?.count, 32)
        XCTAssertEqual(UpdateChannelPolicy.scheduledCheckInterval, 86_400)
    }

    func testQwenCannotSpendOutputBudgetOnHiddenThinking() {
        XCTAssertFalse(OllamaRuntimePolicy.allowsHiddenThinking)
    }

    func testIncompleteOllamaEnvelopeIsNeverRenderedAsRawChatText() {
        XCTAssertEqual(AIService.unwrapOllamaStructuredReply(#"{"message":"Eine abgeschnittene Antwort"#), "")
        XCTAssertEqual(
            AIService.unwrapOllamaStructuredReply(#"{"message":"Gültige Antwort"}"#),
            "Gültige Antwort"
        )
    }

    func testBubbleWidthPolicyKeepsPlainTextCompactAndRichContentWide() {
        XCTAssertFalse(ChatBubbleLayoutPolicy.usesWideLayout(for: "Hallo"))
        XCTAssertLessThan(ChatBubbleLayoutPolicy.preferredWidth(for: "Hi"), 100)
        XCTAssertLessThan(ChatBubbleLayoutPolicy.preferredWidth(for: "Hallo, wie geht es dir?"), 240)
        XCTAssertTrue(ChatBubbleLayoutPolicy.usesWideLayout(
            for: "| Name | Preis |\n| --- | --- |\n| Döner | 8 € |"
        ))
        XCTAssertEqual(ChatBubbleLayoutPolicy.preferredWidth(
            for: "| Name | Preis |\n| --- | --- |\n| Döner | 8 € |"
        ), 560)
    }

    func testValidAndOrphanColoredTags() {
        let fragments = ColoredTextParser.parse("[red]Leon[/red], Anna[/green]")
        XCTAssertEqual(fragments.map(\.text).joined(), "Leon, Anna")
        XCTAssertEqual(fragments.first?.foreground, .red)
        XCTAssertEqual(fragments.last?.foreground, nil)
    }

    func testOpenTagEndsAtParagraphBoundary() {
        let fragments = ColoredTextParser.parse("[green]Erster Absatz\n\nZweiter Absatz")
        let first = fragments.first(where: { $0.text.contains("Erster") })
        let second = fragments.first(where: { $0.text.contains("Zweiter") })
        XCTAssertEqual(first?.foreground, .green)
        XCTAssertNil(second?.foreground)
    }

    func testNestedMarkAndColor() {
        let fragments = ColoredTextParser.parse("[mark][blue]Wichtig[/blue][/mark]")
        XCTAssertEqual(fragments, [
            ColoredTextFragment(text: "Wichtig", foreground: .blue, marked: true)
        ])
    }

    func testUnknownTagsRemainVisible() {
        let fragments = ColoredTextParser.parse("[custom]Text[/custom]")
        XCTAssertEqual(fragments.map(\.text).joined(), "[custom]Text[/custom]")
    }

    func testStandardMarkdownTable() {
        let blocks = RichMessageParser.parse("| Jahr | Preis |\n| --- | --- |\n| 2024 | 8 € |")
        guard case .table(let table) = blocks.first else {
            return XCTFail("Tabelle wurde nicht erkannt")
        }
        XCTAssertEqual(table.headers, ["Jahr", "Preis"])
        XCTAssertEqual(table.rows, [["2024", "8 €"]])
    }

    func testSingleLineWeakModelTableIsRepaired() {
        let input = "Hier ist die Tabelle: | Preise | | 6 € | | 7 € | | 8 € |"
        let blocks = RichMessageParser.parse(input)
        let table = blocks.compactMap { block -> TablePayload? in
            if case .table(let value) = block { return value }
            return nil
        }.first
        XCTAssertEqual(table?.headers, ["Preise"])
        XCTAssertEqual(table?.rows, [["6 €"], ["7 €"], ["8 €"]])
    }

    func testPipeInProseDoesNotBecomeTable() {
        let blocks = RichMessageParser.parse("A | B ist nur ein Vergleich im Satz.")
        XCTAssertEqual(blocks, [.text("A | B ist nur ein Vergleich im Satz.")])
    }

    func testSimpleNativeChartPayload() {
        let json = #"{"type":"line","title":"Preise","seriesName":"Euro","labels":["2023","2024"],"values":[7,8.5]}"#
        let chart = ChartPayloadParser.parse(json)
        XCTAssertEqual(chart?.kind, .line)
        XCTAssertEqual(chart?.points.map(\.value), [7, 8.5])
    }

    func testChartRejectsMismatchedArrays() {
        let json = #"{"type":"bar","labels":["A"],"values":[1,2]}"#
        XCTAssertNil(ChartPayloadParser.parse(json))
    }

    func testResponseIntentPrecedence() {
        XCTAssertEqual(ResponseIntent.detect(userText: "Mach eine Tabelle", webRequested: false), .table)
        XCTAssertEqual(ResponseIntent.detect(userText: "Recherchiere und mach eine Tabelle", webRequested: true), .research(.table))
        XCTAssertEqual(ResponseIntent.detect(userText: "Färbe Leon rot", webRequested: false), .coloredText)
    }

    func testResearchValidatorAcceptsExactEvidence() {
        let source = WebSource(title: "Quelle", url: "https://example.com")
        let evidence = [ResearchEvidence(
            sourceNumber: 1,
            source: source,
            content: "Der bestätigte Preis beträgt acht Euro im Jahr 2024."
        )]
        let envelope = OllamaResearchEnvelope(claims: [
            EvidenceClaim(
                text: "Der Preis beträgt 2024 acht Euro.",
                evidence: [EvidenceReference(sourceID: 1, quote: "bestätigte Preis beträgt acht Euro")]
            )
        ])
        let answer = ResearchAnswerValidator.validate(envelope, evidence: evidence)
        XCTAssertEqual(answer?.text, "Der Preis beträgt 2024 acht Euro. [S1]")
        XCTAssertEqual(answer?.citations.first?.sourceID, source.id)
    }

    func testResearchValidatorRejectsInventedQuoteAndSource() {
        let source = WebSource(title: "Quelle", url: "https://example.com")
        let evidence = [ResearchEvidence(sourceNumber: 1, source: source, content: "Belegter Inhalt")]
        XCTAssertNil(ResearchAnswerValidator.validate(
            OllamaResearchEnvelope(claims: [
                EvidenceClaim(text: "Erfunden", evidence: [EvidenceReference(sourceID: 2, quote: "Gibt es nicht")])
            ]),
            evidence: evidence
        ))
    }

    func testValidatedResearchCanBecomeNativeChart() {
        let source = WebSource(title: "Quelle", url: "https://example.com/data")
        let answer = ValidatedResearchAnswer(
            text: "Januar: 2 [S1]\n\nFebruar: 5 [S1]",
            citations: [],
            sources: [source]
        )

        let rendered = answer.canonicalChartText()
        XCTAssertNotNil(rendered)
        XCTAssertTrue(rendered?.contains("```chart") == true)
        XCTAssertTrue(rendered?.contains("Januar: 2 [S1]") == true)
    }

    func testLegacyMessageWithoutV18MetadataDecodes() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","speaker":"alice","text":"Hallo","date":0}"#
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.text, "Hallo")
        XCTAssertNil(message.citations)
        XCTAssertNil(message.researchStatus)
    }
}
