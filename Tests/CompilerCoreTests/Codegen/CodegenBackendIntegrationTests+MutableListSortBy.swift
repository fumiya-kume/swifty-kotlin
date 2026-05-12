@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenMutableListSortByMutatesPrimitiveAndObjectSelectorListsInPlace() throws {
        let source = """
        fun main() {
            val ints = mutableListOf(22, 12, 21, 11)
            ints.sortBy { it % 10 }
            println(ints)

            val strings = mutableListOf("b", "a", "c")
            strings.sortBy { it }
            println(strings)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListSortByRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[21, 11, 22, 12]\n[a, b, c]\n")
        }
    }
}
