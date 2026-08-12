<!-- readme-revision: 1 -->
<!-- source-version: 1.0.1 -->
<!-- source-build: 1 -->

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Lyrinotch 应用图标">
</p>

# Lyrinotch

[English](README.md) | [繁體中文](README.zh-Hant.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md)

<!-- section: overview -->

一款非官方的第三方 macOS 菜单栏应用，可在 MacBook 刘海附近显示同步歌词；使用其他显示器时，则会以悬浮卡片显示。支持 Spotify 与 Apple Music。

> **Lyrinotch 与 Spotify、Apple、Apple Music、LRCLIB 或任何其他歌词提供方均无隶属、授权、赞助或背书关系。**

| | |
|---|---|
| **当前源码版本** | 1.0.1（build 1） |
| **平台** | macOS 14+；推荐使用 Apple Silicon |
| **播放器** | Spotify 桌面应用和／或 Music.app |
| **界面语言** | English、繁體中文、简体中文、日本語，以及跟随系统 |
| **许可证** | [MIT](LICENSE) |
| **代码仓库** | [github.com/barrygg11/lyrinotch](https://github.com/barrygg11/lyrinotch) |

源码中的版本可能比 GitHub 上最新的可下载构建更新。请在 [Releases 页面](https://github.com/barrygg11/lyrinotch/releases)查看各个构建的版本、签名与公证状态。

### 免责声明

- Spotify、Apple Music、歌词与专辑封面的权利均归各自权利人所有。
- Lyrinotch 仅在你播放有权访问的音乐时，将歌词显示在屏幕上供个人使用。请勿使用本应用复制、再分发、商业利用歌词，或绕过付费访问及 DRM。
- 在线与本地歌词来源均独立于 Lyrinotch；不保证其可用性、歌曲匹配、时间戳或准确性。
- 本软件依据 [MIT License](LICENSE) 按**“原样”**提供，不附带任何保证。
- 产品与服务名称仅用于说明兼容性。Lyrinotch 使用原创图稿，不使用 Spotify 或 Apple 的标志。

应用内版本可从**关于 Lyrinotch → 免责声明**查看。

<!-- section: features -->

## 主要功能

### 每块显示器都有合适的歌词界面

- **带刘海的 MacBook：**收起的动态岛会在摄像头区域下方显示当前歌词；将指针移上去或将其展开，即可查看更多歌词与控制项。
- **其他显示器：**菜单栏下方会显示悬浮卡片。
- 可让浮层跟随鼠标、使用主显示器，或固定到指定屏幕。
- 可选择在全屏时隐藏、启用点击穿透、调整版面，以及选择展开后的显示模式。

### 不打扰你的播放控制

- 通过本地 AppleScript“自动化”读取歌曲名称、艺人、专辑、时长、播放位置、封面与播放状态。
- 支持“自动”“Spotify 优先”和“Apple Music 优先”；首选播放器未播放时会自动切换。
- 展开浮层后，可使用上一首、播放／暂停、下一首、跳转／进度条，以及快速歌词时间校正。
- 支持可配置的全局快捷键；打包后的应用也支持登录时启动。

### 外观与辅助使用

- 可通过实时预览调整歌词大小、表面透明度、从封面提取的颜色、间距、垂直位置与显示行为。
- 在当前 macOS 版本支持时，可分别为刘海动态岛与悬浮卡片配置 Liquid Glass。
- 设置与显示文案会统一使用所选的界面语言。
- 暂停时仍保留控制项，因此可直接从浮层恢复播放。

<!-- section: lyrics -->

## 歌词、翻译与时间同步

### 歌词来源

| 来源 | 需要网络？ | 说明 |
|--------|----------|-------|
| LRCLIB | 是 | 新安装默认使用的歌词提供方偏好。 |
| NetEase / lyrics.ovh | 是 | 仅在所选歌词来源偏好启用时使用。 |
| Music.app 内嵌歌词 | 本地 | 配置的查询流程允许本地 Music 来源时使用。 |
| 导入本地 `.lrc` | 本地 | 由用户明确选择文件；支持 UTF-8 和带 BOM 的 UTF-16；最大 1 MB。 |
| Tap Sync | 本地 | 播放歌曲时记录每行歌词的锚点，稍后可继续编辑。 |

歌词来源偏好会同时控制自动查找与手动搜索。Lyrinotch 不会抓取 Spotify Web 或 Apple Music Web，也不会在此代码仓库中捆绑受版权保护的 `.lrc` 文件。

### 找不到同步歌词时的补救方式

- 纯文本歌词、有效时间行过少和当前播放区段时间点过于稀疏，会显示为不同状态，而不会全部归为同一个笼统的校正失败。
- 如果信任现有 LRC 的版本，可以将其导入。
- 使用 **Tap Sync**，在播放一遍歌曲的过程中逐行标记。实际点按的时间会保持精确；行间空缺、前奏与尾奏则根据相邻锚点及原始节奏估算。
- Tap Sync 草稿、撤销记录、来源指纹与生成的时间轴可在重新启动后保留，同时不会保存导入文件的原始路径。

### 翻译

可选翻译功能通过 MyMemory 支持繁体中文、简体中文、English 与日本語。源语言由 MyMemory 推断，目标语言则由用户选择。系统可能会发送当前与下一行歌词，以及推断的源语言和用户选择的目标语言，以便提前准备下一行翻译。

### 时间校正

- 可为当前使用环境设置全局歌词偏移。
- 可用 ±0.5 秒步进调整当前歌曲、让下一行立即对齐，或清除该歌曲的校正值。
- 可选的麦克风校正功能**默认关闭**，主要用于扬声器播放。它会将歌词时间戳与在本机精简得到的起音／能量包络进行比较。
- 校正需要可用的同步歌词时间点与稳定的播放状态。含义不明确、位于边界、遭到中断、音频路线已变更或已过期的样本都会被拒绝，不会保存。
- 校正值会按播放器、歌曲身份、歌词时间轴与音频环境相互隔离。

<!-- section: permissions -->

## 权限与问题排查

### 自动化

Lyrinotch 需要获得其所读取或控制的每个播放器的“自动化”权限。

1. 先打开 Apple Music 和／或 Spotify。
2. 打开 **Lyrinotch 设置 → 播放器**。
3. 为单个播放器选择**检查权限**，或选择**检查全部权限**以依次验证。
4. 如果 macOS 显示授权提示，请作出选择。

应用会区分**已授权**、**尚未授权**、**已拒绝**、**播放器未打开**、**验证超时**和**尚未验证**。“播放器未打开”不代表权限被拒绝——请启动该播放器后再次检查。如果此前拒绝了访问，请前往**系统设置 → 隐私与安全性 → 自动化**为 Lyrinotch 启用权限，然后回到应用内重新检查。

更改应用签名或运行以不同方式打包的副本，可能会让 macOS 将其视为另一个“自动化”客户端。日常使用时，建议始终使用同一个已安装且签名一致的应用。

### 麦克风

只有在你启用自动歌词校正，或启动可利用扬声器反馈的手动重新校正后，应用才会请求麦克风权限。你可以不授予此权限，改用 LRC 导入、Tap Sync 或手动偏移。

<!-- section: privacy -->

## 隐私与数据流向

Lyrinotch 可以使用完全本地的歌词来源，但在线提供方查询、翻译、远程封面与更新检查需要网络连接。

| 活动 | 本地／网络 | 可能离开这台 Mac 的内容 |
|----------|-----------------|-------------------------|
| 读取当前播放内容；播放、暂停、跳过或跳转 | 本地“自动化” | 无；Apple Event 只会发送给这台 Mac 上的播放器应用。 |
| 获取或搜索歌词 | 已启用的提供方需要网络；Music.app 查询可在本地进行 | 用于识别歌曲所需的名称、艺人、时长、专辑及相关查询元数据。 |
| 翻译歌词 | 网络，可选的 MyMemory 功能 | 当前与下一行歌词、推断的源语言，以及用户选择的目标语言。 |
| 加载专辑封面 | 本地和／或网络 | 当播放器提供 HTTPS 封面网址时发出的远程图片请求。 |
| 使用麦克风校正时间 | 本地，可选 | 不会上传麦克风音频。每次 10–18 秒的分析会在内存中精简为起音／能量包络；原始采样不会写入磁盘。 |
| 导入 LRC 或使用 Tap Sync | 本地 | 无。解析后的时间轴、锚点、撤销记录、歌曲身份与歌词指纹可能保存在本地；不会保留原始文件路径。 |
| 检查更新 | 网络，GitHub | 应用版本与标准 HTTP 请求元数据。 |
| Spotify / Apple 账户登录 | 不使用 | Lyrinotch 不会存储 Spotify 或 Apple OAuth 令牌。 |
| 分析、广告或第一方遥测 | 无 | Lyrinotch 不运营用户跟踪后端。 |

本地持久化的数据可能包括偏好设置、已选择的歌词、提供方缓存、封面缓存、翻译缓存、每首歌曲的偏移、校正信心度／环境指纹，以及 Tap Sync 项目。**清除已选歌词与歌曲校准值…**会移除手动选择的歌词、每首歌曲的时间校准、Tap Sync 草稿与撤销记录，以及内存缓存；其他偏好设置不受影响。

安全问题报告政策与更详细的本地处理承诺，请参阅 [SECURITY.md](SECURITY.md)。

<!-- section: install -->

## 安装打包构建

当 [GitHub Releases](https://github.com/barrygg11/lyrinotch/releases) 上提供合适的构建时：

1. 阅读其发行说明，以及签名／公证状态。
2. 打开 DMG。
3. 将 **Lyrinotch.app** 拖入 **Applications**；如有需要，请替换旧版本。
4. 启动已安装的应用。未公证的本地构建首次启动时可能需要使用**右键点击 → 打开**。
5. 打开你使用的播放器，并在**设置 → 播放器**中验证“自动化”权限。

登录时启动仅能在打包后的 `.app` 中可靠工作，不适用于 `swift run` 会话。

### 系统要求

- macOS 14+
- Spotify 和／或 Music（Apple Music）桌面应用
- 你所使用的每个播放器都需要“自动化”权限
- 使用基于扬声器的时间校正时，可选择授予麦克风权限
- 从源码构建时，需要 Xcode 16+ 或 Swift 5.10+ 工具链

<!-- section: build -->

## 从源码构建并运行

```bash
git clone https://github.com/barrygg11/lyrinotch.git
cd lyrinotch

swift build
swift test

# 菜单栏 app + 浮层；请保持终端会话处于打开状态。
swift run Lyrinotch

# CLI 诊断／轮询模式。
swift run Lyrinotch --cli
swift run Lyrinotch --once
swift run Lyrinotch --cli --interval-ms 1000
swift run Lyrinotch --help
```

创建可在本地双击启动的应用或磁盘映像：

```bash
./scripts/package-app.sh
open dist/Lyrinotch.app

./scripts/create-dmg.sh --local
```

通过 `.gitignore`，生成的应用、DMG、校验和与 Swift 构建产物均不会纳入 Git。

<!-- section: signing -->

## 签名与分发模式

| 模式 | 适用场景 | 重要行为 |
|------|--------------|--------------------|
| Ad-hoc，默认 | 本地源码构建 | 未公证；手动安装更新；当身份改变时，macOS 可能重新请求权限。 |
| Apple Development | 在已授权的开发用 Mac 上稳定测试 | 有明确身份的本地构建，但不是公开分发或已公证的发行版。 |
| Developer ID Application | 公开分发 | 必须遵循干净标签、Hardened Runtime、时间戳、公证、装订、完整性与校验和流程。 |

本地 Apple Development 构建示例——请使用你自己的“钥匙串”与开发者账户中的值：

```bash
security find-identity -v -p codesigning

export SIGN_IDENTITY="Apple Development: Your Name (CERTIFICATE_ID)"
export UPDATE_TEAM_ID="YOURTEAMID"
export DMG_SIGN_IDENTITY="$SIGN_IDENTITY"
./scripts/create-dmg.sh --local
```

请勿将由此生成的本地 DMG 作为正式发行版发布。准备 Developer ID 构建的维护者必须遵循 [docs/releasing.md](docs/releasing.md)，其中涵盖版本／标签检查、代码签名、公证、装订、已挂载 DMG 验证、SHA-256 生成与发行验证。

只有当正在运行的应用内嵌受信任的 Team ID 时，应用内更新器才会提供自动替换。替换前，它会验证代码仓库的发行网址、可选的 GitHub SHA-256 摘要、bundle identifier、版本、代码签名与 Team ID，然后以支持回滚的方式暂存替换内容。

<!-- section: layout -->

## 项目结构与配置

```text
lyrinotch/
├── README.md                    # 英文规范文档
├── README.zh-Hant.md            # 繁体中文
├── README.zh-Hans.md            # 简体中文
├── README.ja.md                 # 日文
├── Package.swift
├── Resources/                   # Info.plist、entitlements、本地化权限说明、图标
├── scripts/
│   ├── package-app.sh           # 构建 dist/Lyrinotch.app
│   ├── create-dmg.sh            # 构建并验证带版本号的 DMG
│   ├── check-readme-sync.sh     # 验证多语言 README 一致性
│   ├── test-release-notes-checker.sh # 测试发行说明验证器
│   ├── check-release-notes.sh   # 按 Info.plist 验证发行说明
│   └── check-coverage.sh        # 强制执行 CI 覆盖率下限
├── Sources/
│   ├── Lyrinotch/               # 应用外壳、设置、浮层控制器、CLI
│   └── LyrinotchCore/           # 模型、服务、本地化、共享 UI
├── Tests/LyrinotchTests/
└── docs/                        # 发行说明、路线图与发行流程
```

公开项目、支持与更新元数据在 `Sources/Lyrinotch/App/AppInfo.swift` 中配置：

| 字段 | 用途 |
|-------|---------|
| `repositoryURL` | Issues 与更新发行来源 |
| `koFiURL` 和其他支持网址 | 支持窗口的目标网址 |
| `supportEmail` | 安全／支持邮件后备地址 |

<!-- section: verification -->

## 验证

CI 会验证多语言文档和发行说明、严格 Swift 并发、优化后的 Release 构建、包含代码覆盖率的测试，以及 25% 的生产源码行覆盖率下限。

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

README 检查器要求四种语言的修订／版本标记及章节顺序完全相同，并拒绝指向不存在的本地 Markdown 链接。

<!-- section: contributing -->

## 贡献与支持

欢迎范围明确的 pull request。请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，明确说明提供方／隐私行为；公开行为发生变化时，请同步更新四份 README，并运行上面的验证命令。

- 一般问题与功能请求：[GitHub Issues](https://github.com/barrygg11/lyrinotch/issues)
- 应用内诊断：**关于 → 报告问题…**
- 安全敏感问题报告：[SECURITY.md](SECURITY.md)
- 支持项目：[Ko-fi](https://ko-fi.com/barrylai)

代码仓库的简要承诺：

- 应用与菜单栏使用原创图稿；不使用 Spotify 或 Apple 的官方标志。
- 代码仓库中不提交受版权保护的歌词数据库或歌词文件。
- 不使用第一方分析、广告 SDK 或跟踪后端。
- “自动化”与麦克风权限均有明确说明，可选功能始终保持可选。

<!-- section: license -->

## 许可证

[MIT](LICENSE) — Copyright © 2026 barry.

第三方名称、商标、歌词、音乐与图稿均归各自权利人所有，仅用于说明兼容性或显示用户请求的媒体内容。
