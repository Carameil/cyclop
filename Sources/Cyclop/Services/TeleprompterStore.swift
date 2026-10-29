import AppKit
import SwiftUI

/// The script, and where reading it has got to.
///
/// The notch is the one place on the screen where a teleprompter belongs: it
/// sits directly under the camera, so the eyes stay on the lens instead of
/// travelling to a window somewhere below it. Every other tab is here because
/// there is room; this one is here because of where the room is.
@MainActor
final class TeleprompterStore: ObservableObject {
    /// The text being read. Kept between launches — a script is written once
    /// and read several times, often over several takes.
    @Published var script: String = "" {
        didSet {
            guard script != oldValue else { return }
            blocks = TeleprompterBlock.parse(script)
            // Rewriting the script mid-take would leave the scroll pointing at
            // a line that no longer exists.
            offset = 0
            scheduleSave()
        }
    }

    /// The script as shown: markdown applied, so `**task**` reads bold, a
    /// table pasted from a chat answer stays a table and a screenshot is shown
    /// rather than its path. Parsed here, once per change, rather than in the
    /// view, which redraws sixty times a second while the text is moving.
    private(set) var blocks: [TeleprompterBlock] = []

    /// Where the caret is in the editor, so a pasted screenshot lands there.
    /// Not published: the editor keeps it current itself, and redrawing the
    /// pane on every caret move would buy nothing.
    var selection: TextSelection?

    /// Points per second the text creeps upward at 1×. Slow: a comfortable
    /// reading pace is far slower than anyone guesses before trying it, and
    /// the speed control multiplies this.
    static let baseRate: CGFloat = 22

    /// Multiplier on `baseRate`. Adjustable mid-take, because the pace that
    /// felt right while setting up never survives the first paragraph.
    @Published var speed: Double = 1.0 {
        didSet {
            guard speed != oldValue else { return }
            ConfigStore.shared.teleprompterSpeed = speed
        }
    }

    /// Point size of the script. What makes a teleprompter legible is type
    /// large enough to read at a glance, without focusing — the glance is all
    /// the attention available while talking to a camera.
    @Published var fontSize: Double = 30 {
        didSet {
            guard fontSize != oldValue else { return }
            ConfigStore.shared.teleprompterFontSize = fontSize
        }
    }

    /// How far the text has scrolled, in points. Not persisted: a new session
    /// starts at the top, which is where a take starts.
    @Published var offset: CGFloat = 0
    @Published private(set) var isRunning = false

    /// Height of the text as laid out, set by the pane once it knows. Scrolling
    /// stops here rather than running the script off into empty space.
    var contentHeight: CGFloat = 0
    /// Height of the window the text scrolls through, also from the pane.
    var viewportHeight: CGFloat = 0

    static let defaultFile = Support.file("teleprompter.txt")

    /// Given rather than looked up, as in `SnippetStore`: a test against the
    /// real path would be rewriting the script of whoever ran it.
    let file: URL

    /// Screenshots pasted into the script, next to it, so `![](…)` paths in
    /// the file stay short and relative.
    var imageFolder: URL { file.deletingLastPathComponent().appendingPathComponent("teleprompter-images", isDirectory: true) }
    private var images: [String: NSImage] = [:]

    private var timer: Timer?
    private let saves = DebouncedWrite()

    init(file: URL = defaultFile) {
        self.file = file
        script = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        // Reading the file above went through `script`'s observer and armed a
        // save of what was just loaded. Harmless, but worth not doing.
        saves.cancel()
        // Persisted in `config.json` (#67) since before this store existed —
        // the clamps guard a value hand-edited in the file past what the
        // slider itself allows.
        speed = min(max(ConfigStore.shared.teleprompterSpeed, 0.3), 3.0)
        fontSize = min(max(ConfigStore.shared.teleprompterFontSize, 18), 64)
    }

    // MARK: - Running

    /// The furthest the text may scroll: the last line stops in the middle of
    /// the window rather than at the top edge, so it is still being read from
    /// the same place as every line before it.
    var maxOffset: CGFloat {
        max(0, contentHeight - viewportHeight / 2)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !script.isEmpty, !isRunning else { return }
        if offset >= maxOffset { offset = 0 }
        isRunning = true
        // 60 Hz rather than a per-line jump: text that steps line by line is
        // read in lurches, and the eye loses the line it was on at every step.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func rewind() {
        pause()
        offset = 0
    }

    /// Stops the clock and leaves the position alone. For the panel closing or
    /// the tab changing, where the only thing that has to happen immediately is
    /// that the text stops moving — where it stopped is decided on the way back
    /// in, by the pane, which puts it at the top.
    func suspend() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func tick() {
        // Nothing measured yet: the scrolling view is put on screen by the
        // same press that started the clock, and until it is laid out the end
        // of the script would look like it is at the very top.
        guard isRunning, contentHeight > 0 else { return }
        offset = min(maxOffset, offset + Self.baseRate * CGFloat(speed) / 60.0)
        if offset >= maxOffset { pause() }
    }

