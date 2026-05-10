@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenMutableListSortByDescendingMutatesPrimitiveAndObjectSelectorListsInPlace() throws {
        let source = """
        fun main() {
            val ints = mutableListOf(21, 12, 22, 11)
            ints.sortByDescending { it % 10 }
            println(ints)

            val strings = mutableListOf("b", "a", "c")
            strings.sortByDescending { it }
            println(strings)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListSortByDescendingRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[12, 22, 21, 11]\n[c, b, a]\n")
        }
    }
}
