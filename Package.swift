// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpotSentenceTranslate",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "SpotSentenceTranslate",
            targets: ["SpotSentenceTranslate"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "SpotSentenceTranslate"
        ),
        .testTarget(
            name: "SpotSentenceTranslateTests",
            dependencies: ["SpotSentenceTranslate"]
        ),
    ]
)
