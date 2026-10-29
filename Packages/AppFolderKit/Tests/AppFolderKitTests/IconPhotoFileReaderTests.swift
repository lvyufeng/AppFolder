import Darwin
import Foundation
import Testing
@testable import AppFolderKit

@Suite("Selected icon file reads")
struct IconPhotoFileReaderTests {
    @Test("Coordinated reads return selected bytes without altering or copying the file")
    func coordinatedRead() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
        try bytes.write(to: fixture.file)
        let result = try await IconPhotoFileReader.read(url: fixture.file)
        #expect(result == bytes)
        #expect(try Data(contentsOf: fixture.file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["selected.png"])
    }

    @Test("A source at the byte cap is accepted and a larger source is rejected")
    func exactLimit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data(repeating: 42, count: 128)
        try bytes.write(to: fixture.file)
        #expect(try IconPhotoFileReader.readContents(at: fixture.file, maximumBytes: 128) == bytes)
        #expect(throws: IconPhotoImportError.tooManyBytes) {
            try IconPhotoFileReader.readContents(at: fixture.file, maximumBytes: 127)
        }
    }

    @Test("Growth after fstat cannot bypass the byte cap")
    func growingSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data(repeating: 1, count: 16).write(to: fixture.file)
        var checks = 0
        #expect(throws: IconPhotoImportError.tooManyBytes) {
            try IconPhotoFileReader.readContents(at: fixture.file, maximumBytes: 32) {
                checks += 1
                if checks == 2 {
                    let writer = try FileHandle(forWritingTo: fixture.file)
                    defer { try? writer.close() }
                    try writer.seekToEnd()
                    try writer.write(contentsOf: Data(repeating: 2, count: 32))
                }
            }
        }
    }

    @Test("Cancellation during a multi-chunk read returns no partial image")
    func cancellationDuringRead() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data(repeating: 6, count: 150_000).write(to: fixture.file)
        var checks = 0
        #expect(throws: CancellationError.self) {
            try IconPhotoFileReader.readContents(at: fixture.file) {
                checks += 1
                if checks == 3 { throw CancellationError() }
            }
        }
        #expect(try fixture.file.resourceValues(forKeys: [.fileSizeKey]).fileSize == 150_000)
    }

    @Test("Already cancelled import never publishes file bytes")
    func alreadyCancelled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([1, 2, 3]).write(to: fixture.file)
        let cancelled = await withTaskGroup(of: Bool.self) { group in
            group.cancelAll()
            group.addTask {
                do { _ = try await IconPhotoFileReader.read(url: fixture.file); return false }
                catch is CancellationError { return true }
                catch { return false }
            }
            return await group.next() ?? false
        }
        #expect(cancelled)
    }

    @Test("Directories, symlinks, and named pipes cannot become source image files")
    func regularFilesOnly() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([7, 8, 9]).write(to: fixture.file)
        let link = fixture.directory.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.file)
        let pipe = fixture.directory.appendingPathComponent("pipe.png")
        #expect(mkfifo(pipe.path, S_IRUSR | S_IWUSR) == 0)
        for url in [fixture.directory, link, pipe] {
            #expect(throws: (any Error).self) { try IconPhotoFileReader.readContents(at: url) }
        }
        #expect(try Data(contentsOf: fixture.file) == Data([7, 8, 9]))
    }

    @Test("Remote URLs and missing files fail without downloading a URL")
    func invalidSelection() async throws {
        let remote = try #require(URL(string: "https://example.org/selected.png"))
        await #expect(throws: (any Error).self) { try await IconPhotoFileReader.read(url: remote) }
        let fixture = try Fixture()
        defer { fixture.remove() }
        await #expect(throws: (any Error).self) { try await IconPhotoFileReader.read(url: fixture.file) }
    }

    private struct Fixture: Sendable {
        let directory: URL
        let file: URL
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("IconFileRead-\(UUID())")
            file = directory.appendingPathComponent("selected.png")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
