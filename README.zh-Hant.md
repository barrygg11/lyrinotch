<!-- readme-revision: 1 -->
<!-- source-version: 1.0.1 -->
<!-- source-build: 1 -->

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Lyrinotch app 圖示">
</p>

# Lyrinotch

[English](README.md) | [繁體中文](README.zh-Hant.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md)

<!-- section: overview -->

Lyrinotch 是一款非官方的第三方 macOS 選單列 app，可在 MacBook 瀏海附近顯示同步歌詞，也能在其他顯示器上以懸浮卡片呈現，支援 Spotify 與 Apple Music。

> **Lyrinotch 與 Spotify、Apple、Apple Music、LRCLIB 或任何其他歌詞供應商皆無隸屬關係，亦未獲得其授權、贊助或背書。**

| | |
|---|---|
| **目前原始碼版本** | 1.0.1（build 1） |
| **平台** | macOS 14+；建議使用 Apple Silicon |
| **播放器** | Spotify 桌面版 app 和／或 Music.app |
| **介面語言** | English、繁體中文、简体中文、日本語，以及跟隨系統 |
| **授權條款** | [MIT](LICENSE) |
| **原始碼儲存庫** | [github.com/barrygg11/lyrinotch](https://github.com/barrygg11/lyrinotch) |

原始碼版本可能比 GitHub 上最新的可下載成品更新。請到 [Releases 頁面](https://github.com/barrygg11/lyrinotch/releases)查看各項目的版本、簽章及公證狀態。

### 免責聲明

- Spotify、Apple Music、歌詞與專輯封面皆為其各自權利人的財產。
- Lyrinotch 僅在你播放有權存取的音樂時，於畫面上顯示歌詞供個人使用。請勿使用本軟體複製、重新散布或以商業方式利用歌詞，也不得用於規避付費存取機制或 DRM。
- 線上與本機歌詞來源皆獨立於 Lyrinotch；不保證其可用性、歌曲配對、時間戳記或準確度。
- 本軟體依 [MIT License](LICENSE) 按**「現狀」**提供，不附帶任何形式的保證。
- 產品與服務名稱僅用於識別相容性。Lyrinotch 使用原創圖像，不使用 Spotify 或 Apple 的標誌。

你也可以從 app 內的**關於 Lyrinotch → 免責聲明**查看此內容。

<!-- section: features -->

## 功能亮點

### 適用各種顯示器的歌詞介面

- **配備瀏海的 MacBook：**收合的動態島會在相機區域下方顯示目前歌詞；將游標移上去或展開，即可查看更多歌詞與控制項目。
- **其他顯示器：**在選單列下方顯示懸浮卡片。
- 可讓浮層跟隨滑鼠、顯示於主要顯示器，或固定在特定螢幕上。
- 可選擇在全螢幕時隱藏、允許點擊穿透、調整版面，以及選擇展開時的呈現模式。

### 不打擾聆聽的播放控制

- 透過本機 AppleScript 自動化讀取歌曲名稱、演出者、專輯、時長、播放位置、封面與播放狀態。
- 支援自動、Spotify 優先及 Apple Music 優先選擇；偏好的播放器未播放時會自動改用另一個播放器。
- 展開浮層後可操作上一首、播放／暫停、下一首、跳轉／進度，以及歌詞時間的快速調整。
- 提供可自訂的全域快速鍵；打包後的 app 也支援登入時自動啟動。

### 外觀與輔助使用

- 透過即時預覽調整歌詞大小、介面透明度、取自封面的顏色、間距、垂直位置與顯示行為。
- 若目前執行的 macOS 版本支援，可分別設定瀏海動態島與懸浮卡片的 Liquid Glass 效果。
- 設定與呈現文字皆使用所選的介面語言。
- 暫停時仍保留控制項目，方便直接從浮層恢復播放。

<!-- section: lyrics -->

## 歌詞、翻譯與時間同步

### 歌詞來源

| 來源 | 需要網路？ | 說明 |
|------|------------|------|
| LRCLIB | 是 | 新安裝預設使用的歌詞供應商偏好。 |
| NetEase / lyrics.ovh | 是 | 只有所選的供應商偏好啟用它們時才會使用。 |
| Music.app 內嵌歌詞 | 否 | 設定的供應流程允許本機 Music 來源時才會查詢。 |
| 匯入本機 `.lrc` | 否 | 由使用者明確選擇檔案；支援 UTF-8 與含 BOM 的 UTF-16；檔案上限為 1 MB。 |
| Tap Sync | 否 | 歌曲播放時記錄各行歌詞的錨點，之後可繼續編輯專案。 |

供應商偏好會同時控制自動查找與手動搜尋。Lyrinotch 不會擷取 Spotify Web 或 Apple Music Web，也不會在此原始碼儲存庫內附帶受著作權保護的 `.lrc` 檔案。

### 找不到同步歌詞時的處理方式

- 純文字歌詞、具時間的歌詞行數過少，以及目前播放區段的時間點過於稀疏，會分別顯示不同狀態，而不是一律回報為校準失敗。
- 若你信任現有 LRC 的歌曲版本，可以直接匯入。
- 使用 **Tap Sync**，在播放一遍歌曲時標記各行歌詞。手動點擊的時間會精確保留；中間缺口、前奏與尾奏則依鄰近錨點和原始節奏估算。
- Tap Sync 草稿、復原紀錄、來源指紋與產生的時間軸可在重新啟動後保留，且不會保留匯入檔案的路徑。

### 翻譯

選用的翻譯功能透過 MyMemory 支援繁體中文、简体中文、English 與日本語。來源語言由 MyMemory 推斷，目標語言則由使用者選擇。系統可能會傳送目前與下一行歌詞，以及推斷的來源語言和使用者選擇的目標語言，以便及時準備下一行翻譯。

### 時間校正

- 為目前使用環境設定全域歌詞偏移。
- 以 ±0.5 秒調整目前歌曲、立即對齊下一行，或清除該曲的校正值。
- 選用的麥克風校準預設為**關閉**，主要用於揚聲器播放。它會比較歌詞時間戳記與在本機簡化後的起音／能量包絡。
- 校準需要可用的同步歌詞時間點和穩定的播放狀態。模糊、位於邊界、遭中斷、音訊路由已變更或過期的樣本都會被捨棄，不會儲存。
- 校正值會依播放器、歌曲識別資訊、歌詞時間軸與音訊環境分開保存。

<!-- section: permissions -->

## 權限與疑難排解

### 自動化

Lyrinotch 需要取得它所讀取或控制之各播放器的自動化權限。

1. 先開啟 Apple Music 和／或 Spotify。
2. 開啟 **Lyrinotch 設定 → 播放器**。
3. 選擇單一播放器的**檢查權限**，或使用**檢查全部權限**依序驗證。
4. 若 macOS 顯示同意提示，請依提示回應。

App 會區分**已授權**、**未授權**、**已拒絕**、**播放器未開啟**、**驗證逾時**及**尚未驗證**。「播放器未開啟」不代表權限遭拒；請啟動該播放器後再次檢查。若權限已遭拒，請前往**系統設定 → 隱私權與安全性 → 自動化**啟用 Lyrinotch，再回到 app 重新檢查。

變更 app 簽章或執行不同方式打包的副本，可能使 macOS 將它視為另一個自動化用戶端。日常使用時，建議固定使用同一個已安裝且簽章一致的 app。

### 麥克風

只有在你啟用歌詞自動校準，或開始能利用揚聲器回授的手動重新校準後，系統才會要求麥克風權限。你可以不啟用此權限，改用匯入 LRC、Tap Sync 或手動偏移。

<!-- section: privacy -->

## 隱私權與資料流向

Lyrinotch 可以使用完全在本機運作的歌詞來源，但線上供應商查找、翻譯、遠端封面與更新檢查皆需要網路連線。

| 活動 | 本機／網路 | 可能離開你 Mac 的資料 |
|------|------------|------------------------|
| 讀取播放中資訊；播放、暫停、跳過或跳轉 | 本機自動化 | 無；Apple event 只會傳送給這台 Mac 上的播放器 app。 |
| 取得或搜尋歌詞 | 已啟用的網路供應商；可選用本機 Music.app 查詢 | 為識別歌曲所需的歌曲名稱、演出者、時長、專輯及相關查詢中繼資料。 |
| 翻譯歌詞 | 網路；選用的 MyMemory 功能 | 目前與下一行歌詞、推斷的來源語言，以及使用者選擇的目標語言。 |
| 載入專輯封面 | 本機和／或網路 | 播放器提供 HTTPS 封面網址時所發出的遠端圖片請求。 |
| 使用麥克風校準時間 | 本機；選用 | 不會上傳麥克風音訊。每次 10–18 秒的分析會在記憶體中簡化為起音／能量包絡；原始取樣不會寫入磁碟。 |
| 匯入 LRC 或使用 Tap Sync | 本機 | 無。解析後的時間軸、錨點、復原紀錄、歌曲識別資訊與歌詞指紋可能儲存在本機。不會保留原始檔案路徑。 |
| 檢查更新 | 網路；GitHub | App 版本與標準 HTTP 請求中繼資料。 |
| 登入 Spotify / Apple 帳號 | 未使用 | Lyrinotch 不會儲存 Spotify 或 Apple OAuth token。 |
| 分析、廣告或第一方遙測 | 無 | Lyrinotch 沒有營運任何使用者追蹤後端。 |

儲存在本機的資料可能包括偏好設定、已選歌詞、供應商快取、封面快取、翻譯快取、單曲偏移、校準信心度／環境指紋，以及 Tap Sync 專案。**清除已選歌詞與歌曲校正值…**會移除手動選擇的歌詞、單曲時間校正、Tap Sync 草稿與復原紀錄，以及記憶體快取；其他偏好設定不受影響。

安全性問題回報政策與詳細的本機處理承諾，請參閱 [SECURITY.md](SECURITY.md)。

<!-- section: install -->

## 安裝打包版本

當 [GitHub Releases](https://github.com/barrygg11/lyrinotch/releases) 提供合適的成品時：

1. 閱讀其版本說明及簽章／公證狀態。
2. 開啟 DMG。
3. 將 **Lyrinotch.app** 拖到 **Applications**；如有需要，請取代舊版本。
4. 啟動已安裝的 app。未經公證的本機版本第一次啟動時，可能需要**按右鍵 → 打開**。
5. 開啟你使用的播放器，並在**設定 → 播放器**中驗證自動化權限。

登入時自動啟動只能在打包後的 `.app` 中穩定運作，不適用於 `swift run` 工作階段。

### 系統需求

- macOS 14+
- Spotify 和／或 Music（Apple Music）桌面版 app
- 你所使用之每個播放器的自動化權限
- 使用揚聲器校準時間時，可選擇授予麥克風權限
- 從原始碼建置時，需要 Xcode 16+ 或 Swift 5.10+ 工具鏈

<!-- section: build -->

## 從原始碼建置與執行

```bash
git clone https://github.com/barrygg11/lyrinotch.git
cd lyrinotch

swift build
swift test

# 選單列 app + 浮層；請保持終端機工作階段開啟。
swift run Lyrinotch

# CLI 診斷／輪詢模式。
swift run Lyrinotch --cli
swift run Lyrinotch --once
swift run Lyrinotch --cli --interval-ms 1000
swift run Lyrinotch --help
```

建立可在本機點兩下執行的 app 或磁碟映像檔：

```bash
./scripts/package-app.sh
open dist/Lyrinotch.app

./scripts/create-dmg.sh --local
```

產生的 app、DMG、checksum 與 Swift 建置產物會透過 `.gitignore` 排除在 Git 之外。

<!-- section: signing -->

## 簽章與散布模式

| 模式 | 適用情境 | 重要行為 |
|------|----------|----------|
| Ad-hoc（預設） | 本機原始碼建置 | 未經公證；需手動安裝更新；識別資訊變更時，macOS 可能會重新要求權限。 |
| Apple Development | 在已授權的開發用 Mac 上穩定測試 | 具可識別身分的本機版本，但不屬於公開散布或經公證的發行版本。 |
| Developer ID Application | 公開散布 | 必須遵循乾淨 tag、hardened runtime、timestamp、公證、stapling、完整性與 checksum 流程。 |

本機 Apple Development 建置範例——請使用你自己的 Keychain 與開發者帳號資訊：

```bash
security find-identity -v -p codesigning

export SIGN_IDENTITY="Apple Development: Your Name (CERTIFICATE_ID)"
export UPDATE_TEAM_ID="YOURTEAMID"
export DMG_SIGN_IDENTITY="$SIGN_IDENTITY"
./scripts/create-dmg.sh --local
```

請勿將產生的本機 DMG 發布為官方版本。準備 Developer ID 成品的維護者必須遵循 [docs/releasing.md](docs/releasing.md)，其中涵蓋版本／tag 檢查、程式碼簽章、公證、stapling、掛載後的 DMG 驗證、產生 SHA-256，以及發行驗證。

App 內更新程式只會在執行中的 app 內嵌受信任的 Team ID 時提供自動取代。取代前，它會驗證原始碼儲存庫的 Release URL、選用的 GitHub SHA-256 digest、bundle identifier、版本、程式碼簽章與 Team ID，再以支援復原的暫存方式完成取代。

<!-- section: layout -->

## 專案結構與設定

```text
lyrinotch/
├── README.md                    # 英文基準文件
├── README.zh-Hant.md            # 繁體中文
├── README.zh-Hans.md            # 簡體中文
├── README.ja.md                 # 日文
├── Package.swift
├── Resources/                   # Info.plist、entitlements、本地化權限文字、圖示
├── scripts/
│   ├── package-app.sh           # 建置 dist/Lyrinotch.app
│   ├── create-dmg.sh            # 建置並驗證含版本的 DMG
│   ├── check-readme-sync.sh     # 驗證多語 README 一致性
│   ├── test-release-notes-checker.sh # 測試版本說明驗證工具
│   ├── check-release-notes.sh   # 依 Info.plist 驗證版本說明
│   └── check-coverage.sh        # 強制執行 CI 覆蓋率下限
├── Sources/
│   ├── Lyrinotch/               # App 外殼、設定、浮層控制器、CLI
│   └── LyrinotchCore/           # 模型、服務、本地化、共用 UI
├── Tests/LyrinotchTests/
└── docs/                        # 版本說明、roadmap 與發行流程
```

公開專案、支援與更新的中繼資料設定於 `Sources/Lyrinotch/App/AppInfo.swift`：

| 欄位 | 用途 |
|------|------|
| `repositoryURL` | Issues 與更新版本來源 |
| `koFiURL` 與其他支援 URL | 支援視窗的目的地 |
| `supportEmail` | 安全性／支援郵件的備用聯絡方式 |

<!-- section: verification -->

## 驗證

CI 會驗證多語文件與版本說明、嚴格 Swift concurrency、最佳化的 Release 建置、含程式碼覆蓋率的測試，以及正式原始碼至少 25% 的行覆蓋率。

```bash
bash scripts/check-readme-sync.sh
bash scripts/test-release-notes-checker.sh
bash scripts/check-release-notes.sh

swift test --enable-code-coverage \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warn-concurrency \
  -Xswiftc -warnings-as-errors

bash scripts/check-coverage.sh 25
swift build -c release
```

README 檢查工具要求四個語言版本的修訂／版本標記與章節順序完全一致，並會拒絕指向不存在之本機 Markdown 目標的連結。

<!-- section: contributing -->

## 貢獻與支援

歡迎範圍明確的 pull request。請先閱讀 [CONTRIBUTING.md](CONTRIBUTING.md)、清楚說明供應商／隱私權行為，在公開行為變更時更新全部四份 README，並執行上述驗證命令。

- 一般錯誤與功能建議：[GitHub Issues](https://github.com/barrygg11/lyrinotch/issues)
- App 內診斷：**關於 → 回報問題⋯**
- 安全性相關回報：[SECURITY.md](SECURITY.md)
- 支持專案：[Ko-fi](https://ko-fi.com/barrylai)

原始碼儲存庫的簡要承諾：

- App 與選單列皆使用原創圖像；不使用 Spotify 或 Apple 的官方標誌。
- 原始碼儲存庫不會提交受著作權保護的歌詞資料庫或歌詞檔案。
- 沒有第一方分析、廣告 SDK 或追蹤後端。
- 自動化與麥克風權限均有清楚說明，所有選用功能都會維持為選用。

<!-- section: license -->

## 授權條款

[MIT](LICENSE) — Copyright © 2026 barry.

第三方名稱、商標、歌詞、音樂與圖像皆為其各自權利人的財產，僅用於識別相容性或顯示使用者要求的媒體。
