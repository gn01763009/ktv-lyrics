/// How far the colour sweep has progressed through a line at a given time.
public enum Sweep: Equatable, Sendable {
    /// Whole-line progress, 0...1, for lines without word timing.
    case linear(Double)
    /// Word `index` is `progress` (0...1) of the way sung.
    case word(index: Int, progress: Double)
}

public extension LyricLine {
    /// The sweep state at `time`. Word-timed lines use their words; all others sweep across start...end.
    func sweep(at time: Double) -> Sweep {
        guard let words, !words.isEmpty else { return linearSweep(at: time) }
        return wordSweep(words, at: time)
    }

    private func linearSweep(at time: Double) -> Sweep {
        let length = end - start
        guard length > 0 else { return .linear(time >= start ? 1 : 0) }
        return .linear(Self.unitClamped((time - start) / length))
    }

    /// Before the first word the sweep is at word 0. Between two words it is at the next word, not started yet.
    private func wordSweep(_ words: [WordTiming], at time: Double) -> Sweep {
        guard let first = words.first, time >= first.start else { return .word(index: 0, progress: 0) }
        for (index, word) in words.enumerated() {
            if time < word.start { return .word(index: index, progress: 0) }
            if time < word.start + word.duration {
                return .word(index: index, progress: (time - word.start) / word.duration)
            }
        }
        return .word(index: words.count - 1, progress: 1)
    }

    private static func unitClamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
