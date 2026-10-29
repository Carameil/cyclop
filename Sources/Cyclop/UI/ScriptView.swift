import SwiftUI

/// The teleprompter script, block by block. One view for both the page and the
/// scrolling reader: they differ in size and weight, not in what a table or a
/// screenshot looks like.
struct ScriptView: View {
    let blocks: [TeleprompterBlock]
    let fontSize: CGFloat
    var weight: Font.Weight = .regular
    let lineSpacing: CGFloat
    /// Resolves `![](source)`; the store keeps the decoded images.
    let image: (String) -> NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func font(scale: CGFloat = 1, weight: Font.Weight? = nil) -> Font {
        .system(size: fontSize * scale, weight: weight ?? self.weight, design: .rounded)
    }

    @ViewBuilder
    private func view(for block: TeleprompterBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(font())
                .lineSpacing(lineSpacing)
        case .heading(let level, let text):
            Text(text)
                .font(font(scale: [1.45, 1.25, 1.1][min(level, 3) - 1], weight: .bold))
                .lineSpacing(lineSpacing)
        case .quote(let text):
            Text(text)
                .font(font())
                .lineSpacing(lineSpacing)
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.tertiary).frame(width: 3)
                }
        case .code(let code):
            Text(code)
                .font(.system(size: fontSize * 0.85, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .table(let header, let rows):
            table(header: header, rows: rows)
        case .image(let source):
            picture(source)
        case .rule:
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    /// Cells wrap rather than cut: a long cell is the reason to look at the
    /// table at all.
    private func table(header: [AttributedString], rows: [[AttributedString]]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: fontSize, verticalSpacing: fontSize * 0.5) {
            GridRow {
                ForEach(header.indices, id: \.self) { column in
                    Text(header[column])
                        .font(font(weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rectangle().fill(Theme.tertiary).frame(height: 1)
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        Text(rows[row][column])
                            .font(font())
                            .lineSpacing(lineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if row < rows.count - 1 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
        }
    }

    /// Never wider than the picture itself: a small crop blown up to the
    /// column's width reads as a mistake.
    @ViewBuilder
    private func picture(_ source: String) -> some View {
        if let image = image(source) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: image.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Label(source, systemImage: "photo")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
