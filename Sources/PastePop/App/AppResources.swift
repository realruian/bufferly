import Foundation

enum AppResources {
    static func url(
        forResource name: String,
        withExtension extensionName: String,
        subdirectory: String? = nil
    ) -> URL? {
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: extensionName,
            subdirectory: subdirectory
        ) {
            return url
        }

        if
            let resourceBundle = Bundle(
                url: Bundle.main.bundleURL.appendingPathComponent("PastePop_PastePop.bundle", isDirectory: true)
            ),
            let url = resourceBundle.url(
                forResource: name,
                withExtension: extensionName,
                subdirectory: subdirectory
            )
        {
            return url
        }

        return Bundle.module.url(forResource: name, withExtension: extensionName, subdirectory: subdirectory)
    }
}
