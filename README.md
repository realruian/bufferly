<div align="center">

<img src="docs/icon.png" width="120" alt="PastePop" />

# PastePop

[English](README.md) | [简体中文](README.zh-CN.md)

**A local-first clipboard assistant for everyday Mac users**

![Platform](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Liquid Glass](https://img.shields.io/badge/UI-Liquid%20Glass-7AA7FF)
[![License](https://img.shields.io/github/license/realruian/bufferly?color=blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/realruian/bufferly?style=social)](https://github.com/realruian/bufferly)

<br/>

[![Download DMG](https://img.shields.io/badge/Download-PastePop.dmg-7AA7FF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/realruian/bufferly/releases/latest)

<sub>Get the latest build from <a href="https://github.com/realruian/bufferly/releases/latest">Releases</a></sub>

</div>

---

PastePop keeps the text, links, images, and files you copy close at hand. Search, filter, pin, and safely paste them back without sending clipboard contents to the cloud. It is designed to feel like a natural part of macOS.

## Features

- **Automatic capture and deduplication** — copied items are saved locally, with the newest item first.
- **Paste-style Power Search** — search and filter tokens share one stable input with suggestions and keyboard control.
- **Combined filters** — narrow results by content type, source app, and time at the same time.
- **Visual card history** — scan a horizontal wall of type-colored cards with source-app icons.
- **Everyday content recognition** — links, images, files, email addresses, verification codes, phone numbers, and more.
- **Rich clipboard support** — preserve and preview images, files, and rich text in addition to plain text.
- **Sensitive-content protection** — detected passwords, verification codes, tokens, and private keys are hidden or excluded.
- **Pins, names, and groups** — keep reusable content in a dedicated area with custom names and one-level groups.
- **Pause recording** — stop capture for 15 minutes, one hour, or until manually resumed.
- **Configurable paste behavior** — copy only, paste into the previous app, or paste as plain text.
- **Excluded apps** — Passwords, Keychain Access, 1Password, and Bitwarden are excluded by default.
- **Native macOS 26 experience** — Liquid Glass, semantic colors, Hugeicons, Light/Dark appearance, and Reduce Motion.
- **Smooth panel motion** — Quick Panel entrance and exit use interruptible Core Animation compositing.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Show or hide Quick Panel | `⌥ Space` by default |
| Move between cards | `←` `→` or `↑` `↓` |
| Run the configured paste action | `Return` |
| Quick Look preview | `Space` when search is empty |
| Copy and close | `⌥ Return` |
| Paste as plain text | `⌘ Return` |
| Pin or unpin | `⌘P` |
| Delete the selected item | `⌘⌫` |
| Switch Clipboard / Pinned | `⌘1` / `⌘2` |
| Clear search or close | `Esc` |

## Installation

### Download the app

1. Download the latest `PastePop-x.y.z.dmg` from [Releases](https://github.com/realruian/bufferly/releases/latest).
2. Open the DMG and drag PastePop into Applications.
3. On first launch, right-click PastePop and choose **Open** because local builds are not notarized.

PastePop currently requires Apple Silicon and macOS 26 Tahoe.

### Build from source

```bash
git clone https://github.com/realruian/bufferly.git
cd bufferly

swift run PastePop            # Run a development build
bash scripts/build-app.sh     # Build .build/PastePop.app
bash scripts/install-app.sh   # Install to /Applications and launch
bash scripts/build-dmg.sh     # Build .build/PastePop-x.y.z.dmg
```

`install-app.sh` signs the local build, registers it with Launch Services, asks Spotlight to import it, and launches the installed app.

Pasting into the previous app requires Accessibility permission under **System Settings → Privacy & Security → Accessibility**. Without it, PastePop still restores the selected item to the clipboard for a manual `⌘V`.

## Privacy

- Clipboard history is stored locally in SQLite under `~/Library/Application Support/PastePop/`.
- PastePop does not provide cloud sync or upload clipboard contents.
- Retention time, history limits, excluded apps, and sensitive-content protection are configurable.
- Sensitive apps are excluded by default.
- Link previews are disabled by default and access the network only when enabled.

## Technology

Swift 6.2 · SwiftUI · AppKit · Core Animation · [GRDB](https://github.com/groue/GRDB.swift) · SQLite · Keychain

## Roadmap and contributing

The core clipboard experience, rich content, search, filters, pins, groups, privacy controls, and local packaging are implemented. See [ROADMAP.md](ROADMAP.md) for what comes next.

Contributions are welcome. Read [DESIGN.md](DESIGN.md) and [CLAUDE.md](CLAUDE.md) before changing product behavior or visuals.

## License

[MIT](LICENSE) © [Ruian Tian](https://github.com/realruian)

<div align="center"><sub>Built for everyone who copies things every day.</sub></div>
