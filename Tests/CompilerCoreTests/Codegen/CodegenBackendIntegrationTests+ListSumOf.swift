@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSumOfUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.sumOf { it * 2 })
            println(emptyList<Int>().sumOf { it * 10 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListSumOfRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "12\n0\n")
        }
    }
}
