@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesTakeIfTakeUnless() throws {
        let source = """
        fun main() {
            // takeIf: returns receiver if predicate is true, else null
            println(10.takeIf { it > 5 })   // 10
            println(10.takeIf { it > 20 })  // null
            println(0.takeIf { it == 0 })   // 0

            // takeUnless: returns receiver if predicate is false, else null
            println(10.takeUnless { it > 5 })   // null
            println(10.takeUnless { it > 20 })  // 10
            println(0.takeUnless { it != 0 })  // 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "TakeIfTakeUnless",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "10\nnull\n0\nnull\n10\n0\n")
        }
    }
}
