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
        ),
        .executable(
            name: "kswift-lsp",
            targets: ["KSwiftLSPCLI"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CLLVM"
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
        .target(
            name: "LSPServer",
            dependencies: ["CompilerCore"]
        ),
        .executableTarget(
            name: "KSwiftLSPCLI",
            dependencies: ["LSPServer"]
        ),
        .executableTarget(
            name: "GoldenHarnessWorker",
            dependencies: ["GoldenHarnessSupport"],
            path: "Sources/GoldenHarnessWorker"
        ),
        .target(
            name: "Runtime"
        ),
        .testTarget(
            name: "CompilerCoreTests",
            dependencies: ["CompilerCore", "GoldenHarnessSupport", "GoldenHarnessWorker"],
            path: "Tests/CompilerCoreTests",
            exclude: [
                "GoldenCases",
                "Integration/ClassDelegationSmokeTest.kt",
            ]
        ),
        .testTarget(
            name: "RuntimeTests",
            dependencies: ["Runtime", "RuntimeABI"],
            path: "Tests/RuntimeTests"
        ),
        .testTarget(
            name: "RuntimeTestsParallel",
            dependencies: ["Runtime", "RuntimeABI"],
            path: "Tests/RuntimeTestsParallel"
        ),
        .testTarget(
            name: "KSwiftKCLITests",
            dependencies: ["KSwiftKCLI", "CompilerCore"],
            path: "Tests/KSwiftKCLITests"
        )
    ],
    swiftLanguageModes: [.v6]
)
