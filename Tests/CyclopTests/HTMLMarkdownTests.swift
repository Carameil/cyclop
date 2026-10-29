import Foundation
import Testing
@testable import Cyclop

/// Тесты на `HTMLMarkdown.convert` — ответ из чата, скопированный выделением,
/// вставляется в телесуфлёр тем markdown, из которого был отрисован.
struct HTMLMarkdownTests {

    /// Так выглядит буфер после копирования ответа из браузера: заголовок,
    /// абзац с жирным и кодом, таблица с шапкой в `thead`.
    @Test func chatAnswerComesBackAsMarkdown() throws {
        let html = """
        <meta charset="utf-8"><h3>В NativeAds два случая</h3>
        <p>Формат построен вокруг <strong>скриншотов</strong> и поля <code>url</code>:</p>
        <table><thead><tr><th>Результат</th><th>Как обозначить</th></tr></thead>
        <tbody><tr><td>Решение по лендингу</td><td><code>screenshot_url</code></td></tr>
        <tr><td>Категория</td><td><code>campaign_check_id</code>, без скриншота</td></tr></tbody></table>
        """
        let markdown = try #require(HTMLMarkdown.convert(html))
        #expect(markdown == """
        ### В NativeAds два случая

        Формат построен вокруг **скриншотов** и поля `url`:

        | Результат | Как обозначить |
        |---|---|
        | Решение по лендингу | `screenshot_url` |
        | Категория | `campaign_check_id`, без скриншота |
        """)
    }

    /// Списки, в том числе вложенный, и абзацы внутри пунктов.
    @Test func listsKeepTheirNumbersAndNesting() throws {
        let html = "<ol><li><p>Первое</p><ul><li>деталь</li></ul></li><li><p>Второе</p></li></ol>"
        #expect(try #require(HTMLMarkdown.convert(html)) == "1. Первое\n  - деталь\n2. Второе")
    }

    /// Из редактора кода приходят цветные `span` — это не разметка, такой
    /// текст вставляется как есть, с отступами.
    @Test func plainSpansAreLeftToThePlainText() {
        #expect(HTMLMarkdown.convert("<div><span>let x</span><br><span>    = 1</span></div>") == nil)
    }
}
