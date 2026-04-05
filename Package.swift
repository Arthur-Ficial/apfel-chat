// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "apfel-chat",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "apfel-chat",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "./Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "ApfelChatTests",
            dependencies: ["apfel-chat"],
            path: "Tests"
        ),
    ]
)
