@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSliceUsesRangeAndIterableRuntimeHelpers() throws {
        let source = """
        fun printSlices(values: List<Int>) {
            println(values.slice(1..3))
            println(values.slice(listOf(3, 1, 3)))
        }

        fun main() {
            printSlices(listOf(10, 20, 30, 40, 50))
            println(listOf("a", "b", "c").slice(0..1))
            println(listOf("a", "b", "c").slice(listOf(2, 0)))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionSlice",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[20, 30, 40]\n[40, 20, 40]\n[a, b]\n[c, a]\n")
        }
    }
}
