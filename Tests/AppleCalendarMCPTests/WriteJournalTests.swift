import Foundation
import Testing
@testable import AppleCalendarMCP

/// A journal that cannot be written must say so: before a change, to stop it,
/// and after one, to report it. It used to fail into the system log only.
struct WriteJournalTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "WriteJournalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func readOnlyJournal() throws -> WriteJournal {
        let url = folder.appending(path: "journal.log")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path(percentEncoded: false))
        return WriteJournal(url: url)
    }

    @Test("A missing journal is created, folder included")
    func createsMissing() async throws {
        let url = folder.appending(path: "Logs/journal.log")
        try await WriteJournal(url: url).checkWritable()
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test("A read-only journal fails the check, and says why in English")
    func readOnly() async throws {
        let journal = try readOnlyJournal()
        let error = await #expect(throws: WriteJournal.Failure.self) { try await journal.checkWritable() }
        #expect(error?.localizedDescription.hasSuffix("Permission denied (errno 13)") == true)
    }

    @Test("Errors are described from their POSIX cause, not the Mac's language", arguments: [
        (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
        ]), "Permission denied (errno 13)"),
        (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), "No space left on device (errno 28)"),
        (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError), "NSCocoaErrorDomain error 512"),
    ])
    func describe(_ error: NSError, _ expected: String) {
        #expect(WriteJournal.describe(error) == expected)
    }

    @Test("A folder where the journal should be fails the check")
    func folderInTheWay() async throws {
        let url = folder.appending(path: "journal.log")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        await #expect(throws: WriteJournal.Failure.self) { try await WriteJournal(url: url).checkWritable() }
    }

    @Test("Appending to a journal that cannot be written throws, rather than only logging")
    func appendThrows() async throws {
        let journal = try readOnlyJournal()
        await #expect(throws: WriteJournal.Failure.self) { try await journal.append(Data("{}".utf8)) }
    }

    @Test("Appending adds one line")
    func appends() async throws {
        let url = folder.appending(path: "journal.log")
        let journal = WriteJournal(url: url)
        try await journal.append(Data("{}".utf8))
        try await journal.append(Data("{}".utf8))
        #expect(try String(contentsOf: url, encoding: .utf8) == "{}\n{}\n")
    }
}
