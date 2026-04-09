@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesSequenceEdgeCases() throws {
        let source = """
        fun main() {
            val trace = mutableListOf<String>()

            val generated = generateSequence(1) { current ->
                trace.add("next:$current")
                if (current >= 3) null else current + 1
            }

            println(generated.take(2).toList())
            println(trace.joinToString(","))

            trace.clear()

            val filtered = sequenceOf(1, 2, 3, 4)
                .map {
                    trace.add("map:$it")
                    it * 2
                }
                .filter {
                    trace.add("filter:$it")
                    it % 4 == 0
                }

            println(filtered.take(1).toList())
            println(trace.joinToString(","))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2]
                next:1
                [4]
                map:1,filter:2,map:2,filter:4
                """
            )
        }
    }
}