    /// Inline markdown only, whitespace kept: line breaks and numbering are
    /// the layout of a script, and block parsing would fold them away. Text
    /// that is not valid markdown is shown as written. The blocks are picked
    /// out beforehand, by `TeleprompterBlock.parse`.
    nonisolated static func format(_ script: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: script, options: options)) ?? AttributedString(script)
    }

    // MARK: - Pasting

    /// ⌘V in the editor, for what the editor would get wrong by itself.
    ///
    /// Rich text from a page — a chat answer copied by selecting it — goes in
    /// as the markdown it was rendered from, since its plain version has
    /// already flattened the tables and headings. A screenshot is saved next
    /// to the script and goes in as `![](…)`. Anything else is left to the
    /// editor; false says so.
    func paste(from pasteboard: NSPasteboard = .general) -> Bool {
        if let html = pasteboard.string(forType: .html), let markdown = HTMLMarkdown.convert(html) {
            replaceSelection(with: markdown)
            return true
        }
        // Text first: copying from a browser often brings a picture along.
        guard pasteboard.string(forType: .string) == nil,
              let png = ClipboardStore.png(from: pasteboard),
              let line = attachImage(png) else { return false }
        insert(line)
        return true
    }

    /// Puts `text` over the selection, as typing would, caret after it.
    func replaceSelection(with text: String) {
        var range = script.endIndex..<script.endIndex
        if case .selection(let selected) = selection?.indices, selected.upperBound <= script.endIndex {
            range = selected
        }
        let offset = script.distance(from: script.startIndex, to: range.lowerBound) + text.count
        script.replaceSubrange(range, with: text)
        selection = TextSelection(insertionPoint: caret(at: offset))
    }

    /// Writes the image into `imageFolder` and returns the line that shows it.
    func attachImage(_ png: Data, at date: Date = Date()) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "\(formatter.string(from: date))-\(UUID().uuidString.prefix(8)).png"
        do {
            try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
            try png.write(to: imageFolder.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("Cyclop: cannot save teleprompter image: \(error.localizedDescription)")
            return nil
        }
        return "![](\(imageFolder.lastPathComponent)/\(name))"
    }

    /// On a line of its own at the caret, or at the end without one. The
    /// caret is left just after it, so the next paste goes below.
    func insert(_ line: String) {
        var at = script.endIndex
        if case .selection(let range) = selection?.indices, range.upperBound <= script.endIndex {
            at = range.upperBound
        }
        let before = at > script.startIndex && script[script.index(before: at)] != "\n" ? "\n" : ""
        let after = at < script.endIndex && script[at] != "\n" ? "\n" : ""
        let offset = script.distance(from: script.startIndex, to: at) + before.count + line.count
        script.insert(contentsOf: before + line + after, at: at)
        selection = TextSelection(insertionPoint: caret(at: offset))
    }

    private func caret(at offset: Int) -> String.Index {
        script.index(script.startIndex, offsetBy: offset, limitedBy: script.endIndex) ?? script.endIndex
    }

    /// The image behind `![](source)`: a path relative to the script's folder,
    /// an absolute one, or a `file://` URL. Nothing from the network — the
    /// script is read offline, like everything else in the panel but rates.
    func image(_ source: String) -> NSImage? {
        if let cached = images[source] { return cached }
        let url: URL
        if let parsed = URL(string: source), parsed.isFileURL {
            url = parsed
        } else if source.hasPrefix("/") || source.hasPrefix("~") {
            url = URL(fileURLWithPath: (source as NSString).expandingTildeInPath)
        } else if URL(string: source)?.scheme == nil {
            url = file.deletingLastPathComponent().appendingPathComponent(source)
        } else {
            return nil
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images[source] = image
        return image
    }

    // MARK: - Storage

    /// Plain text, not JSON. The script is written elsewhere and pasted here,
    /// and a file anyone can open in any editor is worth more than a format
    /// only this app reads.
    private func scheduleSave() {
        saves.schedule { [weak self] in self?.persist() }
    }

    func flush() { saves.flush() }

    /// Re-read on every visit to the tab. The script is also written from
    /// outside the app — a daily report dropped into the file by a script —
    /// and without this it would show up only after a relaunch, and the copy
    /// in memory would write over it at the next keystroke.
    ///
    /// An edit still waiting to be saved wins: it is newer than whatever is on
    /// disk, and reloading would throw away what was just typed.
    func reload() {
        guard !saves.isPending,
              let text = try? String(contentsOf: file, encoding: .utf8),
              text != script else { return }
        script = text
        // Same as in `init`: loading went through `script`'s observer and
        // armed a save of what was just read.
        saves.cancel()
    }

    private func persist() {
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Cyclop: cannot write teleprompter.txt: \(error.localizedDescription)")
        }
    }

    static func reveal() {
        if !FileManager.default.fileExists(atPath: defaultFile.path) {
            try? "".write(to: defaultFile, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([defaultFile])
    }
}
