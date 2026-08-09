<div align="center">

<img src="docs/icon.png" width="120" alt="Bufferly" />

# Bufferly

[English](README.md) | [简体中文](README.zh-CN.md)

**A local-first clipboard workspace for developers and AI-heavy workflows**

![Platform](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Liquid Glass](https://img.shields.io/badge/UI-Liquid%20Glass-7AA7FF)
[![License](https://img.shields.io/github/license/Innate-Labs/bufferly?color=blue)](LICENSE)

</div>

Bufferly automatically organizes copied code, commands, links, JSON, prompts, images, files, and temporary text into a searchable and reusable local workspace. It is designed for developer and AI workflows rather than as a generic clipboard replacement, and clipboard history stays on your Mac by default.

## Features

- **Automatic capture and deduplication** — new clipboard items appear first without filling the history with duplicates.
- **Fuzzy search and relevance ranking** — find `database connection` with a short query such as `dbcon`.
- **Type-aware cards** — distinguish URLs, code, JSON, commands, email, images, files, and rich text at a glance.
- **Native paste-back** — select an item and press Return to restore it to the clipboard and paste it into the previous app.
- **Pinned snippets** — keep frequently reused content in a dedicated section.
- **Developer transforms** — format or minify JSON and remove tracking parameters from URLs.
- **Sensitive-content filtering** — redact or discard detected tokens, passwords, `.env` values, and API keys.
- **Native macOS experience** — Liquid Glass, semantic colors, SF Symbols, light/dark appearance, and Reduce Motion support.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Show or hide the panel | `⌥ Space` by default |
| Move between cards | Arrow keys |
| Paste the selected item | `Return` |
| Quick Look preview | `Space` when search is empty |
| Copy and close without pasting | `⌥ Return` |
| Pin or unpin | `⌘P` |
| Delete the selected item | `⌘⌫` |
| Clear search or close | `Esc` |

## Installation

### Download the app

Download the latest DMG from the [Bufferly releases page](https://github.com/Innate-Labs/bufferly/releases/latest), open it, and drag Bufferly into Applications. The current build requires Apple Silicon and macOS 26 Tahoe.

Because the app is not notarized, use right-click → **Open** the first time.

### Build from source

```bash
git clone https://github.com/realruian/bufferly.git
cd bufferly

swift run Bufferly
bash scripts/build-app.sh
bash scripts/build-dmg.sh
```

Automatic paste-back requires Accessibility permission under System Settings → Privacy & Security → Accessibility. Without it, Bufferly can still restore the selected item to the clipboard for a manual `⌘V`.

## Privacy

- Clipboard history is stored locally in SQLite under `~/Library/Application Support/Bufferly/`.
- Bufferly does not sync or upload clipboard contents.
- Sensitive content can be redacted or excluded from storage.
- Link previews are disabled by default and access the network only when enabled.

## Technology

Swift 6.2 · SwiftUI · AppKit · [GRDB](https://github.com/groue/GRDB.swift) · SQLite · Keychain

## Roadmap and contributing

See [ROADMAP.md](ROADMAP.md) for planned AI workflow features. Contributions are welcome; read [DESIGN.md](DESIGN.md) and [CLAUDE.md](CLAUDE.md) before changing product behavior or visuals.

## License

[MIT](LICENSE) © [Innate Labs](https://github.com/Innate-Labs)
