import Foundation
@testable import KTVOverlayUI
import Testing

@Suite struct LRCFileReaderTests {
    private static func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ktv-\(UUID().uuidString).lrc")
        try data.write(to: url)
        return url
    }

    @Test func readsUTF8AndDropsBOM() throws {
        let url = try Self.write(Data("\u{FEFF}[00:01.00]你好".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try LRCFileReader.read(url) == "[00:01.00]你好")
    }

    @Test func rejectsFilesOverOneMegabyte() throws {
        let url = try Self.write(Data(count: LRCFileReader.maxBytes + 1))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: LRCFileError.tooLarge) { try LRCFileReader.read(url) }
    }

    @Test func rejectsNonUTF8() throws {
        let url = try Self.write(Data([0xFF, 0xFE, 0xFA]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: LRCFileError.notUTF8) { try LRCFileReader.read(url) }
    }

    @Test func missingFileIsReported() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).lrc")
        #expect(throws: LRCFileError.self) { try LRCFileReader.read(url) }
    }
}
