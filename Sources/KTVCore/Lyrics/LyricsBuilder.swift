/// Turns parsed LRC stamps into timed lyric lines, estimating the singing pace from the song itself.
/// Pure functions only: the same input always yields the same lines.
public enum LyricsBuilder {
    /// The pace is the lower quartile of per-character gaps: index = count / divisor.
    private static let paceQuartileDivisor = 4
    /// Slot values alternate between 1 and 0 inside one section, starting at 1.
    private static let sectionStartSlot = 1

    /// Optional parentheses, a 男/女/合 label, then a colon. Group 1 is the label, group 2 the lyric.
    private static let partPattern = #/^[(（]?([男女合])[)）]?\s*[:：]\s*(.*)$/#

    /// One stamp after label stripping. `gap` is the distance to the next stamp, or nil for the last one.
    private struct Entry {
        let start: Double
        let gap: Double?
        let part: String?
        let text: String
    }

    /// Counts the characters that are sung (letters and digits), with a floor of 1.
    public static func sungCount(_ text: String) -> Int {
        max(1, text.filter { $0.isLetter || $0.isNumber }.count)
    }

    /// Seconds per sung character, taken from the lower quartile of gaps and capped at the maximum pace.
    public static func songRate(stamps: [LRCStamp]) -> Double {
        let rates = entries(from: stamps).compactMap { entry -> Double? in
            guard !entry.text.isEmpty, let gap = entry.gap else { return nil }
            return gap / Double(sungCount(entry.text))
        }.sorted()
        guard !rates.isEmpty else { return LyricsTiming.fallbackSecondsPerChar }
        let quartile = rates[rates.count / paceQuartileDivisor]
        return min(quartile, LyricsTiming.maxSecondsPerChar)
    }

    /// Builds timed lines, skipping blank end markers, and assigns each line its slot.
    public static func lines(from parsed: ParsedLRC) -> [LyricLine] {
        let rate = songRate(stamps: parsed.stamps)
        let timed = entries(from: parsed.stamps).filter { !$0.text.isEmpty }.map { entry in
            timedLine(entry, rate: rate)
        }
        return assigningSlots(timed)
    }

    /// Alternates slots within a section. A section starts after a gap of at least `interludeMinGap`
    /// between one line's hold end and the next line's start.
    public static func assigningSlots(_ lines: [LyricLine]) -> [LyricLine] {
        let slots = lines.indices.reduce(into: [Int]()) { result, index in
            let startsSection = index == 0
                || lines[index].start - lines[index - 1].holdEnd >= LyricsTiming.interludeMinGap
            let slot = startsSection ? sectionStartSlot : 1 - (result.last ?? sectionStartSlot)
            result.append(slot)
        }
        return zip(lines, slots).map { line, slot in
            LyricLine(
                start: line.start,
                end: line.end,
                holdEnd: line.holdEnd,
                text: line.text,
                part: line.part,
                slot: slot,
                words: line.words
            )
        }
    }

    private static func timedLine(_ entry: Entry, rate: Double) -> LyricLine {
        let chars = Double(sungCount(entry.text))
        let room = (entry.gap ?? LyricsTiming.lastLineGap) - LyricsTiming.lineGapMargin
        let end = entry.start + boundedSeconds(chars * rate, room: room)
        let wantedHold = max(LyricsTiming.minHoldSeconds, chars * LyricsTiming.holdSecondsPerChar)
        let holdEnd = entry.start + boundedSeconds(wantedHold, room: room)
        return LyricLine(
            start: entry.start,
            end: end,
            holdEnd: holdEnd,
            text: entry.text,
            part: entry.part
        )
    }

    /// Keeps a duration at least `minLineSeconds`, and at most the room before the next line.
    private static func boundedSeconds(_ wanted: Double, room: Double) -> Double {
        max(LyricsTiming.minLineSeconds, min(room, wanted))
    }

    /// Sorts stamps by time, strips part labels and records each stamp's gap to the next one.
    private static func entries(from stamps: [LRCStamp]) -> [Entry] {
        let sorted = stamps.sorted { $0.time < $1.time }
        let nextTimes: [Double?] = sorted.dropFirst().map { $0.time } + [nil]
        return zip(sorted, nextTimes).map { stamp, nextTime in
            let (part, text) = split(stamp.text)
            return Entry(
                start: stamp.time,
                gap: nextTime.map { $0 - stamp.time },
                part: part,
                text: text
            )
        }
    }

    /// Removes a leading part label. `(男)：`, `男：` and `合：` all normalize to `男：`, `女：` or `合：`.
    private static func split(_ text: String) -> (part: String?, text: String) {
        guard let match = text.firstMatch(of: partPattern) else { return (nil, text) }
        return ("\(match.1)：", String(match.2))
    }
}
