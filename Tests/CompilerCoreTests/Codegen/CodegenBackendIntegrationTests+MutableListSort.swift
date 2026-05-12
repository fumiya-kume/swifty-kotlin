@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenMutableListSortMutatesPrimitiveAndObjectListsInPlace() throws {
        let source = """
        fun main() {
            val ints = mutableListOf(5, 3, 8, 1, 4)
            ints.sort()
            println(ints)

            val strings = mutableListOf("b", "a", "c")
            strings.sort()
            println(strings)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutableListSortRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 3, 4, 5, 8]\n[a, b, c]\n")
        }
    }
}
