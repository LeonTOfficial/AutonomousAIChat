import SwiftUI
import Charts
import WebKit

struct RichMessageContent: View {
    let text: String
    let sources: [WebSource]

    init(text: String, sources: [WebSource] = []) {
        self.text = text
        self.sources = sources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(RichMessageParser.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SafeColoredText(text: value, sources: sources)
                    }
                case .table(let table):
                    NativeTableView(table: table)
                case .mermaid(let source):
                    MermaidDiagramView(source: source)
                        .frame(minHeight: 210, idealHeight: 230, maxHeight: 300)
                case .chart(let chart):
                    NativeChartView(chart: chart)
                        .frame(minHeight: 230, idealHeight: 250, maxHeight: 310)
                case .code(let language, let source):
                    CodeBlockView(language: language, source: source)
                }
            }
        }
    }
}

enum RichMessageBlock: Equatable, Sendable {
    case text(String)
    case table(TablePayload)
    case mermaid(String)
    case chart(ChartPayload)
    case code(language: String, source: String)
}

enum ChatBubbleLayoutPolicy {
    private static let wideWidth: CGFloat = 560

    static func usesWideLayout(for text: String) -> Bool {
        RichMessageParser.parse(text).contains { block in
            switch block {
            case .table, .chart, .mermaid, .code: return true
            case .text: return false
            }
        }
    }

    static func preferredWidth(for text: String) -> CGFloat {
        if usesWideLayout(for: text) { return wideWidth }

        let visibleText = ColoredTextParser.parse(text).map(\.text).joined()
        let longestLine = visibleText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(\.count)
            .max() ?? 0
        let estimatedTextWidth = CGFloat(longestLine) * 7.35 + 28
        return min(max(estimatedTextWidth, 74), 540)
    }
}

struct TablePayload: Equatable, Sendable {
    let headers: [String]
    let rows: [[String]]

    var columnCount: Int { headers.count }
}

struct ChartPayload: Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case bar
        case line
        case area

        init(modelValue: String?) {
            switch modelValue?.lowercased() {
            case "line": self = .line
            case "area": self = .area
            default: self = .bar
            }
        }
    }

    struct Point: Identifiable, Equatable, Sendable {
        let id: Int
        let label: String
        let value: Double
    }

    let kind: Kind
    let title: String?
    let seriesName: String?
    let points: [Point]
}

enum RichMessageParser {
    private final class CacheBox: NSObject {
        let blocks: [RichMessageBlock]

        init(_ blocks: [RichMessageBlock]) {
            self.blocks = blocks
        }
    }

    private final class ParserCache: @unchecked Sendable {
        let storage: NSCache<NSString, CacheBox>

        init() {
            storage = NSCache<NSString, CacheBox>()
            storage.countLimit = 256
            storage.totalCostLimit = 1_500_000
        }
    }

    private static let cache = ParserCache()

    static func parse(_ raw: String) -> [RichMessageBlock] {
        let key = raw as NSString
        if let cached = cache.storage.object(forKey: key) {
            return cached.blocks
        }

        let blocks = parseUncached(raw)
        cache.storage.setObject(CacheBox(blocks), forKey: key, cost: raw.utf16.count)
        return blocks
    }

    private static func parseUncached(_ raw: String) -> [RichMessageBlock] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let regex = try? NSRegularExpression(
            pattern: "```([A-Za-z0-9_-]*)\\n([\\s\\S]*?)```",
            options: []
        ) else {
            return parseTextBlocks(normalized)
        }

