public struct WordTiming: Equatable, Codable, Sendable {
    public let text: String
    public let start, duration: Double

    public init(text: String, start: Double, duration: Double) {
        self.text = text
        self.start = start
        self.duration = duration
    }
}

public struct LyricLine: Equatable, Codable, Sendable {
    public let start, end, holdEnd: Double
    public let text: String
    public let part: String?
    public let slot: Int
    public let words: [WordTiming]?

    public init(
        start: Double,
        end: Double,
        holdEnd: Double,
        text: String,
        part: String? = nil,
        slot: Int = 1,
        words: [WordTiming]? = nil
    ) {
        self.start = start
        self.end = end
        self.holdEnd = holdEnd
        self.text = text
        self.part = part
        self.slot = slot
        self.words = words
    }
}

public enum LyricsSource: String, Codable, Sendable {
    case lrclib, netease, imported
}

public struct Lyrics: Equatable, Codable, Sendable {
    public let source: LyricsSource
    public let lines: [LyricLine]
    public let credits: [String]

    public init(source: LyricsSource, lines: [LyricLine], credits: [String]) {
        self.source = source
        self.lines = lines
        self.credits = credits
    }

    public var isWordTimed: Bool {
        lines.contains { $0.words != nil }
    }
}

public struct LRCStamp: Equatable, Sendable {
    public let time: Double
    public let text: String

    public init(time: Double, text: String) {
        self.time = time
        self.text = text
    }
}

public struct ParsedLRC: Equatable, Sendable {
    public let stamps: [LRCStamp]
    public let credits: [String]

    public init(stamps: [LRCStamp], credits: [String]) {
        self.stamps = stamps
        self.credits = credits
    }
}
