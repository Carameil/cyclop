import Foundation

/// Rich text copied from a page, turned back into markdown.
///
/// A chat answer copied by selecting it carries two versions: HTML and plain
/// text. The plain one has already lost the layout — a table comes out as
/// cells separated by tabs, headings and bold as ordinary words — so the
/// teleprompter takes the HTML and writes the markdown it was rendered from.
enum HTMLMarkdown {
    /// Nil when the HTML has nothing plain text would lose: a code editor puts
    /// its text on the pasteboard as coloured spans too, and those must paste
    /// exactly as typed, indentation and all.
    static func convert(_ html: String) -> String? {
        let lowered = html.lowercased()
        guard structural.contains(where: { lowered.contains("<\($0)") }),
              let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let root = document.rootElement() else { return nil }
        let body = root.children?.first { ($0 as? XMLElement)?.localName?.lowercased() == "body" } ?? root
        let markdown = blocks(body, depth: 0)
            .joined(separator: "\n\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return markdown.isEmpty ? nil : markdown
    }

    private static let structural = [
        "table", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6",
        "strong", "b>", "b ", "em>", "em ", "pre", "blockquote",
    ]

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "figure",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "table", "pre", "blockquote", "hr",
    ]

    // MARK: - Blocks

    private static func blocks(_ node: XMLNode, depth: Int) -> [String] {
        var out: [String] = []
        var run = ""
        func flush() {
            let text = run.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append(text) }
            run = ""
        }

        for child in node.children ?? [] {
            guard let element = child as? XMLElement,
                  let tag = element.localName?.lowercased(),
                  blockTags.contains(tag) else {
                run += inline(child)
                continue
            }
            flush()
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(String(tag.last!))!
                let text = inline(element).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append(String(repeating: "#", count: level) + " " + text) }
            case "ul", "ol":
                out.append(list(element, ordered: tag == "ol", depth: depth))
            case "table":
                if let table = table(element) { out.append(table) }
            case "pre":
                let code = (element.stringValue ?? "").trimmingCharacters(in: .newlines)
                out.append("```\n\(code)\n```")
            case "blockquote":
                let quoted = blocks(element, depth: depth).joined(separator: "\n\n")
                out.append(quoted.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n"))
            case "hr":
                out.append("---")
            default:
                out += blocks(element, depth: depth)
            }
        }
        flush()
        return out
    }

    private static func list(_ element: XMLElement, ordered: Bool, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        var number = 1
        for case let item as XMLElement in element.children ?? [] where item.localName?.lowercased() == "li" {
            let parts = blocks(item, depth: depth + 1)
            let marker = ordered ? "\(number). " : "- "
            lines.append(indent + marker + (parts.first ?? ""))
            // A nested list comes back already indented; anything else in the
            // item continues it on a line of its own.
            for part in parts.dropFirst() {
                lines.append(part.hasPrefix(indent + "  ") ? part : indent + "  " + part)
            }
            number += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func table(_ element: XMLElement) -> String? {
        let rows = self.rows(in: element).map { row in
            (row.children ?? [])
                .compactMap { $0 as? XMLElement }
                .filter { ["th", "td"].contains($0.localName?.lowercased()) }
                .map { cell in
                    inline(cell)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "|", with: "\\|")
                        .replacingOccurrences(of: "\n", with: "<br>")
                }
        }
        guard let width = rows.map(\.count).max(), width > 0 else { return nil }
        let padded = rows.map { $0 + Array(repeating: "", count: width - $0.count) }
        let line: ([String]) -> String = { "| " + $0.joined(separator: " | ") + " |" }
        let separator = "|" + Array(repeating: "---", count: width).joined(separator: "|") + "|"
        return ([line(padded[0]), separator] + padded.dropFirst().map(line)).joined(separator: "\n")
    }

    /// Rows of this table, through `thead` and `tbody` but not into a table
    /// nested in a cell.
    private static func rows(in node: XMLNode) -> [XMLElement] {
        (node.children ?? []).flatMap { child -> [XMLElement] in
            guard let element = child as? XMLElement else { return [] }
            switch element.localName?.lowercased() {
            case "tr": return [element]
            case "thead", "tbody", "tfoot": return rows(in: element)
            default: return []
            }
        }
    }

    // MARK: - Inline

    private static func inline(_ node: XMLNode) -> String {
        guard let element = node as? XMLElement else {
            guard node.kind == .text else { return "" }
            return (node.stringValue ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        let children = { (element.children ?? []).map(inline).joined() }
        switch element.localName?.lowercased() {
        case "br": return "\n"
        case "strong", "b": return wrap(children(), in: "**")
        case "em", "i": return wrap(children(), in: "*")
        case "code": return wrap(element.stringValue ?? "", in: "`")
        case "img", "script", "style", "button", "svg": return ""
        default: return children()
        }
    }

    /// Markers hug the words: `** bold **` is not bold in markdown, so the
    /// spaces a page leaves inside a tag go outside the markers.
    private static func wrap(_ text: String, in marker: String) -> String {
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }
        let leading = text.hasPrefix(" ") ? " " : ""
        let trailing = text.hasSuffix(" ") ? " " : ""
        return leading + marker + core + marker + trailing
    }
}
