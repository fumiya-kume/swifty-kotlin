// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KSwiftK",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "CompilerCore",
            targets: ["CompilerCore"]
        ),
        .library(
            name: "KotlinRuntime",
            targets: ["Runtime"]
        ),
        .executable(
            name: "kswiftc",
            targets: ["KSwiftKCLI"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CLLVM"
        ),
        .systemLibrary(
            name: "CSQLite"
        ),
        .target(
            name: "RuntimeABI"
        ),
        .target(
            name: "CompilerCore",
            dependencies: ["CLLVM", "RuntimeABI"]
        ),
        .target(
            name: "GoldenHarnessSupport",
            dependencies: ["CompilerCore"],
            path: "Sources/GoldenHarnessSupport",
            sources: [
                "GoldenHarnessAPI.swift",
                "GoldenHarnessCaseDiscovery.swift",
                "GoldenHarnessDump.swift",
                "GoldenHarnessExprFormat.swift",
                "GoldenHarnessGoldenFileIO.swift",
                "GoldenHarnessPipeline.swift",
                "GoldenHarnessGoldenSuiteKind.swift",
                "GoldenHarnessPaths.swift",
                "GoldenHarnessSemaFormat.swift",
                "GoldenHarnessSyntaxFormat.swift",
            ]
        ),
        .executableTarget(
            name: "KSwiftKCLI",
            dependencies: ["CompilerCore"]
        ),
        .executableTarget(
            name: "GoldenHarnessWorker",
            dependencies: ["GoldenHarnessSupport"],
            path: "Sources/GoldenHarnessWorker"
        ),
        .target(
            name: "Runtime",
            dependencies: ["CSQLite"]
        ),
        .testTarget(
            name: "CompilerCoreTests",
            dependencies: ["CompilerCore", "GoldenHarnessSupport", "GoldenHarnessWorker"],
            path: "Tests/CompilerCoreTests",
            exclude: [
                "GoldenCases",
                "Integration/ClassDelegationSmokeTest.kt",
                "Integration/GoldenHarnessCaseDiscovery.swift",
                "Integration/GoldenHarnessDump.swift",
                "Integration/GoldenHarnessExprFormat.swift",
                "Integration/GoldenHarnessGoldenFileIO.swift",
                "Integration/GoldenHarnessGoldenSuiteKind.swift",
                "Integration/GoldenHarnessPaths.swift",
                "Integration/GoldenHarnessSemaFormat.swift",
                "Integration/GoldenHarnessSyntaxFormat.swift",
            ]
        ),
        .testTarget(
            name: "RuntimeTests",
            dependencies: ["Runtime", "RuntimeABI"],
            path: "Tests/RuntimeTests"
        ),
        .testTarget(
            name: "KSwiftKCLITests",
            dependencies: ["KSwiftKCLI", "CompilerCore"],
            path: "Tests/KSwiftKCLITests"
        )
    ],
    swiftLanguageModes: [.v6]
)
