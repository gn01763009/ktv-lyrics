# KTV 字幕層 Mac App 第一版實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出常駐選單列的 Mac app，自動偵測正在播的歌，把 KTV 風格、可點穿的字幕畫在所有 app 上，並可從 GitHub 安裝。

**Architecture:** `KTVCore` 放所有不碰 AppKit 的純邏輯（解析、時間、比對、狀態機、設定），`KTVOverlayUI` 放 AppKit 繪製與系統連線，`KTVLyrics` 只是進入點。外部播放資訊由打包的 mediaremote-adapter 子程序提供，Spotify 與 Apple Music 的時鐘改用 AppleScript 校正。

**Tech Stack:** Swift 6 toolchain（language mode v5）、SwiftPM、AppKit、SwiftUI（僅設定視窗）、Swift Testing。無第三方 Swift 套件。

**Spec:** `docs/superpowers/specs/2026-11-08-ktv-lyrics-overlay-design.md`。`spike/overlay.swift` 是驗證過的參考做法，不沿用。

## Global Constraints

- 支援 macOS 14 以上；Swift + AppKit，常駐選單列、無 Dock 圖示（`LSUIElement`）。
- 字幕視窗：borderless + nonactivating `NSPanel`、透明、`ignoresMouseEvents`、`.screenSaver` level、`.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.stationary`，不能成為 key window。
- 所有時間常數集中在 `LyricsTiming`：間奏門檻 10 秒、4 顆星每顆 0.8 秒、片頭最多 10 秒、逐行提早 0.25 秒、唱速上限 0.7 秒／字、行尾保留 0.12 秒。
- 時鐘：每 1 秒輪詢、偏差超過 0.12 秒才校正。比對：長度 3 秒內，歌手不符或缺歌手時 1 秒內。逐字版本檢查：行首中位數差 1 秒內。
- 掌聲字卡：10 秒以上間奏約五成機率、一首最多兩次，文字固定為 `《來賓請掌聲鼓勵》`。
- 不付費、不公證，只做 ad-hoc 簽章。專案授權 MIT，打包的 mediaremote-adapter 保留 BSD-3 聲明。
- repo 不放歌詞；`spike/`、`.superpowers/` 不進 repo。User-Agent 固定 `ktv-lyrics/0.1`，不帶任何使用者資訊。
- UI 文字一律繁體中文。
- 依提案人全域規則：TDD、`KTVCore` 覆蓋率 80% 以上、不可變資料（更新回傳新值）、函式 50 行內、檔案 400 行左右。所有外部資料在邊界驗證。UI 上靜默的失敗仍要用 `os.Logger` 記錄。
- Commit 用 conventional commits，不加 attribution 行。每個 Commit 步驟都是 `git add -A && git commit -m "<訊息>"`。建立公開 repo 或 push 要等提案人明確要求。

## Review Focus

1. **快速連續切歌**（實測使用者會這樣做）：晚回來的舊查詢不能蓋掉新歌的字幕。測試在 Task 8、Task 13。
2. **播放器被關掉或沒有東西在播**：字幕立刻清空，且絕不用 AppleScript 把沒開的播放器叫起來。測試在 Task 5、Task 13。
3. **抓歌子程序掛掉或起不來**：不當機，退避重啟，♪ 選單顯示狀態。測試在 Task 12。
4. **存的位置在已拔掉的螢幕，或解析度變小**：字幕回到可見範圍。測試在 Task 9。
5. **外部資料壞掉**（LRC 或 JSON 格式錯、時間戳異常、零長度行）：跳過該筆不當機，掃色進度恆在 0 到 1。測試在 Task 1、3、7。

---

### Task 1: 專案骨架與 LRC 解析

**Files:**
- Create: `Package.swift`、`.gitignore`、`LICENSE`、`Sources/KTVCore/Lyrics/LyricsModels.swift`、`Sources/KTVCore/Lyrics/LyricsTiming.swift`、`Sources/KTVCore/Lyrics/LRCParser.swift`、`Sources/KTVOverlayUI/OverlayModule.swift`、`Sources/KTVLyrics/main.swift`
- Test: `Tests/KTVCoreTests/LRCParserTests.swift`、`Tests/KTVCoreTests/Fixtures.swift`、`Tests/KTVOverlayUITests/SmokeTests.swift`

**Interfaces:**
- Produces:
```swift
public struct WordTiming: Equatable, Codable, Sendable { public let text: String; public let start, duration: Double }
public struct LyricLine: Equatable, Codable, Sendable {
    public let start, end, holdEnd: Double; public let text: String
    public let part: String?; public let slot: Int; public let words: [WordTiming]?
    public init(start: Double, end: Double, holdEnd: Double, text: String, part: String? = nil, slot: Int = 1, words: [WordTiming]? = nil)
}
public enum LyricsSource: String, Codable, Sendable { case lrclib, netease, imported }
public struct Lyrics: Equatable, Codable, Sendable { public let source: LyricsSource; public let lines: [LyricLine]; public let credits: [String]; public var isWordTimed: Bool { get } }
public struct LRCStamp: Equatable, Sendable { public let time: Double; public let text: String }
public struct ParsedLRC: Equatable, Sendable { public let stamps: [LRCStamp]; public let credits: [String] }
public enum LRCParser { public static func parse(_ raw: String) -> ParsedLRC }
```

- [ ] **Step 1: 建立 repo 與套件骨架**

`git init -b main`、`git commit --allow-empty -m "chore: initial commit"`、`git switch -c feat/v1`。`Package.swift`：tools 6.0、`.macOS(.v14)`、package 名 `KTVLyrics`、targets `KTVCore`、`KTVOverlayUI`（依賴 Core）、executable `KTVLyrics`、兩個 test target，全部 `.swiftLanguageMode(.v5)`。`.gitignore` 含 `.build/`、`build/`、`spike/`、`.superpowers/`。`LICENSE` 為 MIT。`LyricsTiming` 常數見 Global Constraints，另加 `trailingHold = 3`、`fallbackSecondsPerChar = 0.45`、`lineGapMargin = 0.12`、`countdownSeconds = 3.2`。

- [ ] **Step 2: 寫失敗的測試**

```swift
@Test func multipleTagsOnOneLine() { #expect(LRCParser.parse("[00:20.00][00:10.50]副歌").stamps == [LRCStamp(time: 10.5, text: "副歌"), LRCStamp(time: 20, text: "副歌")]) }
@Test func keepsBlankTagAsLineEnd() { #expect(LRCParser.parse("[00:10.00]一句\n[00:15.00]").stamps.last == LRCStamp(time: 15, text: "")) }
@Test func movesCreditsOutOfBody() {
    let p = LRCParser.parse("[00:00.00]作词 : 方文山\n[00:01.00]作曲 : 周杰倫\n[00:02.00]製作人 : 某人\n[00:10.00]第一句")
    #expect(p.credits == ["作詞：方文山", "作曲：周杰倫"]); #expect(p.stamps.map(\.text) == ["第一句"])
}
@Test func headerRuleStopsAfterFourteenRows() { let raw = (0..<15).map { "[00:\(10 + $0).00]第\($0)句" }.joined(separator: "\n") + "\n[00:40.00]他說：你好"; #expect(LRCParser.parse(raw).stamps.last?.text == "他說：你好") }
@Test func keepsPartLabels() { #expect(LRCParser.parse("[00:10.00]男：第一句").stamps.first?.text == "男：第一句") }
@Test func skipsMalformedRows() { #expect(LRCParser.parse("[aa:bb]x\n[99:99.99]y\n沒有時間\n{\"t\":0}\n[00:05.00]好").stamps == [LRCStamp(time: 5, text: "好")]) }
```

