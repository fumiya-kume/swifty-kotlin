@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCharEdgeCases() throws {
        let source = """
        fun main() {
            println('5'.digitToInt())
            println('f'.digitToIntOrNull(16))
            println('G'.digitToIntOrNull(16))

            try {
                println('z'.digitToInt(10))
            } catch (e: Throwable) {
                println("invalid-char")
            }

            try {
                println('5'.digitToInt(1))
            } catch (e: Throwable) {
                println("invalid-radix-low")
            }

            try {
                println('5'.digitToInt(37))
            } catch (e: Throwable) {
                println("invalid-radix-high")
            }

            println('ß'.uppercase())
            println('İ'.lowercase())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharEdgeCases",
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
                15
                null
                invalid-char
                invalid-radix-low
                invalid-radix-high
                SS
                i\u{0307}
                """
            )
        }
    }
}
