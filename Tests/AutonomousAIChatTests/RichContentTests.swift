import XCTest
@testable import AutonomousAIChat

final class RichContentTests: XCTestCase {
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
