@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCharEdgeCases() throws {
        let source = """
        fun main() {
            println('5'.digitToInt())
            println('9'.digitToInt())
            println('a'.digitToIntOrNull())

            try {
                println('z'.digitToInt())
            } catch (e: Throwable) {
                println("invalid-char")
            }

            println('ß'.uppercase())
            println('ß'.uppercaseChar())
            println('İ'.lowercase())
            println('İ'.lowercaseChar())
            println('ǆ'.titlecaseChar())
            println('ß'.titlecaseChar())
            println('A'.isDefined())
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
                9
                null
                invalid-char
                SS
                ß
                i\u{0307}
                i
                ǅ
                ß
                true
                """
                + "\n"
            )
        }
    }
}
