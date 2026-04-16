@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesEnumEdgeCoverage() throws {
        throw XCTSkip("Enum entries/enumValues not yet implemented")
        let source = """
        enum class Direction {
            NORTH,
            SOUTH,
        }

        fun main() {
            println(Direction.entries)
            println(enumValues<Direction>().toList())
            println(enumValueOf<Direction>("NORTH"))
            println(Direction.SOUTH.name)
            println(Direction.SOUTH.ordinal)

            try {
                println(enumValueOf<Direction>("WEST"))
            } catch (e: Throwable) {
                println("invalid-enum-name")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EnumEdgeCoverage",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [NORTH, SOUTH]
                [NORTH, SOUTH]
                NORTH
                SOUTH
                1
                invalid-enum-name
                """
                + "\n"
            )
        }
    }
}
