// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MKVMagic",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MKVMagicCore", targets: ["MKVMagicCore"]),
        .library(name: "MKVMagicSystem", targets: ["MKVMagicSystem"]),
        .library(name: "MKVMagicMedia", targets: ["MKVMagicMedia"]),
        .library(name: "MKVMagicPlanning", targets: ["MKVMagicPlanning"]),
        .library(name: "MKVMagicExecution", targets: ["MKVMagicExecution"]),
        .executable(name: "MKVMagic", targets: ["MKVMagic"]),
        .executable(
            name: "MKVMagicPerformanceProbe",
            targets: ["MKVMagicPerformanceProbe"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5")
    ],
    targets: [
        .target(name: "MKVMagicCore"),
        .target(
            name: "MKVMagicSystem",
            dependencies: ["MKVMagicCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "MKVMagicMedia",
            dependencies: ["MKVMagicCore", "MKVMagicSystem"]
        ),
        .target(
            name: "MKVMagicPlanning",
            dependencies: ["MKVMagicCore"]
        ),
        .target(
            name: "MKVMagicExecution",
            dependencies: [
                "MKVMagicCore", "MKVMagicMedia", "MKVMagicPlanning", "MKVMagicSystem",
            ]
        ),
        .target(
            name: "MKVMagicPerformance",
            dependencies: ["MKVMagicCore", "MKVMagicPlanning"]
        ),
        .executableTarget(
            name: "MKVMagicPerformanceProbe",
            dependencies: ["MKVMagicPerformance"]
        ),
        .executableTarget(
            name: "MKVMagic",
            dependencies: [
                "MKVMagicCore",
                "MKVMagicExecution",
                "MKVMagicMedia",
                "MKVMagicPlanning",
                "MKVMagicSystem",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MKVMagic/Info.plist",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
        .testTarget(
            name: "MKVMagicCoreTests",
            dependencies: ["MKVMagicCore"]
        ),
        .testTarget(
            name: "MKVMagicSystemTests",
            dependencies: ["MKVMagicCore", "MKVMagicSystem"]
        ),
        .testTarget(
            name: "MKVMagicMediaTests",
            dependencies: ["MKVMagicCore", "MKVMagicMedia", "MKVMagicSystem"]
        ),
        .testTarget(
            name: "MKVMagicPlanningTests",
            dependencies: ["MKVMagicCore", "MKVMagicPlanning"]
        ),
        .testTarget(
            name: "MKVMagicExecutionTests",
            dependencies: [
                "MKVMagicCore", "MKVMagicExecution", "MKVMagicMedia", "MKVMagicPlanning",
                "MKVMagicSystem",
            ]
        ),
        .testTarget(
            name: "MKVMagicPerformanceTests",
            dependencies: ["MKVMagicPerformance"]
        ),
        .testTarget(
            name: "MKVMagicAppTests",
            dependencies: ["MKVMagic"]
        ),
    ]
)
