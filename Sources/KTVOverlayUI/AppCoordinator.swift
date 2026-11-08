import Foundation
import KTVCore
import os

/// Joins playback events, the player clock, the lyrics lookup and the user's settings into the
/// content the overlay draws. It owns no windows; the controller feeds it events and asks for `content()`.
@MainActor
public final class AppCoordinator {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "AppCoordinator")

    /// What is known about the song being played. Replaced as a whole, never edited in place.
    private struct CurrentTrack {
        let query: TrackQuery
        let trackKey: String
        let usesRedTitle: Bool
        let songOverride: SongOverride
    }

    private struct LoadedLyrics {
        let lyrics: Lyrics
        let engine: SceneEngine
    }

    private struct TimedNotice {
        let text: String
        let since: Double
    }

    private enum LookupState: Equatable {
        case idle
        case searching(since: Double)
        case notFound(at: Double)
        case unavailable(at: Double)
        case found
    }

    private let makeResolver: (Bool) -> any LyricsResolving
    private let baseCache: LyricsCache
    private var locator: LyricsLocator
    private let overrides: SongOverrideStore
    private let clock: any PlayerClockReading
    private let runningApps: () -> Set<String>
    private let now: () -> Double

    private var resolver: any LyricsResolving
    private var settings: OverlaySettings
    private var gate = LookupGate()
    private var lookupTask: Task<Void, Never>?
    private var snapshot: PlaybackSnapshot?
    private var track: CurrentTrack?
    private var loaded: LoadedLyrics?
    private var lookup = LookupState.idle
    private var positionResolver = PositionResolver()
    private var adapterStatus = AdapterStatus.running
    private var offered: [LyricsCandidate] = []
    private var userNotice: TimedNotice?
    /// When a track arrived without a duration, the time after which it is looked up anyway, without caching.
    private var lookupDeadline: Double?

    public init(
        makeResolver: @escaping (_ useNetEase: Bool) -> any LyricsResolving,
        cache: LyricsCache,
        overrides: SongOverrideStore,
        settings: OverlaySettings,
        clock: any PlayerClockReading,
        runningApps: @escaping () -> Set<String>,
        now: @escaping () -> Double
    ) {
        self.makeResolver = makeResolver
        self.baseCache = cache
        self.locator = LyricsLocator(cache: cache.scoped(Self.cacheScope(useNetEase: settings.useNetEase)))
        self.overrides = overrides
        self.settings = settings
        self.clock = clock
        self.runningApps = runningApps
        self.now = now
        self.resolver = makeResolver(settings.useNetEase)
    }

    /// The cache subdirectory for a NetEase setting. Lookups made with NetEase off are not trusted when it is on.
    static func cacheScope(useNetEase: Bool) -> String {
        useNetEase ? "netease-on" : "netease-off"
    }

    // MARK: - Events

    public func handle(_ event: AdapterEvent) {
        switch event {
        case .playing(let incoming):
            let merged = incoming.merging(previous: snapshot)
            let previous = snapshot
            let isNewTrack = merged.trackKey != previous?.trackKey
            snapshot = merged
            if isNewTrack {
                startTrack(merged)
            } else if let previous, abs(merged.duration - previous.duration) > CoordinatorText.durationChangeSeconds {
                restartLookup(merged)
            }
            pollClock()
        case .nothing:
            clearTrack()
        case .ignored:
            break
        }
    }

    /// Asks the playing app for its own clock and lets the position resolver decide whether to correct.
    public func pollClock() {
        guard let snapshot,
              let player = ScriptablePlayer.toPoll(bundleID: snapshot.bundleID, running: runningApps()),
              let sample = clock.read(player) else { return }
        positionResolver = positionResolver.applying(sample, snapshot: snapshot)
    }

    /// Starts a lookup that was held back for a missing duration once its grace period is over.
    /// The result is not cached, because the query has no duration. Call this regularly.
    public func advance() {
        guard let deadline = lookupDeadline, now() >= deadline, let track else { return }
        lookupDeadline = nil
        beginLookup(query: track.query, songOverride: track.songOverride, id: gate.currentID, cacheable: false)
    }

    public func setAdapterStatus(_ status: AdapterStatus) {
        adapterStatus = status
    }

    public func apply(settings newSettings: OverlaySettings) {
        let providersChanged = newSettings.useNetEase != settings.useNetEase
        if providersChanged {
            resolver = makeResolver(newSettings.useNetEase)
            locator = LyricsLocator(cache: baseCache.scoped(Self.cacheScope(useNetEase: newSettings.useNetEase)))
        }
        settings = newSettings
        // Read the matching cache scope for the song on screen, unless its first lookup is still held back.
        if providersChanged, let snapshot, lookupDeadline == nil { restartLookup(snapshot) }
    }

    /// Moves this song's lyrics by `delta` seconds (positive shows them earlier) and remembers it.
    public func adjustOffset(by delta: Double) {
        guard let track else { return }
        remember(SongOverride(
            offset: track.songOverride.offset + delta,
            importedLRC: track.songOverride.importedLRC,
            candidateID: track.songOverride.candidateID
        ), for: track)
    }

    // MARK: - Versions and import

    /// The versions offered for the playing song. Empty when nothing is playing.
    /// `selectCandidate(id:)` can pick from the most recent answer.
    public func availableCandidates() async -> [LyricsCandidate] {
        guard let track else { return [] }
        let found = await resolver.candidates(track.query)
        if self.track?.trackKey == track.trackKey { offered = found }
        return found
    }

    /// The version the user picked for the playing song, if any.
    public var selectedCandidateID: String? { track?.songOverride.candidateID }

    /// Shows the version `id` from the last `availableCandidates()` and remembers it for this song.
    /// It replaces imported text, which would otherwise win again next time. The offset is kept.
    public func selectCandidate(id: String) {
        guard let track else { return }
        guard let candidate = offered.first(where: { $0.id == id }) else {
            Self.logger.error("Lyrics version \(id, privacy: .public) was not among the offered versions")
            return
        }
        show(candidate.lyrics, for: track)
        remember(SongOverride(offset: track.songOverride.offset, importedLRC: nil, candidateID: id), for: track)
    }

    /// Uses `raw` as this song's lyrics and remembers it. Text with no timed lines changes nothing but shows a notice.
    /// It replaces a chosen version, since imported text wins. The offset is kept.
    public func importLRC(_ raw: String) {
        guard let track else {
            postNotice(CoordinatorText.importNeedsSong)
            return
        }
        let parsed = LRCParser.parse(raw)
        let lines = LyricsBuilder.lines(from: parsed)
        guard !lines.isEmpty else {
            Self.logger.error("Imported text has no usable timed lines")
            postNotice(CoordinatorText.importUnusable)
            return
        }
        show(Lyrics(source: .imported, lines: lines, credits: parsed.credits), for: track)
        remember(SongOverride(offset: track.songOverride.offset, importedLRC: raw, candidateID: nil), for: track)
    }

    /// Shows a short message on the overlay. It is urgent: every notice posted here reports a failure
    /// the user must see, so it is drawn even while lyrics are on screen.
    public func postNotice(_ text: String) {
        userNotice = TimedNotice(text: text, since: now())
    }

    /// Resolves once the current lookup has finished. For tests.
    public func waitForLookup() async {
        await lookupTask?.value
    }

    // MARK: - Output

    public func content() -> OverlayContent {
        guard let snapshot, let track else { return noticeOnly() }
        return OverlayContent(
            scene: scene(for: snapshot, track: track),
            lines: loaded?.lyrics.lines ?? [],
            title: track.query.title,
            artist: track.query.artist,
            credits: loaded?.lyrics.credits ?? [],
            notice: notice(for: track),
            noticeIsUrgent: activeUserNotice() != nil,
            usesRedTitle: track.usesRedTitle
        )
    }

    public var statusText: String {
        switch adapterStatus {
        case .restarting: return CoordinatorText.adapterRestarting
        case .failed: return CoordinatorText.adapterFailed
        case .running: break
        }
        guard let track else { return CoordinatorText.waiting }
        let title = track.query.title
        if let loaded { return CoordinatorText.found(title, lyrics: loaded.lyrics) }
        switch lookup {
        case .notFound: return CoordinatorText.notFound(title)
        case .unavailable: return CoordinatorText.unavailable(title)
        default: break
        }
        return CoordinatorText.searching(title)
    }

    private func scene(for snapshot: PlaybackSnapshot, track: CurrentTrack) -> KaraokeScene {
        guard let loaded, let position = positionResolver.position(snapshot: snapshot, now: now()) else { return .idle }
        let lead = loaded.lyrics.isWordTimed ? 0 : LyricsTiming.subtitleLead
        let shown = position + track.songOverride.offset + lead
        return CoordinatorText.filtered(loaded.engine.scene(at: shown), by: settings)
    }

    private func noticeOnly() -> OverlayContent {
        let notice = activeUserNotice()
        return OverlayContent(scene: .idle, lines: [], title: "", notice: notice, noticeIsUrgent: notice != nil)
    }

    private func activeUserNotice() -> String? {
        guard let userNotice, now() - userNotice.since < CoordinatorText.userNoticeSeconds else { return nil }
        return userNotice.text
    }

    private func notice(for track: CurrentTrack) -> String? {
        if let message = activeUserNotice() { return message }
        let title = track.query.title
        switch lookup {
        case .searching(let since) where now() - since < CoordinatorText.lookupNoticeSeconds:
            return CoordinatorText.lookupNotice(title)
        case .notFound(let at) where now() - at < CoordinatorText.notFoundNoticeSeconds:
            return CoordinatorText.notFoundNotice(title)
        case .unavailable(let at) where now() - at < CoordinatorText.notFoundNoticeSeconds:
            return CoordinatorText.unavailableNotice
        default:
            return nil
        }
    }

    // MARK: - Track changes and lookups

    private func startTrack(_ snapshot: PlaybackSnapshot) {
        let query = TitleNormalizer.query(from: snapshot)
        let hash = StableHash.fnv1a(snapshot.trackKey)
        let songOverride = overrides.load(query)
        gate = gate.next()
        track = CurrentTrack(query: query, trackKey: snapshot.trackKey, usesRedTitle: hash % 2 == 0, songOverride: songOverride)
        loaded = nil
        offered = []
        userNotice = nil
        positionResolver = PositionResolver()
        lookup = .searching(since: now())
        lookupDeadline = nil
        if snapshot.duration > 0 {
            beginLookup(query: query, songOverride: songOverride, id: gate.currentID, cacheable: true)
        } else {
            lookupDeadline = now() + CoordinatorText.durationGraceSeconds
        }
    }

    /// The same song reported a different duration: look it up again with the final one, and reload what
    /// the user stored for that query. Lyrics already on screen stay until the new answer arrives.
    private func restartLookup(_ snapshot: PlaybackSnapshot) {
        guard let track else { return }
        let query = TitleNormalizer.query(from: snapshot)
        let songOverride = overrides.load(query)
        gate = gate.next()
        self.track = CurrentTrack(
            query: query, trackKey: track.trackKey, usesRedTitle: track.usesRedTitle, songOverride: songOverride
        )
        offered = []
        lookupDeadline = nil
        if loaded == nil { lookup = .searching(since: now()) }
        beginLookup(query: query, songOverride: songOverride, id: gate.currentID, cacheable: snapshot.duration > 0)
    }

    /// The task is never cancelled: a cancelled network call would be cached as "not found".
    /// A superseded lookup finishes quietly and `finishLookup` drops its result.
    private func beginLookup(query: TrackQuery, songOverride: SongOverride, id: Int, cacheable: Bool) {
        let locator = self.locator
        let resolver = self.resolver
        lookupTask = Task { [weak self] in
            let outcome = await locator.locate(query, override: songOverride, resolver: resolver, usesCache: cacheable)
            self?.finishLookup(outcome, id: id)
        }
    }

    private func finishLookup(_ outcome: LyricsOutcome, id: Int) {
        guard gate.accepts(id), let track else { return }
        switch outcome {
        case .found(let lyrics), .foundPartial(let lyrics):
            show(lyrics, for: track)
        case .notFound:
            lookup = .notFound(at: now())
        case .unavailable:
            lookup = .unavailable(at: now())
        }
    }

    /// Makes `lyrics` current and drops the result of any lookup still running.
    private func show(_ lyrics: Lyrics, for track: CurrentTrack) {
        let seed = StableHash.fnv1a(track.trackKey)
        let banners = BannerPlanner.plan(lines: lyrics.lines, seed: seed)
        loaded = LoadedLyrics(lyrics: lyrics, engine: SceneEngine(lines: lyrics.lines, bannerAfter: banners))
        lookup = .found
        gate = gate.next()
    }

    private func remember(_ songOverride: SongOverride, for track: CurrentTrack) {
        do {
            try overrides.save(songOverride, for: track.query)
        } catch {
            Self.logger.error("Could not save the song override: \(error.localizedDescription, privacy: .public)")
            postNotice(CoordinatorText.saveFailed)
        }
        self.track = CurrentTrack(
            query: track.query, trackKey: track.trackKey,
            usesRedTitle: track.usesRedTitle, songOverride: songOverride
        )
    }

    /// Nothing is playing: forget the song, and make any lookup still running drop its result.
    private func clearTrack() {
        gate = gate.next()
        snapshot = nil
        track = nil
        loaded = nil
        offered = []
        lookup = .idle
        lookupDeadline = nil
        positionResolver = PositionResolver()
    }
}
