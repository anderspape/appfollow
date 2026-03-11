// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusTimer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FocusTimer", targets: ["FocusTimer"])
    ],
    dependencies: [
        .package(url: "https://github.com/danielsaidi/EmojiKit.git", from: "2.3.1"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.5.0")
    ],
    targets: [
        .executableTarget(
            name: "FocusTimer",
            dependencies: [
                .product(name: "EmojiKit", package: "EmojiKit"),
                .product(name: "Lottie", package: "lottie-spm")
            ],
            path: "Sources/FocusTimer",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker", "-sectcreate",
                        "-Xlinker", "__TEXT",
                        "-Xlinker", "__info_plist",
                        "-Xlinker", "Sources/FocusTimer/Resources/AppTargetInfo.plist"
                    ],
                    .when(platforms: [.macOS])
                )
            ]
        ),
        .testTarget(
            name: "FocusTimerTests",
            dependencies: ["FocusTimer"],
            path: "Tests/FocusTimerTests"
        )
    ]
)
