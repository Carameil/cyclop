import Foundation
import Testing
@testable import Cyclop

/// Хранение снимков по дням. Тестируется отбор файлов, а не отправка в
/// Корзину: она трогает настоящую Корзину того, кто запустил тесты.
struct ScreenshotVaultTests {

    private static func makeFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cyclop-vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func touch(_ name: String, in folder: URL, created: Date) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("png".utf8).write(to: url)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        return url
    }

    @Test func onlyFilesCreatedBeforeTheCutoffExpire() throws {
        let folder = try Self.makeFolder()
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let old = try Self.touch("old.png", in: folder, created: cutoff.addingTimeInterval(-3600))
        let fresh = try Self.touch("fresh.png", in: folder, created: cutoff.addingTimeInterval(3600))
        _ = try Self.touch("exact.png", in: folder, created: cutoff)

        let expired = ScreenshotVault.expired(in: folder, before: cutoff)
        #expect(expired.map(\.lastPathComponent) == [old.lastPathComponent])
        #expect(!expired.contains(fresh))
    }

    @Test func hiddenFilesAndFoldersAreSkipped() throws {
        let folder = try Self.makeFolder()
        let cutoff = Date()
        _ = try Self.touch(".DS_Store", in: folder, created: cutoff.addingTimeInterval(-86_400))
        let sub = folder.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.creationDate: cutoff.addingTimeInterval(-86_400)], ofItemAtPath: sub.path)

        #expect(ScreenshotVault.expired(in: folder, before: cutoff).isEmpty)
    }

    @Test func missingFolderExpiresNothing() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        #expect(ScreenshotVault.expired(in: missing, before: Date()).isEmpty)
    }

    /// Ноль и меньше — «хранить всегда», как и до форка: ничего не трогается,
    /// даже если папка полна.
    @Test func nonPositiveRetentionPurgesNothing() {
        #expect(ScreenshotVault.purge(keepingDays: 0).isEmpty)
        #expect(ScreenshotVault.purge(keepingDays: -1).isEmpty)
    }
}
