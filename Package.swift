// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PastePop",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "PastePop", targets: ["PastePop"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "PastePop",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PastePopTests",
            dependencies: ["PastePop"]
        )
    ]
)
