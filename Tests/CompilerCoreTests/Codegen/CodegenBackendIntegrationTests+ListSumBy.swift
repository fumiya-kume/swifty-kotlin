@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSumByUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.sumBy { it * it })
            println(emptyList<Int>().sumBy { it * 10 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListSumByRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "14\n0\n")
        }
    }
}