        let ns = normalized as NSString
        let matches = regex.matches(
            in: normalized,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        guard !matches.isEmpty else { return parseTextBlocks(normalized) }

        var result: [RichMessageBlock] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                result.append(contentsOf: parseTextBlocks(ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                ))))
            }

            let language = match.range(at: 1).location == NSNotFound
                ? ""
                : ns.substring(with: match.range(at: 1)).lowercased()
            let source = match.range(at: 2).location == NSNotFound
                ? ""
                : ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)

            switch language {
            case "mermaid", "mmd", "diagram", "diagramm", "flowchart", "graph":
                result.append(.mermaid(source))
            case "chart", "chartjs", "chart-js", "json-chart", "leon-chart":
                if let chart = ChartPayloadParser.parse(source) {
                    result.append(.chart(chart))
                } else {
                    result.append(.code(language: language, source: source))
                }
            default:
                result.append(.code(language: language, source: source))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            result.append(contentsOf: parseTextBlocks(ns.substring(from: cursor)))
        }

        return result.isEmpty ? [.text(normalized)] : result
    }

    private static func parseTextBlocks(_ raw: String) -> [RichMessageBlock] {
        let repaired = repairSingleLinePipeRows(raw)
        let lines = repaired.components(separatedBy: "\n")
        var result: [RichMessageBlock] = []
        var textLines: [String] = []
        var index = 0

        func flushText() {
            guard !textLines.isEmpty else { return }
            result.append(.text(textLines.joined(separator: "\n")))
            textLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            if let table = markdownTable(startingAt: index, lines: lines) {
                flushText()
                result.append(.table(table.payload))
                index = table.nextIndex
            } else {
                textLines.append(lines[index])
                index += 1
            }
        }
        flushText()
        return result
    }

    private static func markdownTable(
        startingAt start: Int,
        lines: [String]
    ) -> (payload: TablePayload, nextIndex: Int)? {
        guard start < lines.count, let first = pipeCells(lines[start]), !first.isEmpty else { return nil }

        if start + 1 < lines.count,
           let separator = pipeCells(lines[start + 1]),
           separator.count == first.count,
           separator.allSatisfy(isSeparatorCell) {
            var rows: [[String]] = []
            var cursor = start + 2
            while cursor < lines.count,
                  let cells = pipeCells(lines[cursor]),
                  cells.count == first.count {
                rows.append(cells)
                cursor += 1
            }
            guard !rows.isEmpty else { return nil }
            return (TablePayload(headers: first, rows: rows), cursor)
        }

        // Schwächere Modelle erzeugen gelegentlich mehrere "| Zelle |"-Zeilen
        // ohne Markdown-Trennzeile. Ab drei Zeilen ist die Absicht eindeutig genug.
        var candidates: [[String]] = [first]
        var cursor = start + 1
        while cursor < lines.count,
              let cells = pipeCells(lines[cursor]),
              cells.count == first.count {
            candidates.append(cells)
            cursor += 1
        }
        guard candidates.count >= 3 else { return nil }
        return (TablePayload(headers: candidates[0], rows: Array(candidates.dropFirst())), cursor)
    }

    private static func pipeCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }
        let body = String(trimmed.dropFirst().dropLast())
        let cells = body.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cells.allSatisfy(\.isEmpty) ? nil : cells
    }

    private static func isSeparatorCell(_ value: String) -> Bool {
        let compact = value.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        let core = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return core.count >= 3 && core.allSatisfy { $0 == "-" }
    }

    static func repairSingleLinePipeRows(_ raw: String) -> String {
        guard raw.filter({ $0 == "|" }).count >= 6 else { return raw }
        guard let regex = try? NSRegularExpression(pattern: "\\|[ \\t]+\\|", options: []) else { return raw }
        let range = NSRange(location: 0, length: (raw as NSString).length)
        var repaired = regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "|\n|")
        if let firstPipe = repaired.firstIndex(of: "|") {
            let prefix = repaired[..<firstPipe]
            if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !prefix.hasSuffix("\n") {
                repaired.insert("\n", at: firstPipe)
            }
        }
        return repaired
    }
}

enum ColoredTextTag: String, Equatable, Sendable {
    case red, green, blue, yellow, purple, mark

