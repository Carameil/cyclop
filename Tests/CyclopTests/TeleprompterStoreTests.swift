import AppKit
import SwiftUI
import Testing
@testable import Cyclop

/// Тесты на `TeleprompterStore.reload` — скрипт, записанный в файл снаружи
/// приложения, доходит до вкладки без перезапуска.
///
/// Каждый тест работает со своим файлом во временной папке: настоящий
/// `teleprompter.txt` не читается и не пишется.
@MainActor
struct TeleprompterStoreTests {

    private static func makeStore(contents: String) throws -> (store: TeleprompterStore, file: URL) {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cyclop-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("teleprompter.txt")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return (TeleprompterStore(file: file), file)
    }

    @Test func reloadPicksUpTextWrittenFromOutside() throws {
        let (store, file) = try Self.makeStore(contents: "вчера")
        try "сегодня".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.script == "сегодня")
    }

    /// Перечитанный текст не должен тут же записываться обратно: иначе
    /// следующая запись снаружи, пришедшая за эти 0.8 с, была бы затёрта.
    @Test func reloadDoesNotArmASave() throws {
        let (store, file) = try Self.makeStore(contents: "вчера")
        try "сегодня".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        store.flush()
        try "отчёт".write(to: file, atomically: true, encoding: .utf8)
        store.flush()
        #expect(try String(contentsOf: file, encoding: .utf8) == "отчёт")
    }

    /// Правка, которая ещё не легла на диск, новее файла — она и остаётся.
    @Test func pendingEditWinsOverTheFile() throws {
        let (store, file) = try Self.makeStore(contents: "вчера")
        store.script = "печатаю"
        try "отчёт".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.script == "печатаю")
    }

    /// Нет файла — скрипт в памяти не стирается.
    @Test func missingFileKeepsTheScript() throws {
        let (store, file) = try Self.makeStore(contents: "вчера")
        try FileManager.default.removeItem(at: file)
        store.reload()
        #expect(store.script == "вчера")
    }

    /// `**…**` становится жирным, а нумерация и переносы строк остаются как
    /// написаны: блочный markdown склеил бы пункты списка в один абзац.
    @Test func formatBoldsInlineMarkdownAndKeepsTheLayout() {
        let formatted = TeleprompterStore.format("1. **Lokii** — починил\n\n2. ревью")
        #expect(String(formatted.characters) == "1. Lokii — починил\n\n2. ревью")
        let bold = formatted.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(bold.map { String(formatted[$0.range].characters) } == ["Lokii"])
    }

    /// Таблица из ответа чата остаётся таблицей: шапка, строки, `<br>` внутри
    /// ячейки — перенос, короткая строка дополняется до ширины шапки.
    @Test func parseTurnsAPastedTableIntoATable() {
        let blocks = TeleprompterBlock.parse("""
        Вот решения:

        | Результат | К чему | Как |
        |---|:---:|---|
        | Лендинг | Скриншот | `screenshot_url` |
        | Категория | Вся<br>проверка |
        """)
        #expect(blocks.count == 2)
        #expect(blocks.first == .text(TeleprompterStore.format("Вот решения:")))
        guard case .table(let header, let rows) = blocks.last else {
            Issue.record("no table in \(blocks)")
            return
        }
        #expect(header.map { String($0.characters) } == ["Результат", "К чему", "Как"])
        #expect(rows.map { $0.map { String($0.characters) } } == [
            ["Лендинг", "Скриншот", "screenshot_url"],
            ["Категория", "Вся\nпроверка", ""],
        ])
    }

    /// Заголовки, картинка на своей строке, цитата, код и черта — отдельные
    /// блоки; маркер списка становится точкой, переносы строк остаются.
    @Test func parsePicksOutBlocksAndKeepsPlainLines() {
        let blocks = TeleprompterBlock.parse("""
        ## План
        - первое
        - второе
        ![](teleprompter-images/shot.png)
        > важно
        ---
        ```
        let x = 1
        ```
        """)
        #expect(blocks == [
            .heading(level: 2, text: TeleprompterStore.format("План")),
            .text(TeleprompterStore.format("• первое\n• второе")),
            .image(source: "teleprompter-images/shot.png"),
            .quote(TeleprompterStore.format("важно")),
            .rule,
            .code("let x = 1"),
        ])
    }

    /// `**жирный**` в начале строки — не маркер списка, `#тег` — не заголовок.
    @Test func parseLeavesLookalikesAsText() {
        let blocks = TeleprompterBlock.parse("**Lokii** — починил\n#тег")
        #expect(blocks == [.text(TeleprompterStore.format("**Lokii** — починил\n#тег"))])
    }

    /// Вставленный скриншот ложится рядом со скриптом, а в текст попадает
    /// строкой `![](…)` там, где стоит каретка, и открывается по этому пути.
    @Test func attachedImageIsInsertedAtTheCaretAndResolves() throws {
        let (store, _) = try Self.makeStore(contents: "")
        store.script = "до\nпосле"
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let line = try #require(store.attachImage(png))
        store.selection = TextSelection(insertionPoint: store.script.index(store.script.startIndex, offsetBy: 2))
        store.insert(line)

        #expect(store.script == "до\n\(line)\nпосле")
        let source = String(line.dropFirst(4).dropLast())
        #expect(store.image(source) != nil)
    }
}
