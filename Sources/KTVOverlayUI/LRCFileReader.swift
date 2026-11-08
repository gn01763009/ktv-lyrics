import Foundation

/// Why a chosen file could not be used as lyrics. Descriptions are shown to the user.
enum LRCFileError: LocalizedError, Equatable {
    case tooLarge
    case notUTF8
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "檔案超過 1 MB，不像是歌詞檔"
        case .notUTF8: return "檔案不是 UTF-8 編碼，請先轉成 UTF-8"
        case .unreadable(let reason): return "讀不到檔案：\(reason)"
        }
    }
}

/// Reads a lyrics file chosen by the user, with a size cap and strict UTF-8.
enum LRCFileReader {
    static let maxBytes = 1_048_576

    static func read(_ url: URL) throws -> String {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        } catch {
            throw LRCFileError.unreadable(error.localizedDescription)
        }
        guard data.count <= maxBytes else { throw LRCFileError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw LRCFileError.notUTF8 }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
