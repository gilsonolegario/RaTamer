// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RatTamer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RatTamer", targets: ["RatTamerApp"]),
        .executable(name: "RatDiagnose", targets: ["RatDiagnose"]),
        .executable(name: "RatTest", targets: ["RatTest"]),
        .executable(name: "IconGen", targets: ["IconGen"])
    ],
    targets: [
        .target(
            name: "RatTamerCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "RatTamerApp",
            dependencies: ["RatTamerCore"]
        ),
        .executableTarget(
            name: "RatDiagnose",
            dependencies: ["RatTamerCore"]
        ),
        .executableTarget(
            name: "RatTest",
            dependencies: ["RatTamerCore"]
        ),
        .executableTarget(
            name: "IconGen",
            dependencies: []
        ),
        .testTarget(
            name: "RatTamerCoreTests",
            dependencies: ["RatTamerCore"]
        ),
    ]
)
