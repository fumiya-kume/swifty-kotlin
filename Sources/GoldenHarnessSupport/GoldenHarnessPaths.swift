import Foundation

/// Anchor for resolving `Tests/CompilerCoreTests/GoldenCases`.
enum GoldenHarnessPaths {
    static var goldenCasesDirectory: URL {
        let fileManager = FileManager.default
        let cwdCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Tests/CompilerCoreTests/GoldenCases", isDirectory: true)
        if fileManager.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/CompilerCoreTests/GoldenCases", isDirectory: true)
    }
}
