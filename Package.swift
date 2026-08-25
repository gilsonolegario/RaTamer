// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RaTamer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RaTamer", targets: ["RaTamerApp"]),
        .executable(name: "RatDiagnose", targets: ["RatDiagnose"]),
        .executable(name: "RatTest", targets: ["RatTest"]),
        .executable(name: "IconGen", targets: ["IconGen"])
    ],
    targets: [
        .target(
            name: "RaTamerCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "RaTamerApp",
            dependencies: ["RaTamerCore"]
        ),
        .executableTarget(
            name: "RatDiagnose",
            dependencies: ["RaTamerCore"]
        ),
        .executableTarget(
            name: "RatTest",
            dependencies: ["RaTamerCore"]
        ),
        .executableTarget(
            name: "IconGen",
            dependencies: []
        ),
        .testTarget(
            name: "RaTamerCoreTests",
            dependencies: ["RaTamerCore"]
        ),
    ]
)
