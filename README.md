# KTV Lyrics

macOS 選單列 app，在畫面上印出 KTV 風格的卡拉 OK 字幕。字幕是透明的、滑鼠可以點穿，浮在所有 app 上（包括全螢幕的 app），寫 code 時照常工作，不會擋到也不會搶走焦點。

## 功能

- 自動跟著正在播放的歌顯示字幕，不需要手動準備。支援 Spotify、Apple Music，YouTube 為盡力支援，準度需要手動微調。
- KTV 風格：白字黑邊，唱到的字逐字變藍色，上下兩行交錯。
- 片頭字卡（歌名、原唱、作詞、作曲）、開唱前的星星倒數、長間奏時偶爾出現的《來賓請掌聲鼓勵》。
- 歌詞來源：LRCLIB，以及網易雲音樂（可關閉）。找不到歌詞時會顯示提示，不會配到同名的其他歌。
- 選單列可以換版本、匯入自己的 `.lrc` 檔、調整字幕提早或延後。
- 設定視窗可以調整位置與顯示器、大小、不透明度、顏色、字體、樣式預設，以及各種字卡的開關。

## 安裝

需要 macOS 與 Xcode 開發工具（沒有的話先執行 `xcode-select --install`）。

```sh
git clone https://github.com/gn01763009/ktv-lyrics.git && cd ktv-lyrics && make install
```

`make install` 會先編譯 app，然後刪除舊的 `/Applications/KTV Lyrics.app`（如果有），再用 `ditto` 複製新的 app 過去。**執行 `make install` 前請先結束 KTV Lyrics**（選單列 ♪ → 結束），避免替換正在執行的 app。只想編譯、不安裝，執行 `make app`，產物在 `build/KTV Lyrics.app`。

第一次播放歌曲時，macOS 可能會詢問是否允許 KTV Lyrics 控制 Spotify 或音樂 app（實際是否出現，以你的 Mac 為準）。這是用來讀取播放位置，讓字幕跟上歌曲。

### 下載未公證的 app（尚未測試）

`make release` 會在 `build/KTV-Lyrics.zip` 產出未公證的 app。這個下載後打開的流程**尚未測試**，我們還沒有在 macOS 26 上實際走過，因此這裡不提供操作步驟。**建議直接用上面的一行原始碼安裝。**

## 快捷鍵與操作

- **⌃⌥K**：進入或離開移動字幕模式。進入後字幕會顯示虛線框，可以直接拖曳到想要的位置；離開後字幕恢復點穿。
- 選單列 ♪ 圖示：顯示目前歌曲與歌詞來源、字幕提早或延後、換版本、匯入 .lrc、移動字幕、顯示或隱藏字幕、設定、結束。

## 權限

- 第一次需要允許控制 Spotify 或音樂 app（見上方安裝說明）。
- 重新編譯後 app 的簽章會改變，macOS 可能會再次要求允許控制 Spotify。**這一點尚未驗證**，實際行為以你的 Mac 為準。

## 歌詞來源

歌詞依序從以下來源取得，前面的有資料就不往後找：

1. 網易雲音樂的逐字資料（有通過比對檢查時才使用）。
2. LRCLIB 的整行歌詞。
3. 網易雲音樂的整行歌詞。

網易雲音樂是**非官方來源**，介面可能隨時改變或失效。失效時會自動退回 LRCLIB，只是會失去逐字變色與作詞作曲資訊。

如果不想使用網易雲，到 **設定 → 歌詞來源**，關閉「使用網易雲音樂」即可，之後只使用 LRCLIB。

### 隱私：會送出什麼

為了查歌詞，**歌名與歌手名稱預設會送到 LRCLIB 與網易雲音樂**。這包含瀏覽器正在播放的媒體標題（例如 YouTube 影片的標題），因為 app 無法分辨它是不是歌曲。除此之外不會送出其他資料。關閉「使用網易雲音樂」後，只會送到 LRCLIB。

### 快取

查到的歌詞與每首歌的設定（偏移、匯入的 .lrc、選的版本）存在 `~/Library/Application Support/KTV Lyrics/`：

- `cache/`：歌詞快取。依「是否使用網易雲音樂」分成 `netease-on` 與 `netease-off` 兩個子資料夾，切換設定會立刻讀寫對應的那一個。找不到的結果只保留 24 小時；因為網路或來源失敗而沒查完的結果不會存。
- `overrides/`：每首歌的偏移、匯入的歌詞與選的版本。

要清除快取，先結束 app，再刪掉資料夾：`rm -rf ~/Library/Application\ Support/KTV\ Lyrics/cache`。要連每首歌的設定一起清掉，刪除整個 `KTV Lyrics` 資料夾。

找不到歌詞時，字幕層會短暫顯示「找不到字幕」，然後保持透明。如果是因為網路或來源暫時失敗，會顯示「暫時查不到字幕，下次播放會再試一次」，且不會被當成找不到而記住。這時可以用選單列的「匯入 .lrc…」匯入自己的歌詞檔，或用「換版本」切換候選版本。

## 測試狀況

- 目前只在 **macOS 26.4.1**（M1）上實測過。**macOS 14 與 15 尚未測試。**
- **Apple Music 尚未實測**，它的字幕與快轉行為還不確定。
- YouTube 的時間準度尚未實測，需要用選單列的字幕提早或延後手動微調。
- 驗收的完整清單見 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。

## 風險與限制

- **私有 API**：偵測播放中的歌曲，是透過 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) 載入系統的私有 framework。Apple 隨時可能封鎖，屆時會偵測不到播放器。因為依賴私有 API，這個 app 無法上架 Mac App Store。
- **非官方歌詞來源**：網易雲音樂的介面不是官方提供，可能隨時失效，歌詞的使用條款也需要使用者自行留意。repo 本身不收錄任何歌詞，歌詞只會在執行時由使用者的電腦查詢。
- **不付費簽章**：app 只用 ad-hoc 簽章，沒有 Apple Developer 帳號，也沒有公證。
- **播放時間**：Spotify 回報給系統的時間不準，所以 Spotify 與 Apple Music 會每秒用 AppleScript 讀取播放器的實際位置來校正（Apple Music 這條路徑尚未實測）。

## 開發

```sh
make test       # 執行全部測試
make coverage   # 測試並檢查 KTVCore 行覆蓋率（門檻 80%）
make app        # 只編譯 build/KTV Lyrics.app
make release    # 產出 build/KTV-Lyrics.zip
```

設計文件見 [docs/superpowers/specs/2026-11-08-ktv-lyrics-overlay-design.md](docs/superpowers/specs/2026-11-08-ktv-lyrics-overlay-design.md)。

## 授權

MIT License，見 [LICENSE](LICENSE)。打包的第三方元件授權見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，它也會複製進 app 的 `Contents/Resources/`。
