/// What the overlay shows at one moment of playback.
public enum KaraokeScene: Equatable, Sendable {
    case idle
    case title
    case countdown(upcoming: Int, stars: Int)
    case singing(index: Int, sweep: Sweep)
    case held(index: Int)
    case interlude(showBanner: Bool)
}

/// Maps a playback position to the scene on screen. Pure: the same lines and position always give the same scene.
public struct SceneEngine: Sendable {
    private let lines: [LyricLine]
    /// Indexes of the line before each interlude that shows a banner.
    private let bannerAfter: Set<Int>

    public init(lines: [LyricLine], bannerAfter: Set<Int>) {
        self.lines = lines
        self.bannerAfter = bannerAfter
    }

    public func scene(at position: Double) -> KaraokeScene {
        guard let first = lines.first else { return .idle }
        if position < first.start { return leadScene(before: first, at: position) }
        guard let index = lines.lastIndex(where: { $0.start <= position }) else { return .idle }
        let line = lines[index]
        if position < line.end { return .singing(index: index, sweep: line.sweep(at: position)) }
        return afterLine(at: index, position: position)
    }

    /// Scenes before the first line: the title card, or the countdown when the first line is close.
    private func leadScene(before first: LyricLine, at position: Double) -> KaraokeScene {
        if position >= first.start - LyricsTiming.countdownSeconds {
            return countdown(upcoming: 0, startsAt: first.start, at: position)
        }
        return position < LyricsTiming.titleMaxSeconds ? .title : .idle
    }

    /// Scenes after line `index` has finished singing: held, interlude, or the end of the song.
    private func afterLine(at index: Int, position: Double) -> KaraokeScene {
        let line = lines[index]
        guard index + 1 < lines.count else {
            return position < line.end + LyricsTiming.trailingHold ? .held(index: index) : .idle
        }
        let next = lines[index + 1]
        guard next.start - line.holdEnd >= LyricsTiming.interludeMinGap else { return .held(index: index) }
        if position >= next.start - LyricsTiming.countdownSeconds {
            return countdown(upcoming: index + 1, startsAt: next.start, at: position)
        }
        return .interlude(showBanner: bannerAfter.contains(index))
    }

    /// Stars still lit: one goes out every `starSeconds`, and at least one stays lit until the line starts.
    private func countdown(upcoming: Int, startsAt start: Double, at position: Double) -> KaraokeScene {
        let elapsed = position - (start - LyricsTiming.countdownSeconds)
        let litStars = LyricsTiming.starCount - Int(elapsed / LyricsTiming.starSeconds)
        return .countdown(upcoming: upcoming, stars: max(1, litStars))
    }
}
