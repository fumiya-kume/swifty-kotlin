@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesArrayEdgeCases() throws {
        let source = """
        fun main() {
            val empty = emptyArray<Int>()
            println(empty.size)

            val single = arrayOf(7)
            println(single[0])

            val many = arrayOf(1, 2, 3)
            println(many[0])
            println(many[1])
            println(many[2])

            val ints = intArrayOf(4, 5, 6)
            println(ints[1])

            val boxed: Array<Any> = arrayOf<Any>(1, "two", 3)
            println(boxed[1])

            try {
                println(many[10])
            } catch (e: Throwable) {
                println("oob-get")
            }

            try {
                many[10] = 99
                println("unexpected-set")
            } catch (e: Throwable) {
                println("oob-set")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                0
                7
                1
                2
                3
                5
                two
                oob-get
                oob-set
                """
                + "\n"
            )
        }
    }
}
