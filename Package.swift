// swift-tools-version: 5.9
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
        .target(
            name: "CompilerCore"
        ),
        .executableTarget(
            name: "KSwiftKCLI",
            dependencies: ["CompilerCore"]
        ),
        .target(
            name: "Runtime"
        ),
        .testTarget(
            name: "CompilerCoreTests",
            dependencies: ["CompilerCore"],
            path: "Tests/CompilerCoreTests"
        )
    ]
)