- [ ] **Step 3: 確認失敗** — Run: `swift test --filter LRCParserTests`。Expected: FAIL，`cannot find 'LRCParser' in scope`。
- [ ] **Step 4: 實作 `LRCParser.parse`** — 秒數必須小於 60，否則整列略過。標頭判斷沿用 spike 的 `^[^:：]{1,10}\s*[:：]`，只看前 14 列，`男`、`女`、`合` 開頭不算標頭。
- [ ] **Step 5: 確認通過** — Run: `swift test`。Expected: PASS，含 `KTVOverlayUITests` 的 smoke test。
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: scaffold package and parse LRC"`

### Task 2: 逐行時間、唱速與上下排

**Files:** Create `Sources/KTVCore/Lyrics/LyricsBuilder.swift`；Test `Tests/KTVCoreTests/LyricsBuilderTests.swift`

**Interfaces:**
- Consumes: `ParsedLRC`、`LyricLine`、`LyricsTiming`
- Produces:
```swift
public enum LyricsBuilder {
    public static func sungCount(_ text: String) -> Int            // 只算字母與數字，最少 1
    public static func songRate(stamps: [LRCStamp]) -> Double
    public static func lines(from parsed: ParsedLRC) -> [LyricLine]
    public static func assigningSlots(_ lines: [LyricLine]) -> [LyricLine]
}
```

- [ ] **Step 1: 寫失敗的測試**