    init?(name: String) {
        switch name.lowercased() {
        case "red", "rot": self = .red
        case "green", "gruen", "grün": self = .green
        case "blue", "blau": self = .blue
        case "yellow", "gelb": self = .yellow
        case "purple", "lila": self = .purple
        case "mark", "marker": self = .mark
        default: return nil
        }
    }
}

struct ColoredTextFragment: Equatable, Sendable {
    let text: String
    let foreground: ColoredTextTag?
    let marked: Bool
}

enum ColoredTextParser {
    private final class CacheBox: NSObject {
        let fragments: [ColoredTextFragment]

        init(_ fragments: [ColoredTextFragment]) {
            self.fragments = fragments
        }
    }

    private final class ParserCache: @unchecked Sendable {
        let storage: NSCache<NSString, CacheBox>

        init() {
            storage = NSCache<NSString, CacheBox>()
            storage.countLimit = 256
            storage.totalCostLimit = 1_500_000
        }
    }

    private static let cache = ParserCache()

    static func parse(_ raw: String) -> [ColoredTextFragment] {
        let key = raw as NSString
        if let cached = cache.storage.object(forKey: key) {
            return cached.fragments
        }

        let fragments = parseUncached(raw)
        cache.storage.setObject(CacheBox(fragments), forKey: key, cost: raw.utf16.count)
        return fragments
    }

    private static func parseUncached(_ raw: String) -> [ColoredTextFragment] {
        guard let regex = try? NSRegularExpression(
            pattern: "\\[(/?)([A-Za-zÄÖÜäöüß]+)\\]",
            options: [.caseInsensitive]
        ) else {
            return [ColoredTextFragment(text: raw, foreground: nil, marked: false)]
        }

        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return [ColoredTextFragment(text: raw, foreground: nil, marked: false)]
        }

        var fragments: [ColoredTextFragment] = []
        var stack: [ColoredTextTag] = []
        var cursor = 0

        func append(_ value: String) {
            guard !value.isEmpty else { return }
            var remaining = value
            while let boundary = remaining.range(of: "\n\n") {
                let before = String(remaining[..<boundary.lowerBound])
                appendStyled(before, stack: stack, to: &fragments)
                appendStyled("\n\n", stack: [], to: &fragments)
                stack.removeAll()
                remaining = String(remaining[boundary.upperBound...])
            }
            appendStyled(remaining, stack: stack, to: &fragments)
        }

        for match in matches {
            if match.range.location > cursor {
                append(ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                )))
            }

            let rawToken = ns.substring(with: match.range)
            let isClosing = ns.substring(with: match.range(at: 1)) == "/"
            let name = ns.substring(with: match.range(at: 2))
            guard let tag = ColoredTextTag(name: name) else {
                append(rawToken)
                cursor = match.range.location + match.range.length
                continue
            }

            if isClosing {
                if let position = stack.lastIndex(of: tag) {
                    stack.remove(at: position)
                }
                // Ein verwaister oder falscher bekannter End-Tag wird bewusst entfernt.
            } else {
                stack.append(tag)
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length { append(ns.substring(from: cursor)) }
        return coalesced(fragments)
    }

    private static func appendStyled(
        _ value: String,
        stack: [ColoredTextTag],
        to fragments: inout [ColoredTextFragment]
    ) {
        guard !value.isEmpty else { return }
        fragments.append(ColoredTextFragment(
            text: value,
            foreground: stack.last(where: { $0 != .mark }),
            marked: stack.contains(.mark)
        ))
    }

    private static func coalesced(_ input: [ColoredTextFragment]) -> [ColoredTextFragment] {
        var result: [ColoredTextFragment] = []
        for fragment in input {
            if let last = result.last,
               last.foreground == fragment.foreground,
               last.marked == fragment.marked {
                result[result.count - 1] = ColoredTextFragment(
                    text: last.text + fragment.text,
                    foreground: last.foreground,
                    marked: last.marked
                )
            } else {
                result.append(fragment)
            }
        }
        return result
    }
}

