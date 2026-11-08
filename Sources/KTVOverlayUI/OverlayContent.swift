import KTVCore

/// Everything the overlay needs to draw one frame, apart from the user's settings.
public struct OverlayContent: Equatable {
    public let scene: KaraokeScene
    public let lines: [LyricLine]
    public let title: String
    public let artist: String?
    public let credits: [String]
    public let notice: String?
    /// An urgent notice (an import or save failure) is drawn in every scene. Other notices show only when idle.
    public let noticeIsUrgent: Bool
    public let usesRedTitle: Bool

    public init(
        scene: KaraokeScene,
        lines: [LyricLine],
        title: String,
        artist: String? = nil,
        credits: [String] = [],
        notice: String? = nil,
        noticeIsUrgent: Bool = false,
        usesRedTitle: Bool = true
    ) {
        self.scene = scene
        self.lines = lines
        self.title = title
        self.artist = artist
        self.credits = credits
        self.notice = notice
        self.noticeIsUrgent = noticeIsUrgent
        self.usesRedTitle = usesRedTitle
    }

    /// Whether drawing would change nothing: an idle scene and no notice. The display link may sleep then.
    public var isQuiet: Bool {
        scene == .idle && (notice ?? "").isEmpty
    }

    /// Nothing to show: an idle scene with no lines.
    public static let empty = OverlayContent(scene: .idle, lines: [], title: "")
}
