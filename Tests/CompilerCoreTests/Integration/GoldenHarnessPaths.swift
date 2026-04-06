import Foundation

/// Anchor for resolving `Tests/CompilerCoreTests/GoldenCases`.
/// This file must stay under `Integration/`.
enum GoldenHarnessPaths {
    static var goldenCasesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Integration/
            .deletingLastPathComponent() // CompilerCoreTests/
            .appendingPathComponent("GoldenCases", isDirectory: true)
    }
}
