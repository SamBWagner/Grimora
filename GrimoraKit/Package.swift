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
        .library(name: "GrimoraUI", targets: ["GrimoraUI"]),
        .library(name: "GrimoraDataPipeline", targets: ["GrimoraDataPipeline"]),
        .library(name: "GrimoraEngineKit", targets: ["GrimoraEngineKit"]),
        .executable(name: "grimora-data-engine", targets: ["GrimoraDataEngine"]),
        .executable(name: "grimora-data-api", targets: ["GrimoraDataAPI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.25.0"
        ),
        .package(
            url: "https://github.com/soto-project/soto.git",
            from: "7.14.0"
        ),
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            from: "4.5.0"
        )
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
            name: "CZlib",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "GrimoraCore",
            dependencies: [
                "CSQLite",
                "CZlib",
                .product(name: "Crypto", package: "swift-crypto")
            ],
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
        .target(
            name: "GrimoraDataPipeline",
            dependencies: ["GrimoraCore"]
        ),
        .target(
            name: "GrimoraEngineKit",
            dependencies: [
                "GrimoraCore",
                "GrimoraDataPipeline",
                .product(name: "SotoS3", package: "soto")
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "GrimoraDataEngine",
            dependencies: [
                "GrimoraCore",
                "GrimoraEngineKit"
            ]
        ),
        .executableTarget(
            name: "GrimoraDataAPI",
            dependencies: [
                "GrimoraCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "SotoS3", package: "soto")
            ]
        ),
        .testTarget(
            name: "GrimoraCoreTests",
            dependencies: ["GrimoraCore"]
        ),
        .testTarget(
            name: "GrimoraDataPipelineTests",
            dependencies: ["GrimoraCore", "GrimoraDataPipeline"]
        ),
        .testTarget(
            name: "GrimoraDataAPITests",
            dependencies: [
                "GrimoraCore",
                "GrimoraDataAPI",
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ]
        ),
        .testTarget(
            name: "GrimoraDataEngineTests",
            dependencies: ["GrimoraCore", "GrimoraEngineKit"]
        ),
        .testTarget(
            name: "GrimoraUITests",
            dependencies: ["GrimoraUI", "GrimoraCore"]
        )
    ]
)
