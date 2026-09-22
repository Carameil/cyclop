import SwiftUI

/// Paste on the left, result on the right — the same two columns as the
/// translator, and for the same reason: what came in and what it became
/// should be visible at once, so a wrong guess about the format is caught by
/// eye before it is copied anywhere.
struct ToolsPane: View {
    @ObservedObject var tools: ToolsStore
    /// Whether the panel holds the keyboard; the editor follows it.
    @Binding var wantsKeyboard: Bool
    /// Esc on an empty field: the panel was summoned by a key, so a key
    /// should be enough to send it away again.
    let dismiss: () -> Void

    @FocusState private var focused: Bool

    private let font: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            source
            result
        }
        .padding(.top, 2)
        .onAppear { focused = wantsKeyboard }
        .onChange(of: wantsKeyboard) { _, wants in focused = wants }
    }

    // MARK: - Left

    private var source: some View {
        column(localized("Paste")) {
            if !tools.input.isEmpty {
                Button { tools.reset() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
            }
        } content: {
            TextEditor(text: $tools.input)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .font(.system(size: font, design: .monospaced))
                .foregroundStyle(.white)
                .tint(Theme.secondary)
                .focused($focused)
                .padding(.leading, -5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onKeyPress(.escape) {
                    if tools.input.isEmpty {
                        dismiss()
                    } else {
                        tools.reset()
                    }
                    return .handled
                }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Right

    private var result: some View {
        column(kindTitle) {
            if !tools.output.isEmpty {
                CopyButton { tools.copyOutput() }
            }
        } content: {
            outcome
        }
        .padding(10)
    }

    @ViewBuilder
    private var outcome: some View {
        if let failure = tools.result.failure {
            Text(failure)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if !tools.output.isEmpty {
            ScrollView(showsIndicators: false) {
                Text(tools.output)
                    .font(.system(size: font, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("JSON · ids · timestamp")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var kindTitle: String {
        switch tools.kind {
        case .empty: return localized("Result")
        case .json: return "JSON"
        case .ids: return localized("Comma-Separated")
        case .timestamp: return localized("Date")
        case .date: return localized("Unix Timestamp")
        case .invalid: return localized("Invalid JSON")
        }
    }

    // MARK: - Shared

    private func column<Accessory: View, Content: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiary)
                Spacer(minLength: 4)
                accessory()
            }
            .frame(height: 14)

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The header badge: what the paste was recognised as. Observes the store on
/// its own so a keystroke redraws the badge and not the panel — see the note
/// on `NotesCounter` in `NotchContentView`.
struct ToolsKindBadge: View {
    @ObservedObject var tools: ToolsStore

    var body: some View {
        if tools.kind != .empty {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tools.kind == .invalid ? Color.yellow.opacity(0.85) : Theme.tertiary)
        }
    }

    private var label: String {
        switch tools.kind {
        case .empty: return ""
        case .json: return "JSON"
        case .ids: return localized("%d ids", Normalizer.split(tools.input).count)
        case .timestamp: return localized("Date")
        case .date: return localized("Unix Timestamp")
        case .invalid: return localized("Invalid JSON")
        }
    }
}
