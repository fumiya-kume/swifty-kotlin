// swift-tools-version: 6.2
import PackageDescription
import Foundation

// Allow CI to compile CompilerCore with -O in debug builds without changing the
// default debug configuration, based on A/B measurements that showed a ~40%
// total job time reduction for the CompilerCore test shards.
let optimizeCompilerCore = ProcessInfo.processInfo.environment["KSWIFTK_OPTIMIZE_COMPILER_CORE"] == "1"

// `-enable-testing` is required for `@testable import CompilerCore` from
// GoldenHarnessSupport in release builds. Optionally add `-O` in debug when CI
// requests it to keep test-shard build times low.
let compilerCoreSwiftSettings: [SwiftSetting] = {
    var settings: [SwiftSetting] = [.unsafeFlags(["-enable-testing"])]
    if optimizeCompilerCore {
        settings.append(.unsafeFlags(["-O"], .when(configuration: .debug)))
    }
    return settings
}()

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
        .target(
            name: "RuntimeABI"
        ),
        .target(
            name: "CompilerCore",
            dependencies: ["RuntimeABI"],
            resources: [
                .copy("Stdlib"),
            ],
            swiftSettings: compilerCoreSwiftSettings
        ),
        .target(
            name: "CompilerBackend",
            dependencies: ["CompilerCore", "RuntimeABI"]
        ),
        .target(
            name: "TestStdlibCache",
            dependencies: ["CompilerCore", "CompilerBackend"]
        ),
        .target(
            name: "CompilerTestSupport",
            dependencies: ["CompilerCore"],
            path: "Sources/CompilerTestSupport"
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
                "GoldenHarnessStableRenderContext.swift",
                "GoldenHarnessSymbolOrigin.swift",
                "GoldenHarnessSyntaxFormat.swift",
            ]
        ),
        .executableTarget(
            name: "KSwiftKCLI",
            dependencies: ["CompilerCore", "CompilerBackend"]
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
            dependencies: ["CompilerCore", "CompilerTestSupport", "GoldenHarnessSupport", "GoldenHarnessWorker", "TestStdlibCache"],
            path: "Tests/CompilerCoreTests",
            exclude: [
                "GoldenCases",
                "Integration/ClassDelegationSmokeTest.kt",
            ]
        ),
        .testTarget(
            name: "CompilerBackendTests",
            dependencies: ["CompilerBackend", "CompilerCore", "CompilerTestSupport", "TestStdlibCache"],
            path: "Tests/CompilerBackendTests",
            exclude: [
                "Fixtures",
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
        ),
        .testTarget(
            name: "LSPServerTests",
            dependencies: ["LSPServer", "CompilerCore"],
            path: "Tests/LSPServerTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
