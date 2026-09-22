import AppKit

/// The Tools tab's text: what was pasted and what it became.
///
/// Held here rather than in the pane so that leaving the tab and coming back
/// finds the text where it was left — the pane is rebuilt on every switch.
/// The result is recomputed on every keystroke: the transformations are
/// linear in the length of the text and the text is a paste, not a document.
@MainActor
final class ToolsStore: ObservableObject {
    @Published var input = "" {
        didSet { result = Normalizer.normalize(input) }
    }
    @Published private(set) var result = Normalizer.Result.empty

    var output: String { result.output }
    var kind: Normalizer.Kind { result.kind }

    func reset() {
        input = ""
    }

    /// Plain text only, and marked as Cyclop's own write so the clipboard
    /// history does not record the panel copying to itself.
    func copyOutput() {
        guard !output.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        pasteboard.setData(Data(), forType: .cyclopInternal)
    }
}
