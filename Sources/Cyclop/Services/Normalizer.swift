import Foundation

/// Turns whatever was pasted into the Tools tab into the shape one usually
/// wants next: minified JSON into readable JSON, a column of ids into a
/// comma-separated row, a unix timestamp into a date and back.
///
/// Pure functions, no state — the store keeps the text, this only transforms
/// it. Which transformation applies is decided from the text itself rather
/// than from a mode switch: the tab is opened to paste and copy, and a picker
/// in between would be a third step for something that is always obvious from
/// what was pasted.
enum Normalizer {
    enum Kind: Equatable {
        case empty
        case json
        case ids
        case timestamp
        case date
        case invalid
    }

    struct Result: Equatable {
        let kind: Kind
        let output: String
        /// What went wrong when `kind` is `.invalid` — shown in place of the
        /// output so a broken paste is named, not silently left blank.
        let failure: String?

        static let empty = Result(kind: .empty, output: "", failure: nil)
    }

    static func normalize(_ input: String) -> Result {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }

        if text.hasPrefix("{") || text.hasPrefix("[") {
            do {
                return Result(kind: .json, output: try prettyJSON(text), failure: nil)
            } catch {
                return Result(kind: .invalid, output: "", failure: error.localizedDescription)
            }
        }

        // Whole text first: a date written with a space in it would otherwise
        // be split into two "ids". A list never parses as one moment, so the
        // order costs nothing.
        if let date = date(fromTimestamp: text) {
            return Result(kind: .timestamp, output: date, failure: nil)
        }
        if let stamp = timestamp(fromDate: text) {
            return Result(kind: .date, output: stamp, failure: nil)
        }

        return Result(kind: .ids, output: split(text).joined(separator: ", "), failure: nil)
    }

    // MARK: - Lists

    /// Anything that separates one id from the next: line breaks, spaces,
    /// tabs, commas and semicolons — a column pasted from a spreadsheet, a
    /// row copied from a log, or a list that was already comma-separated and
    /// is being re-joined after an edit.
    static func split(_ text: String) -> [String] {
        var separators = CharacterSet.whitespacesAndNewlines
        separators.insert(charactersIn: ",;")
        return text.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    // MARK: - JSON

    struct JSONError: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    /// Re-indents JSON without reordering it.
    ///
    /// `JSONSerialization` would do this in one call, but it parses into a
    /// dictionary and writes the keys back in whatever order the dictionary
    /// keeps them — and a config or an API response with its keys shuffled is
    /// harder to read than the minified original. So the text is validated
    /// with the parser and then laid out by walking the characters: nothing is
    /// reordered, strings are copied verbatim, only the whitespace between
    /// tokens changes.
    static func prettyJSON(_ text: String, indent: String = "  ") throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw JSONError(message: "Not valid UTF-8")
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch let error as NSError {
            let detail = (error.userInfo[NSDebugDescriptionErrorKey] as? String) ?? error.localizedDescription
            throw JSONError(message: detail)
        }

        var out = ""
        out.reserveCapacity(text.count * 2)
        var depth = 0
        var inString = false
        var escaped = false
        let chars = Array(text)
        var index = 0

        func newline() {
            out.append("\n")
            for _ in 0..<depth { out.append(indent) }
        }

        /// Index of the next character that is not whitespace, from `from`.
        func nextMeaningful(after from: Int) -> Int? {
            var i = from + 1
            while i < chars.count {
                if !chars[i].isWhitespace { return i }
                i += 1
            }
            return nil
        }

        while index < chars.count {
            let char = chars[index]
            if inString {
                out.append(char)
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                index += 1
                continue
            }

            switch char {
            case "\"":
                inString = true
                out.append(char)
            case "{", "[":
                out.append(char)
                // `{}` and `[]` stay on one line: an empty container spread
                // over two lines reads as something that lost its contents.
                if let next = nextMeaningful(after: index),
                   (char == "{" && chars[next] == "}") || (char == "[" && chars[next] == "]") {
                    out.append(chars[next])
                    index = next
                } else {
                    depth += 1
                    newline()
                }
            case "}", "]":
                depth = max(0, depth - 1)
                newline()
                out.append(char)
            case ",":
                out.append(char)
                newline()
            case ":":
                out.append(": ")
            default:
                if !char.isWhitespace { out.append(char) }
            }
            index += 1
        }
        return out
    }

    // MARK: - Time

    /// Seconds since 1970 have ten digits for every date this century;
    /// milliseconds have thirteen. Anything else that is all digits is an id,
    /// not a moment, and belongs to the list path.
    static func date(fromTimestamp token: String) -> String? {
        guard token.allSatisfy(\.isNumber), let value = Double(token) else { return nil }
        let seconds: Double
        switch token.count {
        case 10: seconds = value
        case 13: seconds = value / 1000
        default: return nil
        }
        let date = Date(timeIntervalSince1970: seconds)
        let utc = formatter(timeZone: TimeZone(identifier: "UTC")!).string(from: date)
        let local = formatter(timeZone: .current).string(from: date)
        let zone = TimeZone.current.abbreviation() ?? TimeZone.current.identifier
        return "\(utc) UTC\n\(local) \(zone)"
    }

    /// The other direction: a date typed by hand or copied from a log,
    /// answered with the unix seconds it names. A bare date is midnight UTC;
    /// a date with a time and no zone is read as UTC too, because that is
    /// what a timestamp column in a database almost always holds.
    static func timestamp(fromDate token: String) -> String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: token) { return String(Int(date.timeIntervalSince1970)) }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: token) { return String(Int(date.timeIntervalSince1970)) }

        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let parser = formatter(timeZone: TimeZone(identifier: "UTC")!, pattern: pattern)
            if let date = parser.date(from: token) {
                return String(Int(date.timeIntervalSince1970))
            }
        }
        return nil
    }

    private static func formatter(timeZone: TimeZone, pattern: String = "yyyy-MM-dd HH:mm:ss") -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter
    }
}
