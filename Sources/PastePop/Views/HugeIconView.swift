import AppKit
import SwiftUI

/// Hugeicons（stroke-rounded）图标视图：从 Resources/Hugeicons 加载 SVG，
/// 以模板模式渲染，颜色跟随 foregroundStyle；资源缺失时回退 SF Symbol。
struct HugeIconView: View {
    let name: String
    let fallbackSystemName: String

    var body: some View {
        if let image = HugeIconCache.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: fallbackSystemName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

@MainActor
private enum HugeIconCache {
    private static var images: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let image = images[name] {
            return image
        }

        guard
            let url = AppResources.url(
                forResource: name,
                withExtension: "svg",
                subdirectory: "Hugeicons"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = true
        images[name] = image
        return image
    }
}