enum ChartPayloadParser {
    private struct SimpleChart: Decodable {
        let type: String?
        let title: String?
        let seriesName: String?
        let labels: [String]
        let values: [Double]
    }

    static func parse(_ raw: String) -> ChartPayload? {
        guard let data = raw.data(using: .utf8) else { return nil }

        if let simple = try? JSONDecoder().decode(SimpleChart.self, from: data) {
            return payload(
                kind: simple.type,
                title: simple.title,
                seriesName: simple.seriesName,
                labels: simple.labels,
                values: simple.values
            )
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chartData = object["data"] as? [String: Any],
              let labels = chartData["labels"] as? [String],
              let datasets = chartData["datasets"] as? [[String: Any]],
              let first = datasets.first else { return nil }

        let values = (first["data"] as? [NSNumber])?.map(\.doubleValue) ?? []
        let options = object["options"] as? [String: Any]
        let plugins = options?["plugins"] as? [String: Any]
        let titleObject = plugins?["title"] as? [String: Any]
        return payload(
            kind: object["type"] as? String,
            title: titleObject?["text"] as? String,
            seriesName: first["label"] as? String,
            labels: labels,
            values: values
        )
    }

    private static func payload(
        kind: String?,
        title: String?,
        seriesName: String?,
        labels: [String],
        values: [Double]
    ) -> ChartPayload? {
        guard !labels.isEmpty, labels.count == values.count, values.allSatisfy(\.isFinite) else { return nil }
        let points = zip(labels, values).enumerated().map {
            ChartPayload.Point(id: $0.offset, label: $0.element.0, value: $0.element.1)
        }
        return ChartPayload(
            kind: ChartPayload.Kind(modelValue: kind),
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            seriesName: seriesName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            points: points
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct SafeColoredText: View {
    let text: String
    let sources: [WebSource]

    var body: some View {
        Text(attributedText)
            .accessibilityLabel(text.replacingOccurrences(
                of: "\\[/?(red|rot|green|gruen|grün|blue|blau|yellow|gelb|purple|lila|mark|marker)\\]",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            ).replacingOccurrences(
                of: "\\[S[0-9]+\\]",
                with: " Quelle ",
                options: [.regularExpression, .caseInsensitive]
            ))
    }

    private var attributedText: AttributedString {
        var output = AttributedString()
        for fragment in ColoredTextParser.parse(text) {
            output.append(attributedFragment(fragment))
        }
        return output
    }

    private func attributedFragment(_ fragment: ColoredTextFragment) -> AttributedString {
        guard let regex = try? NSRegularExpression(pattern: "\\[S([0-9]+)\\]", options: [.caseInsensitive]) else {
            return styled(fragment.text, like: fragment)
        }
        let ns = fragment.text as NSString
        let matches = regex.matches(
            in: fragment.text,
            range: NSRange(location: 0, length: ns.length)
        )
        guard !matches.isEmpty else { return styled(fragment.text, like: fragment) }

        var output = AttributedString()
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output.append(styled(ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                )), like: fragment))
            }
            let number = Int(ns.substring(with: match.range(at: 1))) ?? 0
            if sources.indices.contains(number - 1),
               let url = URL(string: sources[number - 1].url) {
                var marker = AttributedString(" [\(number)]")
                marker.font = .system(size: 10.5, weight: .bold, design: .rounded)
                marker.foregroundColor = .blue
                marker.link = url
                output.append(marker)
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            output.append(styled(ns.substring(from: cursor), like: fragment))
        }
        return output
    }

    private func styled(_ value: String, like fragment: ColoredTextFragment) -> AttributedString {
        var segment = AttributedString(value)
        switch fragment.foreground {
        case .red: segment.foregroundColor = Color(red: 0.88, green: 0.16, blue: 0.22)
        case .green: segment.foregroundColor = Color(red: 0.08, green: 0.56, blue: 0.28)
        case .blue: segment.foregroundColor = Color(red: 0.08, green: 0.38, blue: 0.88)
        case .yellow: segment.foregroundColor = Color(red: 0.70, green: 0.45, blue: 0.02)
        case .purple: segment.foregroundColor = Color(red: 0.56, green: 0.20, blue: 0.78)
        case .mark, nil: break
        }
        if fragment.marked { segment.backgroundColor = Color.yellow.opacity(0.30) }
        return segment
    }
}

private struct NativeTableView: View {
    let table: TablePayload

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        cell(header, isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { column in
                            cell(column < row.count ? row[column] : "", isHeader: false)
                                .background(rowIndex.isMultiple(of: 2) ? Color.primary.opacity(0.018) : .clear)
                        }
                    }
                }
            }
            .frame(minWidth: min(CGFloat(table.columnCount) * 150, 620), alignment: .leading)
        }
        .padding(1)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .transparentGlassReadabilityPanel(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabelle mit \(table.rows.count) Zeilen und \(table.columnCount) Spalten")
    }

    private func cell(_ value: String, isHeader: Bool) -> some View {
        Text(value)
            .font(.system(size: isHeader ? 12.2 : 12.5, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(isHeader ? .primary : .secondary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .frame(minWidth: 120, maxWidth: 230, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, isHeader ? 9 : 8)
            .accessibilityLabel(value)
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

private struct NativeChartView: View {
    let chart: ChartPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = chart.title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            Chart(chart.points) { point in
                switch chart.kind {
                case .bar:
                    BarMark(
                        x: .value("Kategorie", point.label),
                        y: .value(chart.seriesName ?? "Wert", point.value)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(.blue.gradient)
                case .line:
                    LineMark(
                        x: .value("Kategorie", point.label),
                        y: .value(chart.seriesName ?? "Wert", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    PointMark(
                        x: .value("Kategorie", point.label),
                        y: .value(chart.seriesName ?? "Wert", point.value)
                    )
                    .foregroundStyle(.blue)
                case .area:
                    AreaMark(
                        x: .value("Kategorie", point.label),
                        y: .value(chart.seriesName ?? "Wert", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue.opacity(0.24).gradient)
                    LineMark(
                        x: .value("Kategorie", point.label),
                        y: .value(chart.seriesName ?? "Wert", point.value)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic) }
            .chartYAxis { AxisMarks(position: .leading) }
            .accessibilityLabel(chart.title ?? "Diagramm")
        }
        .padding(12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.8)
        }
        .transparentGlassReadabilityPanel(cornerRadius: 16)
    }
}

private struct CodeBlockView: View {
    let language: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(source)
                    .font(.system(size: 12.2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MermaidDiagramView: NSViewRepresentable {
    let source: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastSource != source else { return }
        context.coordinator.lastSource = source
        webView.loadHTMLString(Self.html(for: source), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastSource: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private static func html(for source: String) -> String {
        let encoded = Data(source.utf8).base64EncodedString()
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        html,body{margin:0;padding:0;background:transparent;color:#222;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
        .card{box-sizing:border-box;width:100%;min-height:190px;padding:14px;border-radius:16px;background:rgba(255,255,255,.26);overflow:auto}
        .error{font-size:12px;color:#8a2d2d;white-space:pre-wrap;padding-top:8px}
        </style>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
        </head><body><div class="card"><div id="diagram" class="mermaid"></div><div id="error" class="error"></div></div>
        <script>
        const src = decodeURIComponent(escape(atob('\(encoded)')));
        const node = document.getElementById('diagram');
        node.textContent = src;
        const fail = err => { document.getElementById('error').textContent='Diagramm konnte nicht geladen werden. Prüfe die Syntax oder die Internetverbindung. '+err; };
        try {
          if (typeof mermaid === 'undefined') { fail('Mermaid ist offline nicht verfügbar.'); }
          else {
            mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'neutral'});
            mermaid.run({nodes:[node]}).catch(fail);
          }
        } catch(err) { fail(err); }
        </script></body></html>
        """
    }
}
