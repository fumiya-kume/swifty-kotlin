@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionOnEachIndexedRunsActionAndReturnsReceiver() throws {
        let source = """
        fun consume(values: List<Int>) {
            var trace = ""
            val returned = values.onEachIndexed { index, value -> trace += "$index:$value;" }
            println(trace)
            println(returned)
        }

        fun main() {
            val values = listOf(10, 20, 30)
            var localTrace = ""
            val localReturned = values.onEachIndexed { index, value -> localTrace += "$index=${value / 10};" }
            println(localTrace)
            println(localReturned)
            consume(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionOnEachIndexedEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0=1;1=2;2=3;\n[10, 20, 30]\n0:10;1:20;2:30;\n[10, 20, 30]\n")
        }
    }
}
