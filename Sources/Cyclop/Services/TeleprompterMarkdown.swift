import Foundation

/// One piece of the script, laid out its own way.
///
/// Scripts arrive pasted from a chat answer, and those are markdown: headings,
/// a table, a screenshot. Inline markdown alone showed the table as rows of
/// pipes and dashes. So the lines that open a block are picked out here, and
/// everything else stays the plain text it was — line breaks and numbering
/// kept as written, since they are the layout of a script.
enum TeleprompterBlock: Equatable {
    /// Plain lines, inline markdown applied, whitespace kept.
    case text(AttributedString)
    case heading(level: Int, text: AttributedString)
    case quote(AttributedString)
    case code(String)
    /// Every row as long as the header: a short row is padded, a long one cut.
    case table(header: [AttributedString], rows: [[AttributedString]])
    /// Where the image lives, as written in `![](…)`.
    case image(source: String)
    case rule

    static func parse(_ script: String) -> [TeleprompterBlock] {
        let lines = script.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [TeleprompterBlock] = []
        var plain: [String] = []

        func flush() {
            while let first = plain.first, first.trimmingCharacters(in: .whitespaces).isEmpty { plain.removeFirst() }
            while let last = plain.last, last.trimmingCharacters(in: .whitespaces).isEmpty { plain.removeLast() }
            if !plain.isEmpty { blocks.append(.text(TeleprompterStore.format(plain.joined(separator: "\n")))) }
            plain.removeAll()
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }

            if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
                i += 1
                continue
            }

            if isRule(trimmed) {
                flush()
                blocks.append(.rule)
                i += 1
                continue
            }

            if let source = imageSource(trimmed) {
                flush()
                blocks.append(.image(source: source))
                i += 1
                continue
            }

            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flush()
                let header = cells(trimmed)
                var rows: [[AttributedString]] = []
                i += 2
                while i < lines.count, lines[i].contains("|") {
                    var row = cells(lines[i].trimmingCharacters(in: .whitespaces))
                    row = Array(row.prefix(header.count))
                    row += Array(repeating: "", count: header.count - row.count)
                    rows.append(row.map(TeleprompterStore.format))
                    i += 1
                }
                blocks.append(.table(header: header.map(TeleprompterStore.format), rows: rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix(">") else { break }
                    var body = next.dropFirst()
                    if body.hasPrefix(" ") { body = body.dropFirst() }
                    quoted.append(String(body))
                    i += 1
                }
                blocks.append(.quote(TeleprompterStore.format(quoted.joined(separator: "\n"))))
                continue
            }

            plain.append(bulleted(line))
            i += 1
        }
        flush()
        return blocks
    }

    // MARK: - Lines

    private static func heading(_ line: String) -> TeleprompterBlock? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level: level, text: TeleprompterStore.format(rest.trimmingCharacters(in: .whitespaces)))
    }

    /// `---`, `***` or `___`, spaces between allowed.
    private static func isRule(_ line: String) -> Bool {
        let marks = line.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// Only an image alone on its line: one in the middle of a sentence has no
    /// width to be drawn at but the sentence's.
    private static func imageSource(_ line: String) -> String? {
        guard line.hasPrefix("!["), line.hasSuffix(")"), let split = line.range(of: "](") else { return nil }
        var source = line[split.upperBound..<line.index(before: line.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        // `![](path "title")` — the title is not part of the path.
        if let title = source.range(of: " \"") { source = String(source[..<title.lowerBound]) }
        if source.hasPrefix("<"), source.hasSuffix(">") { source = String(source.dropFirst().dropLast()) }
        return source.isEmpty ? nil : source
    }

    /// `|---|:--:|`: what separates a table's header from its rows.
    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        return cells(trimmed).allSatisfy { cell in
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !dashes.isEmpty && dashes.allSatisfy { $0 == "-" }
        }
    }

    /// Split on pipes, the ones on the outside dropped and `\|` kept as text.
    /// Chat answers break lines inside a cell with `<br>`.
    private static func cells(_ line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body = body.dropLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for char in body {
            if escaped {
                current.append(char == "|" ? "|" : "\\\(char)")
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current)
        return cells.map {
            $0.replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<br/>", with: "\n")
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// `- item` reads as a bullet, not as a dash someone typed.
    private static func bulleted(_ line: String) -> String {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)
        guard let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first == " " else { return line }
        return String(indent) + "•" + rest.dropFirst()
    }
}
