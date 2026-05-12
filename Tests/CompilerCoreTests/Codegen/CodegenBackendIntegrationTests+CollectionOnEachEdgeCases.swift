@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionOnEachRunsActionAndReturnsReceiver() throws {
        let source = """
        fun consume(values: List<Int>) {
            var trace = ""
            val returned = values.onEach { trace += "$it;" }
            println(trace)
            println(returned)
        }

        fun main() {
            val values = listOf(1, 2, 3)
            var localTrace = ""
            val localReturned = values.onEach { localTrace += "${it * 10};" }
            println(localTrace)
            println(localReturned)
            consume(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionOnEachEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "10;20;30;\n[1, 2, 3]\n1;2;3;\n[1, 2, 3]\n")
        }
    }
}
