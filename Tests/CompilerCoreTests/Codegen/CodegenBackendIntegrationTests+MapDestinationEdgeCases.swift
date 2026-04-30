@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenMapKeysToUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/map_mapkeysto.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapKeysToDestination",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                zero
                zero
                one
                two
                3
                """ + "\n"
            )
        }
    }

    func testCodegenMapValuesToUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/map_mapvaluesto.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapValuesToDestination",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                5
                5
                11
                21
                3
                """ + "\n"
            )
        }
    }
}
