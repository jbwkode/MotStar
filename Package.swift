// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MotStar",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0")
    ],
    targets: [
        .executableTarget(
            name: "MotStar",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/MotStar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MotStarTests",
            dependencies: ["MotStar"],
            path: "Tests/MotStarTests"
        )
    ]
)
