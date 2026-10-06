import Foundation
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
}
