<div align="center">

<img src="docs/icon.png" width="120" alt="PastePop" />

# PastePop

[English](README.md) | [简体中文](README.zh-CN.md)

**复制过的，都在手边。**

<sub>原生体验 · 快速流畅 · 私密保存</sub>

![Platform](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Liquid Glass](https://img.shields.io/badge/UI-Liquid%20Glass-7AA7FF)
[![License](https://img.shields.io/github/license/realruian/pastepop?color=blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/realruian/pastepop?style=social)](https://github.com/realruian/pastepop)

<br/>

[![下载 DMG](https://img.shields.io/badge/下载-PastePop.dmg-7AA7FF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/realruian/pastepop/releases/latest)

<sub>最新版本见 <a href="https://github.com/realruian/pastepop/releases/latest">Releases</a></sub>

</div>

---

PastePop 把剪贴板变成一段清晰、可搜索的视觉历史。一个快捷键呼出，几秒找到并粘贴回来。

## 特性

- **自动记录与去重** —— 复制即保存，最新内容始终排在最前。
- **Paste 式 Power Search** —— 搜索与筛选标签共用固定宽度输入框，支持建议和键盘操作。
- **组合筛选** —— 内容类型、来源 App 和时间条件可以同时生效，也能逐个移除。
- **卡片式历史墙** —— 横向卡片按类型着色，来源 App 图标一眼可辨。
- **日常内容识别** —— 自动识别链接、图片、文件、邮箱、验证码、电话等内容。
- **富剪贴板支持** —— 除文字外，图片、文件和富文本也能保存、预览并原样粘回。
- **敏感内容保护** —— 密码、验证码、token、私钥等命中后隐藏或不保存。
- **固定、命名与分组** —— 常用内容进入独立分区，支持自定义名称和单层分组。
- **临时暂停记录** —— 可暂停 15 分钟、1 小时或直到手动恢复。
- **可配置粘贴行为** —— 支持只复制、粘贴到上一应用或粘贴为纯文本。
- **排除敏感 App** —— 默认不记录 Passwords、Keychain Access、1Password 和 Bitwarden。
- **原生 macOS 26 体验** —— Liquid Glass、语义色、Hugeicons、浅色/深色和 Reduce Motion。
- **流畅面板动效** —— Quick Panel 使用可打断的 Core Animation 合成层动画。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 呼出 / 隐藏面板 | `⌥ Space`（可在设置中更改） |
| 选择上一张 / 下一张 | `←` `→` 或 `↑` `↓` |
| 执行设置中的粘贴行为 | `Return` |
| Quick Look 预览 | `Space`（搜索为空时） |
| 仅复制后关闭 | `⌥ Return` |
| 粘贴为纯文本 | `⌘ Return` |
| 固定 / 取消固定 | `⌘P` |
| 删除选中 | `⌘⌫` |
| 切换 剪贴板 / 已固定 | `⌘1` / `⌘2` |
| 清空搜索 / 关闭面板 | `Esc` |

## 安装

### 下载 DMG

1. 从 [Releases](https://github.com/realruian/pastepop/releases/latest) 下载最新的 `PastePop-x.y.z.dmg`。
2. 打开 DMG，把 PastePop 拖到「应用程序」。
3. 本地构建尚未公证，首次启动请右键 PastePop 并选择「打开」。

PastePop 当前需要 Apple Silicon 与 macOS 26 Tahoe。

### 从源码构建

```bash
git clone https://github.com/realruian/pastepop.git
cd pastepop

swift run PastePop            # 开发运行
bash scripts/build-app.sh     # 构建 .build/PastePop.app
bash scripts/install-app.sh   # 覆盖安装到 /Applications 并启动
bash scripts/build-dmg.sh     # 构建 .build/PastePop-x.y.z.dmg
```

`install-app.sh` 会签名本地构建、注册 Launch Services、通知 Spotlight 导入应用并启动安装后的版本。

粘贴到上一应用需要在「系统设置 → 隐私与安全性 → 辅助功能」中允许 PastePop。没有权限时，PastePop 仍会把内容写回剪贴板，你可以手动按 `⌘V`。

## 隐私

- 剪贴板历史只存于本地 SQLite：`~/Library/Application Support/PastePop/`。
- 不提供云同步，也不上传剪贴板内容。
- 保留时长、历史数量、排除 App 和敏感内容保护均可配置。
- 默认排除常见密码与密钥管理 App。
- 链接预览默认关闭，只有开启后才会联网。

## 技术栈

Swift 6.2 · SwiftUI · AppKit · Core Animation · [GRDB](https://github.com/groue/GRDB.swift) · SQLite · Keychain

## 路线图与贡献

核心剪贴板能力、富内容、搜索筛选、固定分组、隐私控制和本地打包已经完成。后续计划见 [ROADMAP.md](ROADMAP.md)。

欢迎 issue 与 PR。修改产品行为或视觉前，请先阅读 [DESIGN.md](DESIGN.md) 和 [CLAUDE.md](CLAUDE.md)。

## License

[MIT](LICENSE) © [Ruian Tian](https://github.com/realruian)

<div align="center"><sub>Built for everyone who copies things every day.</sub></div>
