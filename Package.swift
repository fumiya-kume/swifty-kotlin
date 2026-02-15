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
        )
    ]
)
