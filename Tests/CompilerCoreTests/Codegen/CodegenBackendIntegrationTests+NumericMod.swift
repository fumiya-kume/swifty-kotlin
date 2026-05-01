@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesNumericModOverloadMatrix() throws {
        let source = """
        fun main() {
            println((-7).mod(3))
            println(7.mod(-3))
            println((-7).mod(-3))
            println(7L.mod(3))
            println(7.mod(3L))
            println(10uL.mod(4u))
            println((-7.0).mod(3.0))
            println(7.0.mod(-3.0))
            println((-7.0f).mod(3.0f))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "NumericModOverloadMatrix",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                2
                -2
                -1
                1
                1
                2
                2.0
                -2.0
                2.0
                """
                + "\n"
            )
        }
    }
}
