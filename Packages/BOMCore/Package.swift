// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BOMCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "BOMCore", targets: ["BOMCore"]),
        .executable(name: "bbom-bench", targets: ["bbom-bench"]),
    ],
    targets: [
        .target(name: "BOMCore"),
        .executableTarget(name: "bbom-bench", dependencies: ["BOMCore"]),
        .testTarget(name: "BOMCoreTests", dependencies: ["BOMCore"]),
    ]
)
