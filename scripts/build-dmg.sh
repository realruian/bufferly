#!/usr/bin/env bash
# 把 PastePop 打包成可分发的 .dmg（拖到 Applications 安装）。
#
# 注意：本机若无 Developer ID 证书，仅做 ad-hoc 签名 —— 本机可运行，
# 但首次打开需右键「打开」绕过 Gatekeeper；正经零警告分发需 Developer ID + 公证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/PastePop.app"
DMG="$ROOT/.build/PastePop.dmg"
RW_DMG="$ROOT/.build/PastePop-rw.dmg"
STAGING="$ROOT/.build/dmg-staging"
BACKGROUND="$ROOT/.build/dmg-background.png"
VOLNAME="PastePop"
MOUNT_DIR=""

cleanup() {
  if [[ -n "${MOUNT_DIR:-}" && -d "${MOUNT_DIR:-}" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  if [[ -n "${MOUNT_DIR:-}" ]]; then
    rmdir "$MOUNT_DIR" 2>/dev/null || true
  fi
  rm -rf "$STAGING" "$RW_DMG"
}

trap cleanup EXIT

# 1. 构建并签名 release .app
bash "$ROOT/scripts/build-app.sh"

# 2. 准备 DMG 内容：App + Applications 快捷方式 + 安装背景
rm -rf "$STAGING" "$DMG" "$RW_DMG" "$BACKGROUND"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

swift - "$BACKGROUND" <<'SWIFT'
import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 720, height: 440)
let image = NSImage(size: size)

image.lockFocus()

NSColor.windowBackgroundColor.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let accent = NSColor(calibratedRed: 0.00, green: 0.37, blue: 0.78, alpha: 1)
let muted = NSColor.secondaryLabelColor

func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSAttributedString(string: text, attributes: attributes).draw(
        in: NSRect(x: point.x, y: point.y, width: 720 - point.x * 2, height: 48)
    )
}

draw("安装 PastePop", at: NSPoint(x: 40, y: 348), size: 28, weight: .semibold, color: .labelColor)
draw("把左侧应用拖到右侧 Applications 文件夹", at: NSPoint(x: 40, y: 314), size: 15, weight: .regular, color: muted)

accent.withAlphaComponent(0.16).setFill()
let pill = NSBezierPath(roundedRect: NSRect(x: 248, y: 190, width: 224, height: 56), xRadius: 28, yRadius: 28)
pill.fill()

accent.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 282, y: 218))
arrow.line(to: NSPoint(x: 438, y: 218))
arrow.stroke()

let head = NSBezierPath()
head.lineWidth = 4
head.lineCapStyle = .round
head.move(to: NSPoint(x: 420, y: 234))
head.line(to: NSPoint(x: 440, y: 218))
head.line(to: NSPoint(x: 420, y: 202))
head.stroke()

draw("Drag to Install", at: NSPoint(x: 40, y: 104), size: 13, weight: .medium, color: muted)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    throw NSError(domain: "PastePopDMG", code: 1)
}

try png.write(to: outputURL)
SWIFT

# 3. 先生成可写 DMG，挂载后设置 Finder 背景和图标位置
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -ov -format UDRW \
  "$RW_DMG"

MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -noverify >/dev/null
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND" "$MOUNT_DIR/.background/background.png"

if osascript <<OSA
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_DIR" as alias
  set backgroundImage to POSIX file "$MOUNT_DIR/.background/background.png" as alias
  open dmgFolder
  set current view of container window of dmgFolder to icon view
  set toolbar visible of container window of dmgFolder to false
  set statusbar visible of container window of dmgFolder to false
  set the bounds of container window of dmgFolder to {120, 120, 840, 560}
  set arrangement of icon view options of container window of dmgFolder to not arranged
  set icon size of icon view options of container window of dmgFolder to 96
  set background picture of icon view options of container window of dmgFolder to backgroundImage
  set position of item "PastePop.app" of dmgFolder to {190, 230}
  set position of item "Applications" of dmgFolder to {530, 230}
  close container window of dmgFolder
  open dmgFolder
  update dmgFolder without registering applications
  delay 1
end tell
OSA
then
  echo "   已设置 DMG 安装背景和图标位置"
else
  echo "   ⚠️ Finder 布局设置失败，继续生成基础 DMG"
fi

hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR" 2>/dev/null || true
MOUNT_DIR=""

# 4. 压缩成最终 DMG
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -ov

rm -rf "$STAGING" "$RW_DMG" "$BACKGROUND"

echo ""
echo "✅ 完成：$DMG"
du -h "$DMG" | cut -f1 | sed 's/^/   体积：/'
