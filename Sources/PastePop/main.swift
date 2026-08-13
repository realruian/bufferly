import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
// Dock 是否显示由用户设置决定；隐藏 Dock 时仍以菜单栏后台 App 运行。
app.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
app.run()
