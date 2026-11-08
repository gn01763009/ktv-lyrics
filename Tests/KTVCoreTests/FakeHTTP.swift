import Foundation
@testable import KTVCore

/// Answers requests by URL substring and records every requested URL.
/// When several route keys occur in one URL, the longest key wins, so the answer does not depend on dictionary order.
final class FakeHTTP: HTTPFetching, @unchecked Sendable {
    private let routes: [String: Result<Data, Error>]
    private let lock = NSLock()
    private var requested: [URL] = []

    init(routes: [String: Result<Data, Error>]) {
        self.routes = routes
    }

    var urls: [URL] {
        lock.withLock { requested }
    }

    var hosts: [String] {
        urls.compactMap(\.host)
    }

    func data(from url: URL) async throws -> Data {
        lock.withLock { requested.append(url) }
        let key = routes.keys.filter { url.absoluteString.contains($0) }.max { $0.count < $1.count }
        guard let key, let route = routes[key] else { throw URLError(.cannotConnectToHost) }
        return try route.get()
    }
}

/// LRCLIB behaviours the resolver tests exercise.
enum LRCLIBScenario {
    case standard, withCredit, empty, otherSong, unsynced, garbage, freeTextOnly
}

/// NetEase behaviours the resolver tests exercise. `offset` shifts word timing, in seconds.
enum NetEaseScenario {
    case wordTimed(offset: Double), noYRC, failing, otherSong, garbage
}

extension FakeHTTP {
    /// Every route answers normally, with NetEase word timing that matches LRCLIB.
    static var standard: FakeHTTP {
        FakeHTTP(routes: routes(lrclib: .standard, netease: .wordTimed(offset: 0)))
    }

    static func routes(lrclib: LRCLIBScenario, netease: NetEaseScenario) -> [String: Result<Data, Error>] {
        lrclibRoutes(lrclib).merging(neteaseRoutes(netease)) { first, _ in first }
    }

    private static func lrclibRoutes(_ scenario: LRCLIBScenario) -> [String: Result<Data, Error>] {
        let host = "lrclib.net"
        let empty = Result<Data, Error>.success(Data("[]".utf8))
        switch scenario {
        case .standard:
            return [host: .success(lrclibJSON(lines: syncedLRC))]
        case .withCredit:
            return [host: .success(lrclibJSON(lines: creditLRC + "\n" + syncedLRC))]
        case .empty:
            return [host: empty]
        case .otherSong:
            return [host: .success(lrclibJSON(title: "盛夏", lines: syncedLRC))]
        case .unsynced:
            return [host: .success(lrclibJSON(lines: nil))]
        case .garbage:
            return [host: .success(Data("not json".utf8))]
        case .freeTextOnly:
            // The track_name query finds nothing, so the resolver must fall back to the free-text query.
            return [host: .success(lrclibJSON(lines: syncedLRC)), "track_name=": empty]
        }
    }

    private static func neteaseRoutes(_ scenario: NetEaseScenario) -> [String: Result<Data, Error>] {
        let search = "music.163.com/api/search"
        let lyric = "music.163.com/api/song/lyric"
        switch scenario {
        case .wordTimed(let offset):
            return [
                search: .success(neteaseSearchJSON()),
                lyric: .success(neteaseLyricJSON(yrc: true, offset: offset)),
            ]
        case .noYRC:
            return [
                search: .success(neteaseSearchJSON()),
                lyric: .success(neteaseLyricJSON(yrc: false)),
            ]
        case .failing:
            return [search: .failure(URLError(.timedOut))]
        case .otherSong:
            // The lyric route answers with real lyrics, so a resolver that skips the title check would show them.
            return [
                search: .success(neteaseSearchJSON(title: "盛夏", id: 10)),
                lyric: .success(neteaseLyricJSON(yrc: true)),
            ]
        case .garbage:
            return [search: .success(Data("not json".utf8))]
        }
    }
}

/// Synced LRC lines at 10, 20, 30 and 40 seconds.
let syncedLRC = "[00:10.00]第一句\n[00:20.00]第二句\n[00:30.00]第三句\n[00:40.00]第四句"

/// The same timing as `syncedLRC`, in simplified Chinese as NetEase sends it.
let neteaseLRC = "[00:10.00]这是第一句\n[00:20.00]第二句\n[00:30.00]第三句\n[00:40.00]第四句"

/// A credit row inside an LRC, before the first lyric line.
let creditLRC = "[00:05.00]作词: 某人"

/// The JSON credit row that starts both NetEase lyric fields.
let creditHeader = "{\"t\":0,\"c\":[{\"tx\":\"作词: \"},{\"tx\":\"五月天 阿信\"}]}"

/// One LRCLIB search response holding one hit. A nil `lines` sends `syncedLyrics` as null.
func lrclibJSON(title: String = "溫柔", lines: String?) -> Data {
    let synced: Any = lines.map { $0 as Any } ?? NSNull()
    let hit: [String: Any] = [
        "id": 1,
        "trackName": title,
        "artistName": "五月天",
        "duration": 270,
        "syncedLyrics": synced,
    ]
    return encodeJSON([hit])
}

/// One NetEase search response holding one song.
func neteaseSearchJSON(title: String = "溫柔", id: Int = 9) -> Data {
    let song: [String: Any] = [
        "id": id,
        "name": title,
        "artists": [["name": "五月天"]],
        "duration": 270000,
    ]
    let body: [String: Any] = ["result": ["songs": [song]]]
    return encodeJSON(body)
}

/// One NetEase lyric response. `yrc: false` omits the yrc field, and `offset` shifts every word start.
func neteaseLyricJSON(yrc: Bool, offset: Double = 0) -> Data {
    var body: [String: Any] = ["lrc": ["lyric": creditHeader + "\n" + neteaseLRC]]
    if yrc {
        body["yrc"] = ["lyric": creditHeader + "\n" + yrcLines(offset: offset)]
    }
    return encodeJSON(body)
}

/// Word-timed rows starting at 10, 20, 30 and 40 seconds, each with two words.
func yrcLines(offset: Double) -> String {
    let milliseconds = 1000.0
    return [10, 20, 30, 40].map { second -> String in
        let start = Int((Double(second) + offset) * milliseconds)
        return "[\(start),1000](\(start),500,0)这(\(start + 500),500,0)是"
    }.joined(separator: "\n")
}

private func encodeJSON(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}
