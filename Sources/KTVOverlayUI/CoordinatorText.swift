import KTVCore

/// How long a notice stays on screen, and the wording of notices and status lines.
enum CoordinatorText {
    /// Seconds the "looking for lyrics" notice may stay up while a lookup runs.
    static let lookupNoticeSeconds: Double = 8
    /// Seconds the "not found" notice stays up after a lookup finds nothing.
    static let notFoundNoticeSeconds: Double = 6

    /// After this many seconds paused, the overlay goes blank until playback resumes.
    static let pausedHideSeconds: Double = 60

    /// Seconds to wait for a track's duration before looking it up without one.
    static let durationGraceSeconds: Double = 1.5
    /// A duration that moves by more than this many seconds for the same track starts a new lookup.
    static let durationChangeSeconds: Double = 1

    /// Seconds a message about an import or save stays on screen.
    static let userNoticeSeconds: Double = 6

    static let importNeedsSong = "♪ 請先播放歌曲，再匯入 .lrc"
    static let importUnusable = "♪ 匯入失敗：檔案裡沒有帶時間的歌詞，已維持原本的字幕"
    static let saveFailed = "♪ 無法儲存這首歌的設定"

    static let waiting = "等待播放…"
    static let adapterRestarting = "抓歌工具重新啟動中…"
    static let adapterFailed = "偵測不到播放器"

    static func lookupNotice(_ title: String) -> String { "♪ 正在找《\(title)》的字幕" }
    static func notFoundNotice(_ title: String) -> String { "♪ 找不到《\(title)》的字幕" }
    static let unavailableNotice = "♪ 暫時查不到字幕，下次播放會再試一次"
    static func unavailable(_ title: String) -> String { "暫時查不到：\(title)" }
    static func searching(_ title: String) -> String { "查詢中：\(title)" }
    static func notFound(_ title: String) -> String { "找不到字幕：\(title)" }

    static func found(_ title: String, lyrics: Lyrics) -> String {
        "\(title)（\(sourceLabel(lyrics))，\(lyrics.lines.count) 行）"
    }

    private static func sourceLabel(_ lyrics: Lyrics) -> String {
        switch lyrics.source {
        case .lrclib: return "LRCLIB"
        case .imported: return "匯入的 .lrc"
        case .netease: return lyrics.isWordTimed ? "網易雲 · 逐字" : "網易雲"
        }
    }

    /// Hides the cards the user turned off. Other scenes pass through unchanged.
    static func filtered(_ scene: KaraokeScene, by settings: OverlaySettings) -> KaraokeScene {
        switch scene {
        case .title where !settings.showTitleCard: return .idle
        case .countdown where !settings.showCountdown: return .idle
        case .interlude(showBanner: true) where !settings.showBanner: return .interlude(showBanner: false)
        default: return scene
        }
    }
}