```swift
// Fixtures.swift：stamps(gaps:chars:) 依序建立等字數的行並補一個空白結束標記，parsed(gaps:chars:) 包成 ParsedLRC
@Test func rateIsLowerQuartile() { #expect(LyricsBuilder.songRate(stamps: stamps(gaps: [1.6, 1.6, 2, 2, 2.4, 2.4, 2.8, 2.8], chars: 4)) == 0.5) }
@Test func rateIsCapped() { #expect(LyricsBuilder.songRate(stamps: stamps(gaps: [20, 20, 20, 20], chars: 4)) == 0.7) }
@Test func rateFallsBackWithoutGaps() { #expect(LyricsBuilder.songRate(stamps: []) == 0.45) }
@Test func countsOnlySungCharacters() { #expect(LyricsBuilder.sungCount("你好, world!") == 7) }
@Test func endUsesRateNotGap() { let l = LyricsBuilder.lines(from: parsed(gaps: [8, 4, 4, 4], chars: 10))[0]; #expect(abs((l.end - l.start) - 4.0) < 0.001) }  // 唱速 0.4 × 10 字，不是行距 8 秒
@Test func endNeverPassesNextLine() { let ls = LyricsBuilder.lines(from: parsed(gaps: [2, 9, 9, 9], chars: 10)); #expect(ls[0].end <= ls[1].start - 0.12 + 0.0001) }
@Test func blankTagEndsLine() { let ls = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00]一二三四\n[00:11.00]\n[00:30.00]五六七八")); #expect(abs(ls[0].holdEnd - 10.88) < 0.001) }
@Test func slotsAlternateAndRestartAfterInterlude() {
    let ls = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00]一\n[00:13.00]二\n[00:16.00]三\n[00:40.00]四\n[00:43.00]五"))
    #expect(ls.map(\.slot) == [1, 0, 1, 1, 0])
}
@Test func stripsPartLabel() { let l = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00]男：第一句\n[00:13.00]下一句"))[0]; #expect(l.text == "第一句" && l.part == "男：") }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter LyricsBuilderTests`。Expected: FAIL，`cannot find 'LyricsBuilder'`。
- [ ] **Step 3: 實作** — `end = start + max(0.4, min(下一標記距離 − 0.12, 字數 × 唱速))`；`holdEnd = start + max(0.4, min(下一標記距離 − 0.12, max(8, 字數 × 0.8)))`。下一行 `start − 本行 holdEnd ≥ 10` 視為段落中斷，段落第一行 slot 為 1，之後交替。最後一行的下一標記距離用 6 秒。
- [ ] **Step 4: 確認通過** — Run: `swift test --filter LyricsBuilderTests`。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: estimate line timing from song pace`

### Task 3: 逐字歌詞與掃色進度

**Files:** Create `Sources/KTVCore/Lyrics/YRCParser.swift`、`Sources/KTVCore/Lyrics/Sweep.swift`、`Sources/KTVCore/Lyrics/TextConversion.swift`；Test `Tests/KTVCoreTests/YRCParserTests.swift`、`SweepTests.swift`

**Interfaces:**
- Consumes: `LyricLine`、`WordTiming`、`LyricsBuilder.assigningSlots`
- Produces:
```swift
public enum TextConversion { public static func toTraditional(_ text: String) -> String }  // ICU "Simplified-Traditional"
public struct ParsedYRC: Equatable, Sendable { public let lines: [LyricLine]; public let credits: [String] }
public enum YRCParser {
    public static func parse(_ raw: String, convert: (String) -> String = { $0 }) -> ParsedYRC
    public static func headerCredits(_ raw: String) -> [String]     // 也用於網易雲 lrc 欄位開頭的 JSON 列
}
public enum Sweep: Equatable, Sendable { case linear(Double); case word(index: Int, progress: Double) }
public extension LyricLine { func sweep(at time: Double) -> Sweep }
```

- [ ] **Step 1: 寫失敗的測試**

```swift
let sample = "[16210,3460](16210,670,0)还(16880,410,0)没"
@Test func parsesWordTimes() {
    let l = YRCParser.parse(sample).lines[0]
    #expect(l.start == 16.21 && l.text == "还没"); #expect(l.words?[1] == WordTiming(text: "没", start: 16.88, duration: 0.41)); #expect(abs(l.end - 17.29) < 0.001 && l.holdEnd == l.end)
}
@Test func convertsPerTokenKeepingTimes() { #expect(YRCParser.parse(sample, convert: TextConversion.toTraditional).lines[0].words?[0] == WordTiming(text: "還", start: 16.21, duration: 0.67)) }
@Test func readsCreditsFromJSONRows() {
    let raw = "{\"t\":0,\"c\":[{\"tx\":\"作词: \"},{\"tx\":\"五月天 阿信\"}]}\n{\"t\":5598,\"c\":[{\"tx\":\"管弦乐团: \"},{\"tx\":\"某人\"}]}\n" + sample
    #expect(YRCParser.parse(raw).credits == ["作詞：五月天 阿信"])
}
@Test func skipsMalformedRows() { #expect(YRCParser.parse("[bad](1,2,0)x\n{not json\n" + sample).lines.count == 1) }
@Test func linearIsClamped() { let l = LyricLine(start: 10, end: 14, holdEnd: 14, text: "一"); #expect(l.sweep(at: 12) == .linear(0.5) && l.sweep(at: 9) == .linear(0) && l.sweep(at: 99) == .linear(1)) }
@Test func zeroLengthLineIsDone() { #expect(LyricLine(start: 10, end: 10, holdEnd: 10, text: "一").sweep(at: 10) == .linear(1)) }
@Test func wordSweep() {
    let l = YRCParser.parse("[1000,3000](1000,1000,0)一(2000,2000,0)二").lines[0]
    #expect(l.sweep(at: 0.5) == .word(index: 0, progress: 0)); #expect(l.sweep(at: 3) == .word(index: 1, progress: 0.5)); #expect(l.sweep(at: 5) == .word(index: 1, progress: 1))
}
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter "YRCParserTests|SweepTests"`。Expected: FAIL，型別不存在。
- [ ] **Step 3: 實作** — 列格式 `[行ms,長ms](字ms,長ms,0)字`，字開始時間是絕對值。兩個字之間的空檔回傳 `.word(index: 下一字, progress: 0)`。最後呼叫 `assigningSlots`。
- [ ] **Step 4: 確認通過** — 同 Step 2 指令。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: parse word timing and compute sweep`

### Task 4: 畫面狀態機與掌聲字卡

**Files:** Create `Sources/KTVCore/Scene/SceneEngine.swift`、`Sources/KTVCore/Scene/BannerPlanner.swift`；Test `Tests/KTVCoreTests/SceneEngineTests.swift`、`BannerPlannerTests.swift`

**Interfaces:**
- Consumes: `LyricLine`、`Sweep`、`LyricsTiming`
- Produces:
```swift
public enum KaraokeScene: Equatable, Sendable { case idle, title; case countdown(upcoming: Int, stars: Int); case singing(index: Int, sweep: Sweep); case held(index: Int); case interlude(showBanner: Bool) }
public enum StableHash { public static func fnv1a(_ text: String) -> UInt64 }
public enum BannerPlanner { public static func plan(lines: [LyricLine], seed: UInt64) -> Set<Int> }  // 值為間奏「前一行」的 index
public struct SceneEngine: Sendable { public init(lines: [LyricLine], bannerAfter: Set<Int>); public func scene(at position: Double) -> KaraokeScene }
```

- [ ] **Step 1: 寫失敗的測試**

```swift
// song：第一句 20 秒開始，兩句相連，之後 15 秒空檔再接第三句
let song = [LyricLine(start: 20, end: 23, holdEnd: 23, text: "一"), LyricLine(start: 24, end: 27, holdEnd: 27, text: "二"), LyricLine(start: 42, end: 45, holdEnd: 45, text: "三")]
let engine = SceneEngine(lines: song, bannerAfter: [1])
@Test func titleOnlyInFirstTenSeconds() { #expect(engine.scene(at: 5) == .title && engine.scene(at: 12) == .idle) }
@Test func starsCountDown() { #expect(engine.scene(at: 16.8) == .countdown(upcoming: 0, stars: 4)); #expect(engine.scene(at: 19.5) == .countdown(upcoming: 0, stars: 1)) }
@Test func singingThenHeld() { #expect(engine.scene(at: 21.5) == .singing(index: 0, sweep: .linear(0.5))); #expect(engine.scene(at: 23.5) == .held(index: 0)) }
@Test func interludeWithBannerThenStars() { #expect(engine.scene(at: 30) == .interlude(showBanner: true)); #expect(engine.scene(at: 39) == .countdown(upcoming: 2, stars: 4)) }
@Test func interludeWithoutBanner() { #expect(SceneEngine(lines: song, bannerAfter: []).scene(at: 30) == .interlude(showBanner: false)) }
@Test func endsThreeSecondsAfterLastLine() { #expect(engine.scene(at: 47) == .held(index: 2) && engine.scene(at: 48.1) == .idle) }
@Test func noLinesIsIdle() { #expect(SceneEngine(lines: [], bannerAfter: []).scene(at: 5) == .idle) }
@Test func firstLineAtStartSkipsTitle() { let e = SceneEngine(lines: [LyricLine(start: 0.33, end: 2, holdEnd: 2, text: "一")], bannerAfter: []); #expect(e.scene(at: 0.1) == .countdown(upcoming: 0, stars: 1)) }
// BannerPlanner：gapped(n) 建立 n 段間隔 12 秒的間奏
@Test func shortGapIsNotEligible() { #expect(BannerPlanner.plan(lines: [LyricLine(start: 0, end: 1, holdEnd: 1, text: "一"), LyricLine(start: 10.9, end: 12, holdEnd: 12, text: "二")], seed: 1).isEmpty) }
@Test func atMostTwoPerSong() { for seed in 0..<200 { #expect(BannerPlanner.plan(lines: gapped(10), seed: UInt64(seed)).count <= 2) } }
@Test func sameSeedSamePlan() { #expect(BannerPlanner.plan(lines: gapped(6), seed: 7) == BannerPlanner.plan(lines: gapped(6), seed: 7)) }
@Test func aboutHalfOfEligibleGaps() { let hits = (0..<1000).filter { !BannerPlanner.plan(lines: gapped(1), seed: StableHash.fnv1a("s\($0)")).isEmpty }.count; #expect((400...600).contains(hits)) }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter "SceneEngineTests|BannerPlannerTests"`。Expected: FAIL。
- [ ] **Step 3: 實作** — 邏輯依 `spike/overlay.swift` 的 `scene(at:lines:)`，間奏判斷用 `next.start - line.holdEnd >= 10`。亂數用 seed 推導的 SplitMix64，確保同一首歌每次一致。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: add scene engine and interlude banner plan`

### Task 5: 播放資訊與時鐘校正

**Files:** Create `Sources/KTVCore/Playback/PlaybackSnapshot.swift`、`AdapterMessage.swift`、`PositionResolver.swift`、`ScriptablePlayer.swift`；Test `Tests/KTVCoreTests/PlaybackTests.swift`

**Interfaces:**
- Produces:
```swift
public struct PlaybackSnapshot: Equatable, Sendable {
    public let title: String; public let artist: String?; public let duration: Double
    public let elapsed, timestamp: Double?; public let rate: Double; public let isPlaying: Bool; public let bundleID: String
    public var trackKey: String { get }                          // "\(title)|\(artist ?? "")"
    public func position(now: Double) -> Double?
    public func merging(previous: PlaybackSnapshot?) -> PlaybackSnapshot   // 同一首歌缺 elapsed 時沿用前值
}
public enum AdapterEvent: Equatable, Sendable { case playing(PlaybackSnapshot), nothing, ignored }
public enum AdapterMessage { public static func parse(_ line: Data) -> AdapterEvent }
public struct PlayerSample: Equatable, Sendable { public let position: Double; public let isPlaying: Bool; public let at: Double }
public struct PositionResolver: Equatable, Sendable {
    public static let snapThreshold = 0.12
    public init()
    public func position(snapshot: PlaybackSnapshot, now: Double) -> Double?
    public func applying(_ sample: PlayerSample, snapshot: PlaybackSnapshot) -> PositionResolver
}
public enum ScriptablePlayer: String, Sendable { case spotify = "Spotify", music = "Music"
    public static func toPoll(bundleID: String, running: Set<String>) -> ScriptablePlayer? }
```

- [ ] **Step 1: 寫失敗的測試**

```swift
let json = #"{"type":"data","diff":false,"payload":{"title":"簡單愛","artist":"周杰倫","durationMicros":270987000,"elapsedTimeMicros":100005000,"timestampEpochMicros":1000000000000,"playbackRate":1,"playing":true,"bundleIdentifier":"com.spotify.client"}}"#
@Test func parsesAdapterRow() { guard case .playing(let s) = AdapterMessage.parse(Data(json.utf8)) else { Issue.record("not playing"); return }; #expect(s.title == "簡單愛" && s.duration == 270.987 && abs(s.position(now: 1000002)! - 102.005) < 0.001) }
@Test func emptyPayloadIsNothing() { #expect(AdapterMessage.parse(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)) == .nothing) }
@Test func garbageIsIgnored() { #expect(AdapterMessage.parse(Data("oops".utf8)) == .ignored) }
@Test func pauseGlitchKeepsPosition() { /* 同曲新快照 elapsed 為 nil，merging 後保留前值的 elapsed 與 timestamp */ }
@Test func smallDriftIsKept() { /* 先校正到 10.00，再送預測值 +0.10 的樣本：reading 不變 */ }
@Test func driftOverThresholdSnaps() { /* 同上，+0.13：position 等於新樣本 */ }
@Test func playStateChangeSnaps() { /* 偏差 0，但 isPlaying 改變：採用新樣本 */ }
@Test func readingForOtherTrackIsIgnored() { /* trackKey 不同時，position 用 snapshot 的值 */ }
@Test func pollsOnlyRunningScriptablePlayers() {
    #expect(ScriptablePlayer.toPoll(bundleID: "com.spotify.client", running: ["com.spotify.client"]) == .spotify)
    #expect(ScriptablePlayer.toPoll(bundleID: "com.spotify.client", running: []) == nil)
    #expect(ScriptablePlayer.toPoll(bundleID: "com.apple.Music", running: ["com.apple.Music"]) == .music)
    #expect(ScriptablePlayer.toPoll(bundleID: "com.google.Chrome", running: ["com.google.Chrome"]) == nil)
}
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter PlaybackTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — 註解中的測試要寫成實際斷言，數值如註解。時間一律換算成秒。沒有 `title` 或 `payload` 為空都算 `.nothing`。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: model playback and correct the clock from players`

### Task 6: 歌名清理與比對

**Files:** Create `Sources/KTVCore/Matching/TitleNormalizer.swift`、`YouTubeTitleParser.swift`、`TrackMatcher.swift`；Test `Tests/KTVCoreTests/MatchingTests.swift`

**Interfaces:**
- Consumes: `PlaybackSnapshot`、`TextConversion`
- Produces:
```swift
public struct TrackQuery: Equatable, Codable, Sendable { public let title: String; public let artist: String?; public let duration: Double }
public enum TitleNormalizer {
    public static func clean(_ title: String) -> String
    public static func matchKey(_ text: String) -> String
    public static func artistKey(_ artist: String) -> String    // 只取第一位歌手
    public static func query(from snapshot: PlaybackSnapshot) -> TrackQuery  // 瀏覽器來源走 YouTubeTitleParser
}
public enum BrowserApps { public static func contains(_ bundleID: String) -> Bool }
public enum YouTubeTitleParser { public static func parse(title: String, channel: String?) -> (title: String, artist: String?) }
public struct MatchCandidate: Equatable, Sendable { public let title: String; public let artist: String?; public let duration: Double }
public enum TrackMatcher {
    public static func accepts(_ candidate: MatchCandidate, for query: TrackQuery) -> Bool
    public static func best<T>(_ items: [T], for query: TrackQuery, candidate: (T) -> MatchCandidate) -> T?
}
```

- [ ] **Step 1: 寫失敗的測試**

```swift
let q = TrackQuery(title: "溫柔", artist: "五月天", duration: 270)
func c(_ d: Double, title: String = "温柔", artist: String? = "五月天") -> MatchCandidate { MatchCandidate(title: title, artist: artist, duration: d) }
@Test func cleansSubtitles() { #expect(TitleNormalizer.clean("想見你想見你想見你 - 電視劇《想見你》片尾曲") == "想見你想見你想見你"); #expect(TitleNormalizer.clean("Bohemian Rhapsody (Remastered 2011)") == "Bohemian Rhapsody") }
@Test func matchKeyUnifiesScripts() { #expect(TitleNormalizer.matchKey("温柔") == TitleNormalizer.matchKey("溫 柔")) }
@Test func durationWindowWithSameArtist() { #expect(TrackMatcher.accepts(c(272.9), for: q)); #expect(!TrackMatcher.accepts(c(273.1), for: q)) }
@Test func stricterWhenArtistDiffers() { #expect(TrackMatcher.accepts(c(270.9, artist: "Mayday"), for: q)); #expect(!TrackMatcher.accepts(c(271.1, artist: "Mayday"), for: q)) }
@Test func stricterWithoutArtist() { let n = TrackQuery(title: "溫柔", artist: nil, duration: 270); #expect(TrackMatcher.accepts(c(270.9), for: n)); #expect(!TrackMatcher.accepts(c(271.1), for: n)) }
@Test func artistContainmentCounts() { #expect(TrackMatcher.accepts(c(272, artist: "五月天 Mayday"), for: q)) }
@Test func rejectsOtherTitle() { #expect(!TrackMatcher.accepts(c(270, title: "倔強"), for: q)) }
@Test func rejectsTheVersionSeenInSpike() { #expect(!TrackMatcher.accepts(c(204.8, title: "我多想擁抱你", artist: "黑屋乐队"), for: TrackQuery(title: "我多想擁抱你", artist: "黑屋乐队", duration: 193))) }
@Test func picksClosestDuration() { #expect(TrackMatcher.best([c(272.5), c(270.5)], for: q) { $0 }?.duration == 270.5) }
@Test func youtubeBracketTitle() { let r = YouTubeTitleParser.parse(title: "周杰倫 Jay Chou【告白氣球 Love Confession】Official MV", channel: "周杰倫 Jay Chou"); #expect(r.title == "告白氣球" && r.artist == "周杰倫 Jay Chou") }
@Test func youtubeDashTitle() { let r = YouTubeTitleParser.parse(title: "五月天 Mayday - 溫柔 (Official Music Video)", channel: nil); #expect(r.title == "溫柔" && r.artist == "五月天 Mayday") }
@Test func youtubeTopicChannel() { let r = YouTubeTitleParser.parse(title: "溫柔", channel: "五月天 - Topic"); #expect(r.title == "溫柔" && r.artist == "五月天") }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter MatchingTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — `clean` 切掉 ` - `、`（`、`(`、`【`、`[`、` feat` 之後的內容。`matchKey` 轉繁、小寫、去空白與標點。`【】` 或 `《》` 內有字時優先當歌名，並取其中第一段中文或第一段文字。`BrowserApps`：Chrome、Safari、Arc、Edge、Brave、Firefox。候選歌名也要先 `clean` 再比對。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: clean titles and match lyrics candidates`

### Task 7: 歌詞來源與選用順序

**Files:** Create `Sources/KTVCore/Providers/HTTPFetching.swift`、`LRCLIBClient.swift`、`NetEaseClient.swift`、`WordTimingValidator.swift`、`LyricsResolver.swift`；Test `Tests/KTVCoreTests/LyricsResolverTests.swift`、`Tests/KTVCoreTests/FakeHTTP.swift`

**Interfaces:**
- Consumes: `TrackQuery`、`TrackMatcher`、`LRCParser`、`YRCParser`、`LyricsBuilder`、`TextConversion`
- Produces:
```swift
public protocol HTTPFetching: Sendable { func data(from url: URL) async throws -> Data }
public struct URLSessionFetcher: HTTPFetching { public init() }  // timeout 12 秒、UA ktv-lyrics/0.1
public struct LRCLIBHit: Equatable, Sendable { public let title: String; public let artist: String?; public let duration: Double; public let syncedLyrics: String }
public struct LRCLIBClient: Sendable { public init(http: any HTTPFetching); public func search(_ query: TrackQuery) async throws -> [LRCLIBHit] }
public struct NetEaseSong: Equatable, Sendable { public let id: Int; public let title: String; public let artist: String?; public let duration: Double }
public struct NetEaseLyrics: Equatable, Sendable { public let lrc: String?; public let yrc: String? }
public struct NetEaseClient: Sendable { public init(http: any HTTPFetching); public func search(_ query: TrackQuery) async throws -> [NetEaseSong]; public func lyrics(id: Int) async throws -> NetEaseLyrics }
public enum WordTimingValidator { public static func isSameVersion(words: [LyricLine], lines: [LyricLine]) -> Bool }
public enum LyricsOutcome: Equatable, Codable, Sendable { case found(Lyrics), notFound; public var lyrics: Lyrics? { get } }
public struct LyricsCandidate: Equatable, Sendable { public let id: String; public let label: String; public let lyrics: Lyrics }
public protocol LyricsResolving: Sendable { func resolve(_ query: TrackQuery) async -> LyricsOutcome; func candidates(_ query: TrackQuery) async -> [LyricsCandidate] }
public struct LyricsResolver: LyricsResolving { public init(lrclib: LRCLIBClient, netease: NetEaseClient?) }
```

- [ ] **Step 1: 寫失敗的測試**

用 `FakeHTTP(routes: [String: Result<Data, Error>])` 依網址子字串回應，並記錄查過的 host。Fixture 提供 `lrclibJSON(lines:)`、`neteaseSearchJSON()`、`neteaseLyricJSON(yrc:offset:)`，offset 用來平移逐字時間。`resolver(lrclib:netease:)` 依情境組出 resolver：LRCLIB 情境 `.standard`（預設）、`.empty`、`.otherSong`、`.garbage`；網易雲情境 `.wordTimed(offset:)`、`.noYRC`、`.failing`、`.otherSong`、`.garbage`。`q` 是溫柔／五月天／270 秒，`lines(at:)` 依開始時間建立 `LyricLine`。

```swift
@Test func wordTimedWins() async { let o = await resolver(netease: .wordTimed(offset: 0)).resolve(q); #expect(o.lyrics?.source == .netease && o.lyrics?.isWordTimed == true && o.lyrics?.credits == ["作詞：五月天 阿信"]) }
@Test func versionMismatchFallsBackToLines() async { let o = await resolver(netease: .wordTimed(offset: 2)).resolve(q); #expect(o.lyrics?.source == .lrclib && o.lyrics?.isWordTimed == false && o.lyrics?.credits == ["作詞：五月天 阿信"]) }
@Test func lrclibLinesWhenNoWordTiming() async { #expect(await resolver(netease: .noYRC).resolve(q).lyrics?.source == .lrclib) }
@Test func neteaseLinesWhenLrclibMisses() async { let o = await resolver(lrclib: .empty, netease: .noYRC).resolve(q); #expect(o.lyrics?.source == .netease && o.lyrics?.isWordTimed == false) }
@Test func disabledNeteaseIsNeverCalled() async { let h = FakeHTTP.standard; _ = await LyricsResolver(lrclib: LRCLIBClient(http: h), netease: nil).resolve(q); #expect(!h.hosts.contains("music.163.com")) }
@Test func neteaseFailureFallsBack() async { #expect(await resolver(netease: .failing).resolve(q).lyrics?.source == .lrclib) }
@Test func nothingMatchesIsNotFound() async { #expect(await resolver(lrclib: .otherSong, netease: .otherSong).resolve(q) == .notFound) }
@Test func malformedResponsesAreNotFound() async { #expect(await resolver(lrclib: .garbage, netease: .garbage).resolve(q) == .notFound) }
@Test func validatorComparesMedianLineStart() { #expect(WordTimingValidator.isSameVersion(words: lines(at: [10, 20, 30]), lines: lines(at: [10.9, 20.9, 30.9]))); #expect(!WordTimingValidator.isSameVersion(words: lines(at: [10, 20, 30]), lines: lines(at: [11.1, 21.1, 31.1]))) }
@Test func validatorPassesWithTooFewLines() { #expect(WordTimingValidator.isSameVersion(words: lines(at: [10]), lines: lines(at: [90]))) }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter LyricsResolverTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — LRCLIB：`https://lrclib.net/api/search`，依序用 `track_name` + `artist_name`、`q=歌名 歌手`、`q=歌名`。網易雲：`https://music.163.com/api/search/get?s=&type=1&limit=8`（欄位 `id`、`name`、`artists[0].name`、`duration` 毫秒），歌詞用 spec 記錄的 `lyric/v1` 網址，取 `lrc.lyric`、`yrc.lyric`。選用順序與版本檢查依 spec §5。網易雲文字一律經 `TextConversion.toTraditional`。`candidates` 回傳所有通過比對的版本，label 例如 `LRCLIB · 整行` 或 `網易雲 · 逐字`。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: resolve lyrics from LRCLIB and NetEase`

### Task 8: 快取、單曲設定與查詢閘門

**Files:** Create `Sources/KTVCore/Storage/LyricsCache.swift`、`SongOverrideStore.swift`、`LookupGate.swift`；Test `Tests/KTVCoreTests/StorageTests.swift`

**Interfaces:**
- Consumes: `TrackQuery`、`LyricsOutcome`、`TitleNormalizer`
- Produces:
```swift
public struct LyricsCache: Sendable { public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init)
    public func load(_ query: TrackQuery) -> LyricsOutcome?; public func save(_ outcome: LyricsOutcome, for query: TrackQuery) throws }
public struct SongOverride: Equatable, Codable, Sendable { public let offset: Double; public let importedLRC: String?; public let candidateID: String?; public static let none: SongOverride }
public struct SongOverrideStore: Sendable { public init(directory: URL); public func load(_ query: TrackQuery) -> SongOverride; public func save(_ override: SongOverride, for query: TrackQuery) throws }
public struct LookupGate: Equatable, Sendable { public init(); public let currentID: Int; public func next() -> LookupGate; public func accepts(_ id: Int) -> Bool }
```

- [ ] **Step 1: 寫失敗的測試**

```swift
@Test func foundIsCachedForever() throws { /* save(.found)，時鐘 +365 天，load 仍為 .found */ }
@Test func notFoundExpiresAfterADay() throws { /* save(.notFound)，+23 小時回 .notFound；+25 小時回 nil */ }
@Test func keyIgnoresScriptAndRoundsDuration() throws { /* 用「溫柔 / 270.2」存，用「温柔 / 269.8」讀得到 */ }
@Test func corruptFileReadsAsMissing() throws { /* 把快取檔內容改成亂碼，load 回 nil 且不丟錯 */ }
@Test func overrideDefaultsToNone() { /* 沒存過回 .none */ }
@Test func overrideRoundTrips() throws { /* offset 0.3、candidateID "x" 存讀一致 */ }
@Test func staleLookupIsIgnored() { let first = LookupGate().next(); let second = first.next(); #expect(!second.accepts(first.currentID)); #expect(second.accepts(second.currentID)) }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter StorageTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — 註解內容寫成實際斷言。檔名是 `matchKey(title)|artistKey|Int(duration.rounded())` 的 SHA-256（CryptoKit）。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: cache lyrics and per-song overrides`

### Task 9: 設定模型、樣式與位置

**Files:** Create `Sources/KTVCore/Settings/OverlaySettings.swift`、`StylePreset.swift`、`SettingsStore.swift`、`PanelPlacement.swift`；Test `Tests/KTVCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
```swift
public struct RGBAColor: Equatable, Codable, Sendable { public let r, g, b, a: Double; public init(hex: UInt32, alpha: Double = 1) }
public struct OverlayStyle: Equatable, Codable, Sendable { public let unsungFill, unsungStroke, sungFill, sungStroke: RGBAColor; public let strokeWidth: Double; public let fontName: String; public let scale: Double; public let singleLine: Bool }
public enum StylePreset: String, CaseIterable, Codable, Sendable { case classic, neon, quiet, gold; public var style: OverlayStyle { get } }
public struct NormalizedPoint: Equatable, Codable, Sendable { public let x, y: Double }
public struct OverlaySettings: Equatable, Codable, Sendable { public var size, opacity: Double; public var preset: StylePreset; public var style: OverlayStyle; public var showTitleCard, showCountdown, showBanner, useNetEase, launchAtLogin: Bool; public var anchor: NormalizedPoint; public var displayID: String?; public static let defaults: OverlaySettings; public func with<V>(_ path: WritableKeyPath<OverlaySettings, V>, _ value: V) -> OverlaySettings }
public protocol SettingsStoring: Sendable { func load() -> OverlaySettings; func save(_ settings: OverlaySettings) }
public struct UserDefaultsSettingsStore: SettingsStoring { public init(defaults: UserDefaults = .standard) }
public struct ScreenInfo: Equatable, Sendable { public let id: String; public let frame, visibleFrame: CGRect }
public enum PanelPlacement {
    public static func frame(settings: OverlaySettings, contentSize: CGSize, screens: [ScreenInfo]) -> CGRect
    public static func anchor(for frame: CGRect, on screen: ScreenInfo) -> NormalizedPoint
}
```

- [ ] **Step 1: 寫失敗的測試**

樣式色值：classic 未唱 `#FFFFFF`／描邊 `#000000`、已唱 `#1746E0`／描邊 `#FFFFFF`；neon 描邊 `#3B1060`、已唱 `#FF5FD2`；quiet 描邊 `#000000` alpha 0.72、已唱 `#FFCF5A`、scale 0.72、`singleLine`；gold 未唱 `#FFF8E6`、描邊 `#4D2500`、已唱 `#FFB516`、字體 Kaiti TC。描邊預設 20（字級百分比）。預設 size 46、opacity 1、anchor (0.5, 0.05)。

```swift
@Test func defaultsAreClassic() { #expect(OverlaySettings.defaults.preset == .classic && OverlaySettings.defaults.size == 46 && OverlaySettings.defaults.useNetEase) }
@Test func presetColors() { #expect(StylePreset.classic.style.sungFill == RGBAColor(hex: 0x1746E0)); #expect(StylePreset.quiet.style.singleLine && StylePreset.quiet.style.scale == 0.72) }
@Test func roundTrips() { /* 改 size 60 後 save，再 load 相等 */ }
@Test func corruptDataFallsBackToDefaults() { /* UserDefaults 存亂碼，load == .defaults */ }
@Test func missingKeysUseDefaults() { /* 只有 {"size":60} 的 JSON：size 60，其餘是預設值 */ }
let main = ScreenInfo(id: "A", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 830))
@Test func placesOnSavedDisplay() { /* 兩個螢幕，displayID "B"：frame 落在 B 內 */ }
@Test func missingDisplayFallsBackToFirst() { /* displayID "gone"：frame 落在 main.visibleFrame 內 */ }
@Test func clampsToVisibleArea() { /* anchor (1, 1)、contentSize 1000×320：frame 完全在 visibleFrame 內 */ }
@Test func anchorRoundTrips() { /* frame -> anchor -> frame 差距小於 1 點 */ }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter SettingsTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — 註解內容寫成實際斷言。`OverlaySettings` 用 `decodeIfPresent` 讓新舊版本相容。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: add settings, style presets and placement`

### Task 10: 繪製字幕

**Files:** Create `Sources/KTVOverlayUI/OverlayContent.swift`、`KaraokeRenderer.swift`、`OverlayView.swift`；Test `Tests/KTVOverlayUITests/RenderingTests.swift`

**Interfaces:**
- Consumes: `KaraokeScene`、`Sweep`、`LyricLine`、`OverlaySettings`、`OverlayStyle`
- Produces:
```swift
public struct OverlayContent: Equatable { public let scene: KaraokeScene; public let lines: [LyricLine]; public let title: String; public let artist: String?; public let credits: [String]; public let notice: String?; public let usesRedTitle: Bool; public static let empty: OverlayContent }
public enum TextFitter { public static func fontSize(for text: String, fontName: String, preferred: CGFloat, maxWidth: CGFloat) -> CGFloat }
public final class OverlayView: NSView { public var content: OverlayContent; public var settings: OverlaySettings; public func snapshot() -> NSBitmapImageRep }
```

- [ ] **Step 1: 寫失敗的測試**

`snapshot()` 用 `cacheDisplay` 輸出點陣圖。測試檔的 `render(_:line:words:)` 回傳 `RenderedImage`，提供 `maxAlpha`、`count(of:in:)`、`touchesLeftOrRightEdge`。

```swift
@Test @MainActor func idleIsFullyTransparent() { #expect(render(.idle).maxAlpha == 0) }
@Test @MainActor func lineSweepPaintsOnlyTheLeft() { let img = render(.singing(index: 0, sweep: .linear(0.5))); #expect(img.count(of: sungBlue, in: .leftHalfOfLine) > 0 && img.count(of: sungBlue, in: .rightHalfOfLine) == 0) }
@Test @MainActor func wordSweepStopsAtTheWord() { let img = render(.singing(index: 0, sweep: .word(index: 1, progress: 0)), words: ["一", "二"]); #expect(img.count(of: sungBlue, in: .leftHalfOfLine) > 0 && img.count(of: sungBlue, in: .rightHalfOfLine) == 0) }
@Test @MainActor func bannerDraws() { #expect(render(.interlude(showBanner: true)).maxAlpha > 0) }
@Test @MainActor func silentInterludeIsEmpty() { #expect(render(.interlude(showBanner: false)).maxAlpha == 0) }
@Test @MainActor func titleCardDraws() { #expect(render(.title).maxAlpha > 0) }
@Test @MainActor func longLineStaysInBounds() { #expect(render(.singing(index: 0, sweep: .linear(1)), line: String(repeating: "長", count: 80)).touchesLeftOrRightEdge == false) }
@Test func fitterShrinksOnlyWhenNeeded() { #expect(TextFitter.fontSize(for: "短", fontName: "PingFangTC-Semibold", preferred: 46, maxWidth: 1000) == 46); #expect(TextFitter.fontSize(for: String(repeating: "長", count: 80), fontName: "PingFangTC-Semibold", preferred: 46, maxWidth: 1000) < 46) }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter RenderingTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — 依 `spike/overlay.swift` 的 `drawOutlined`：先畫 rim（描邊寬 +4、黑 85%，只用在白描邊的已唱字與片頭），再畫描邊，最後畫填色（strokeWidth −3.5），`setLineJoin(.round)`。掃色用 `NSBezierPath.setClip`；逐字模式依字元前綴寬度換算 x 位置。兩行版面：上行靠左、下行靠右，盒寬 `max(12.5em, 最寬行 + 2.2em)`；`singleLine` 只畫作用中那行並置中。片頭：置中歌名 1.4 倍字級，依 `usesRedTitle` 用紅 `#E5202A`／藍 `#35A7F0`；credits 0.74 倍靠左，紅配藍白邊、藍配白黑邊。倒數列為 `part + 星星`，下一句放下排。視窗寬 `min(螢幕 92%, 1500)`、高 320。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: draw karaoke overlay scenes`

### Task 11: 字幕視窗與移動模式

**Files:** Create `Sources/KTVOverlayUI/OverlayPanel.swift`、`HotKeyCenter.swift`；Test `Tests/KTVOverlayUITests/PanelTests.swift`

**Interfaces:**
- Consumes: `OverlayView`
- Produces:
```swift
public final class OverlayPanel: NSPanel { public init(contentRect: CGRect, view: OverlayView); public var isMoveMode: Bool { get set }; public var onMoved: ((CGRect) -> Void)? }
public final class HotKeyCenter { public init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) }  // Carbon RegisterEventHotKey，預設 ⌃⌥K
```

- [ ] **Step 1: 寫失敗的測試**

```swift
@Test @MainActor func panelIsClickThroughByDefault() { let p = makePanel(); #expect(p.ignoresMouseEvents && !p.isOpaque && !p.canBecomeKey && p.level == .screenSaver); #expect(p.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])) }
@Test @MainActor func moveModeAcceptsMouseThenRestores() { let p = makePanel(); p.isMoveMode = true; #expect(!p.ignoresMouseEvents); p.isMoveMode = false; #expect(p.ignoresMouseEvents) }
@Test @MainActor func movingReportsFrame() { /* isMoveMode 開啟後模擬拖曳，onMoved 收到新 frame */ }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter PanelTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — 移動模式顯示虛線框；關閉後穿透。快速鍵用 Carbon，不需要輔助使用權限。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: Commit** — `feat: add click-through panel and move mode`

### Task 12: 打包抓歌工具與播放器連線

**Files:** Create `Vendor/mediaremote-adapter/`（`bin/`、`include/`、`src/`、`LICENSE`，來自 commit `0e82bf1`）、`scripts/build-adapter.sh`、`THIRD_PARTY_NOTICES.md`、`Sources/KTVCore/Playback/RestartPolicy.swift`、`Sources/KTVOverlayUI/AdapterProcess.swift`、`Sources/KTVOverlayUI/PlayerClockReader.swift`；Test `Tests/KTVCoreTests/RestartPolicyTests.swift`、`Tests/KTVOverlayUITests/AdapterProcessTests.swift`

**Interfaces:**
- Consumes: `AdapterEvent`、`AdapterMessage`、`PlayerSample`、`ScriptablePlayer`
- Produces:
```swift
public enum RestartPolicy { public static func delay(attempt: Int) -> Double }
public enum AdapterStatus: Equatable, Sendable { case running, restarting(attempt: Int), failed }
public final class AdapterProcess { public init(executable: String, arguments: [String], onEvent: @escaping (AdapterEvent) -> Void, onStatus: @escaping (AdapterStatus) -> Void); public func start(); public func stop() }
public protocol PlayerClockReading { func read(_ player: ScriptablePlayer) -> PlayerSample? }
public final class PlayerClockReader: PlayerClockReading { public init() }
```

- [ ] **Step 1: 寫失敗的測試**

```swift
@Test func backoffDoublesAndCaps() { #expect((0...6).map(RestartPolicy.delay) == [1, 2, 4, 8, 16, 30, 30]) }
@Test func deliversEventsThenRestarts() async { /* executable /bin/sh、arguments ["-c", "printf '%s\\n' '<json>'; exit 1"]，<json> 用 Task 5 的 fixture：收到 .playing，狀態出現 .restarting(attempt: 0) */ }
@Test func missingExecutableReportsFailure() async { /* executable /no/such：onStatus 收到 .restarting 或 .failed，不當機 */ }
@Test func stopPreventsRestart() async { /* stop() 之後不再出現新的 restarting */ }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter "RestartPolicyTests|AdapterProcessTests"`。Expected: FAIL。
- [ ] **Step 3: 實作並寫建置腳本** — 連續失敗 8 次轉 `.failed`。正式啟動時 executable 是 `/usr/bin/perl`，參數為 `[adapter.pl, framework, "stream", "--no-diff", "--no-artwork", "--micros", "--debounce=100"]`。`build-adapter.sh` 不依賴 cmake：`clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -Iinclude -Isrc -framework Foundation -framework AppKit -framework UniformTypeIdentifiers <CMakeLists 列出的 adapter、private、utility 全部 .m> -install_name @rpath/MediaRemoteAdapter -o $OUT/MediaRemoteAdapter.framework/MediaRemoteAdapter`，再 `codesign --force --sign -`。`PlayerClockReader` 用 `NSAppleScript` 在主執行緒執行 `tell application "<name>" to return {player position, player state as text}`，時間取前後中點，失敗回 nil 並記錄。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。再跑 `scripts/build-adapter.sh`，播著歌時用 `/usr/bin/perl Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl build/adapter/MediaRemoteAdapter.framework get --micros --no-artwork`。Expected: JSON 含 `title` 與 `elapsedTimeMicros`。
- [ ] **Step 5: Commit** — `feat: vendor now-playing adapter and read player clocks`

### Task 13: 串接成可用的 app

**Files:** Create `Sources/KTVOverlayUI/AppCoordinator.swift`、`AppController.swift`、`StatusMenuController.swift`、`Resources/Info.plist`、`scripts/build-app.sh`、`Makefile`；Modify `Sources/KTVLyrics/main.swift`；Test `Tests/KTVOverlayUITests/AppCoordinatorTests.swift`

**Interfaces:**
- Consumes: 前面所有 Produces
- Produces:
```swift
@MainActor public final class AppCoordinator {
    public init(makeResolver: @escaping (_ useNetEase: Bool) -> any LyricsResolving, cache: LyricsCache, overrides: SongOverrideStore, settings: OverlaySettings, clock: any PlayerClockReading, runningApps: @escaping () -> Set<String>, now: @escaping () -> Double)
    public func handle(_ event: AdapterEvent)
    public func pollClock()
    public func content() -> OverlayContent
    public func adjustOffset(by delta: Double)
    public func apply(settings: OverlaySettings)
    public var statusText: String { get }
    public func waitForLookup() async     // 測試用
}
```

- [ ] **Step 1: 寫失敗的整合測試**（假的 resolver、clock、時間）

```swift
@Test func trackChangeLooksUpThenShowsTitle() async { /* handle(.playing)、waitForLookup：scene == .title，title 是清理後的歌名 */ }
@Test func seekSnapsOnNextPoll() async { /* 假時鐘跳 +30 秒，pollClock 後 scene 對應新位置 */ }
@Test func nothingPlayingClearsOverlay() async { /* 有字幕時 handle(.nothing)：scene == .idle，不再呼叫 clock */ }
@Test func closedPlayerIsNotPolled() async { /* runningApps 為空：pollClock 不呼叫 clock.read */ }
@Test func rapidSkipKeepsNewestLyrics() async { /* A 的查詢卡住，切到 B 完成，再放行 A：內容仍是 B */ }
@Test func cacheHitSkipsResolver() async { /* 快取已有：resolver 呼叫次數為 0 */ }
@Test func notFoundShowsNotice() async { /* .notFound：content.notice 含「找不到」，scene == .idle */ }
@Test func leadOnlyForLineTimedLyrics() async { /* 整行歌詞在 start−0.2 已 singing；逐字歌詞同時間仍未 singing */ }
@Test func offsetIsRememberedPerSong() async { /* adjustOffset(0.3) 後換歌再換回：位移仍在 */ }
@Test func settingsHideCards() async { /* showTitleCard false：原本 .title 變 .idle；showBanner false：.interlude(showBanner: false)；showCountdown false：倒數變 .idle */ }
@Test func netEaseSettingIsPassedThrough() async { /* apply(settings: .defaults.with(\.useNetEase, false)) 後，下一次查詢由 makeResolver(false) 建立的 resolver 處理 */ }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter AppCoordinatorTests`。Expected: FAIL。
- [ ] **Step 3: 實作 `AppCoordinator`** — 收到系統事件立刻 `pollClock`，另有 1 秒計時器。位置為 `resolver 位置 + 單曲 offset + (逐字 ? 0 : 0.25)`。`BannerPlanner` 的 seed 用 `StableHash.fnv1a(trackKey)`，`usesRedTitle` 用同一個 hash 的奇偶。查詢順序：單曲匯入、快取、resolver。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: 實作 `AppController`、選單與打包** — ♪ 選單：目前歌曲與來源、狀態、字幕提早 0.3 秒、字幕延後 0.3 秒、移動字幕（⌃⌥K）、顯示或隱藏字幕、換版本、匯入 .lrc、設定、結束。`Info.plist`：`LSUIElement` true、bundle id `com.ktvlyrics.app`、`NSAppleEventsUsageDescription` 為 `KTV Lyrics 需要讀取 Spotify 與音樂 app 的播放位置，讓字幕跟上拍子。`。`build-app.sh` 組出 `build/KTV Lyrics.app`，adapter 放 `Contents/Resources/`，整包 ad-hoc 簽章。`Makefile` 提供 `test`、`app`。視窗位置由 `PanelPlacement.frame` 算出，拖曳結束用 `PanelPlacement.anchor` 存回設定。
- [ ] **Step 6: 實機驗證** — Run: `make app && open "build/KTV Lyrics.app"`，在 Spotify 放歌。Expected: 幾秒內出現字幕；首次出現允許控制 Spotify 的提示；後面的按鈕點得到；快轉、暫停、換歌 1 秒內跟上。
- [ ] **Step 7: Commit** — `feat: wire the menu bar app together`

### Task 14: 設定視窗、換版本與匯入

**Files:** Create `Sources/KTVOverlayUI/SettingsViewModel.swift`、`SettingsView.swift`、`SettingsWindowController.swift`、`LoginItemController.swift`；Modify `StatusMenuController.swift`、`AppController.swift`；Test `Tests/KTVOverlayUITests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `OverlaySettings`、`SettingsStoring`、`StylePreset`、`LyricsCandidate`、`SongOverride`、`ScreenInfo`
- Produces:
```swift
@MainActor public final class SettingsViewModel: ObservableObject { @Published public private(set) var settings: OverlaySettings; public init(store: any SettingsStoring, onChange: @escaping (OverlaySettings) -> Void); public func selectPreset(_ preset: StylePreset); public func update(_ change: (OverlaySettings) -> OverlaySettings) }
extension AppCoordinator { public func availableCandidates() async -> [LyricsCandidate]; public func selectCandidate(id: String); public func importLRC(_ raw: String) }
```

- [ ] **Step 1: 寫失敗的測試**

```swift
@Test @MainActor func presetReplacesStyle() { /* selectPreset(.neon)：style == StylePreset.neon.style */ }
@Test @MainActor func tweakKeepsPresetName() { /* 選 gold 後改已唱色：preset 仍 gold，style.sungFill 為新值 */ }
@Test @MainActor func everyChangePersistsAndNotifies() { /* update 後 store.load 相等，onChange 呼叫一次 */ }
@Test @MainActor func selectedCandidateIsRemembered() async { /* selectCandidate 後換歌再換回：仍用該版本 */ }
@Test @MainActor func importedLyricsWin() async { /* importLRC 後 lyrics.source == .imported */ }
```

- [ ] **Step 2: 確認失敗** — Run: `swift test --filter SettingsViewModelTests`。Expected: FAIL。
- [ ] **Step 3: 實作** — SwiftUI 表單涵蓋 spec §4 全部項目（位置與顯示器、大小、不透明度、四種顏色、描邊粗細、字體、樣式、三種字卡開關、網易雲開關並註明「非官方來源、可能隨時失效」、開機啟動）。開機啟動用 `SMAppService.mainApp`，失敗時在設定頁顯示原因。
- [ ] **Step 4: 確認通過** — 同 Step 2。Expected: PASS。
- [ ] **Step 5: 實機驗證** — `make app`，打開設定。Expected: 每項改動即時反映在字幕上，重開 app 後仍在；匯入 .lrc 與換版本可用。
- [ ] **Step 6: Commit** — `feat: add settings window, version switching and LRC import`

### Task 15: 安裝、文件與發佈前驗收

**Files:** Create `README.md`、`scripts/check-coverage.sh`、`docs/ACCEPTANCE.md`；Modify `Makefile`

- [ ] **Step 1: 補 `Makefile` 目標** — `make install` 建置並複製到 `/Applications`，`make coverage` 執行 `scripts/check-coverage.sh`，`make release` 產出 `build/KTV-Lyrics.zip`。
- [ ] **Step 2: 寫覆蓋率檢查** — `swift test --enable-code-coverage`，再用 `xcrun llvm-cov report .build/debug/KTVLyricsPackageTests.xctest/Contents/MacOS/KTVLyricsPackageTests -instr-profile .build/debug/codecov/default.profdata Sources/KTVCore`，低於 80% 回傳非 0。Run: `make coverage`。Expected: 通過。
- [ ] **Step 3: 實測未公證版本的放行流程** — 解壓 `build/KTV-Lyrics.zip`，用 `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" "KTV Lyrics.app"` 模擬下載後打開，記下 macOS 26.4.1 的實際步驟。這一步需要提案人操作畫面。
- [ ] **Step 4: 實測重新編譯後的權限** — `make install` 兩次，確認第二次是否要求重新允許控制 Spotify，把結果寫進 README。
- [ ] **Step 5: 寫 README** — 繁中：功能、一行安裝 `git clone <repo> && cd ktv-lyrics && make install`（需 Xcode 開發工具）、未公證版本步驟（用 Step 3 的實測結果）、權限說明、歌詞來源與可關閉網易雲、快捷鍵、macOS 14、15 未測試、私有 API 與非官方來源的風險。
- [ ] **Step 6: 跑完 `docs/ACCEPTANCE.md`** — 逐項記錄結果：Spotify 與 Apple Music 字幕出現與快轉、YouTube 盡力支援與手動微調、全螢幕 Blender 上可見、點穿、焦點不被搶、多螢幕移動、台語歌《茫茫到深更》、找不到歌的提示、CPU 約 5%。Apple Music 是首次實測，失敗要回報，不要跳過。
- [ ] **Step 7: Commit** — `docs: add install guide and acceptance checklist`。公開 repo 與 push 等提案人明確要求。
