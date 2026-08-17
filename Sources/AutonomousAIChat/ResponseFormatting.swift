import Foundation

enum ResponseIntent: Equatable, Sendable {
    enum Presentation: Equatable, Sendable {
        case text
        case table
        case chart
    }

    case plain
    case coloredText
    case table
    case chart
    case research(Presentation)

    static func detect(userText: String, webRequested: Bool) -> ResponseIntent {
        let lower = userText.lowercased()
        let wantsTable = ["tabelle", "table", "tabellar", "vergleichstabelle"].contains {
            lower.contains($0)
        }
        let wantsChart = ["diagramm", "chart", "kurve", "balkendiagramm", "liniendiagramm"].contains {
            lower.contains($0)
        }
        let wantsColor = ["farbig", "farbe", "färbe", "faerbe", "markiere", "[red]", "[green]"].contains {
            lower.contains($0)
        }

        if webRequested {
            if wantsTable { return .research(.table) }
            if wantsChart { return .research(.chart) }
            return .research(.text)
        }
        if wantsTable { return .table }
        if wantsChart { return .chart }
        if wantsColor { return .coloredText }
        return .plain
    }

    var isStructured: Bool {
        switch self {
        case .plain, .coloredText: return false
        case .table, .chart, .research: return true
        }
    }

    var isResearch: Bool {
        if case .research = self { return true }
        return false
    }
}

struct OllamaTableEnvelope: Codable, Equatable, Sendable {
    let intro: String?
    let columns: [String]
    let rows: [[String]]
    let note: String?

    func canonicalText() -> String? {
        guard !columns.isEmpty,
              !rows.isEmpty,
              rows.allSatisfy({ $0.count == columns.count }) else { return nil }

        let safeColumns = columns.map(Self.escapeCell)
        let header = "| " + safeColumns.joined(separator: " | ") + " |"
        let separator = "| " + Array(repeating: "---", count: columns.count).joined(separator: " | ") + " |"
        let body = rows.map { row in
            "| " + row.map(Self.escapeCell).joined(separator: " | ") + " |"
        }.joined(separator: "\n")
        return [intro.trimmedNil, header, separator, body, note.trimmedNil]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    private static func escapeCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OllamaChartEnvelope: Codable, Equatable, Sendable {
    let intro: String?
    let type: String
    let title: String
    let seriesName: String
    let labels: [String]
    let values: [Double]
    let note: String?

    func canonicalText() -> String? {
        guard ChartPayloadParser.parse(chartJSON) != nil else { return nil }
        return [intro.trimmedNil, "```chart\n\(chartJSON)\n```", note.trimmedNil]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    private var chartJSON: String {
        let object: [String: Any] = [
            "type": type,
            "title": title,
            "seriesName": seriesName,
            "labels": labels,
            "values": values
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
}

struct EvidenceReference: Codable, Equatable, Sendable {
    let sourceID: Int
    let quote: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case quote
    }
}

struct EvidenceClaim: Codable, Equatable, Sendable {
    let text: String
    let evidence: [EvidenceReference]
}

struct OllamaResearchEnvelope: Codable, Equatable, Sendable {
    let claims: [EvidenceClaim]
}

struct ResearchEvidence: Equatable, Sendable {
    let sourceNumber: Int
    let source: WebSource
    let content: String
}

struct ValidatedResearchAnswer: Equatable, Sendable {
    let text: String
    let citations: [InlineCitation]
    let sources: [WebSource]

    /// Builds a native chart only from numbers that already survived evidence validation.
    /// The original cited claims remain below the chart so every plotted value stays auditable.
    func canonicalChartText() -> String? {
        let markerPattern = #"\s*\[S\d+\]"#
        let numberPattern = #"[-+]?\d+(?:[.,]\d+)?"#
        guard let markerRegex = try? NSRegularExpression(pattern: markerPattern),
              let numberRegex = try? NSRegularExpression(pattern: numberPattern) else { return nil }

        var labels: [String] = []
        var values: [Double] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            let fullRange = NSRange(paragraph.startIndex..., in: paragraph)
            let claim = markerRegex.stringByReplacingMatches(
                in: paragraph,
                range: fullRange,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let claimRange = NSRange(claim.startIndex..., in: claim)
            guard let match = numberRegex.firstMatch(in: claim, range: claimRange),
                  let valueRange = Range(match.range, in: claim),
                  let value = Double(claim[valueRange].replacingOccurrences(of: ",", with: ".")) else { continue }

            var label = String(claim[..<valueRange.lowerBound])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            if label.isEmpty {
                label = "Wert \(labels.count + 1)"
            }
            labels.append(String(label.prefix(48)))
            values.append(value)
        }

        guard labels.count >= 2, labels.count == values.count else { return nil }
        let chart = OllamaChartEnvelope(
            intro: nil,
            type: "bar",
            title: "Belegte Recherchewerte",
            seriesName: "Wert",
            labels: labels,
            values: values,
            note: nil
        )
        guard let chartText = chart.canonicalText() else { return nil }
        return chartText + "\n\n" + text
    }
}

enum ResearchAnswerValidator {
    static func validate(
        _ envelope: OllamaResearchEnvelope,
        evidence: [ResearchEvidence]
    ) -> ValidatedResearchAnswer? {
        let byNumber = Dictionary(uniqueKeysWithValues: evidence.map { ($0.sourceNumber, $0) })
        var textParts: [String] = []
        var citations: [InlineCitation] = []
        var byteCursor = 0

        for claim in envelope.claims {
            let claimText = claim.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !claimText.isEmpty, !claim.evidence.isEmpty else { return nil }

            var validReferences: [(EvidenceReference, ResearchEvidence)] = []
            for reference in claim.evidence {
                guard let source = byNumber[reference.sourceID],
                      Self.quote(reference.quote, occursIn: source.content) else { return nil }
                validReferences.append((reference, source))
            }

            if !textParts.isEmpty { byteCursor += 2 }
            let start = byteCursor
            byteCursor += claimText.utf8.count
            let end = byteCursor

            let uniqueReferences = validReferences.reduce(into: [(EvidenceReference, ResearchEvidence)]()) { partial, item in
                if !partial.contains(where: { $0.1.sourceNumber == item.1.sourceNumber }) {
                    partial.append(item)
                }
            }
            let markers = uniqueReferences.map { "[S\($0.1.sourceNumber)]" }.joined(separator: "")
            textParts.append(claimText + " " + markers)
            byteCursor += 1 + markers.utf8.count

            for (reference, source) in uniqueReferences {
                citations.append(InlineCitation(
                    sourceID: source.source.id,
                    startUTF8Offset: start,
                    endUTF8Offset: end,
                    evidenceQuote: reference.quote
                ))
            }
        }

        guard !textParts.isEmpty else { return nil }
        let sources = evidence.sorted { $0.sourceNumber < $1.sourceNumber }.map(\.source)
        return ValidatedResearchAnswer(
            text: textParts.joined(separator: "\n\n"),
            citations: citations,
            sources: sources
        )
    }

    static func quote(_ quote: String, occursIn content: String) -> Bool {
        let needle = normalize(quote)
        guard needle.count >= 8 else { return false }
        return normalize(content).contains(needle)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private extension Optional where Wrapped == String {
    var trimmedNil: String? {
        guard let self else { return nil }
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
