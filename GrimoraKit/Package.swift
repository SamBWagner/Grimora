// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GrimoraKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v14),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "GrimoraCore", targets: ["GrimoraCore"]),
        .library(name: "GrimoraUI", targets: ["GrimoraUI"])
    ],
    targets: [
        .target(
            name: "CSQLite",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "GrimoraCore",
            dependencies: ["CSQLite"],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "GrimoraUI",
            dependencies: ["GrimoraCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GrimoraCoreTests",
            dependencies: ["GrimoraCore"]
        ),
        .testTarget(
            name: "GrimoraUITests",
            dependencies: ["GrimoraUI", "GrimoraCore"]
        )
    ]
)
