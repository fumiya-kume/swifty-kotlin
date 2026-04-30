@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesStringBuilderDeleteAtEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("abc").deleteAt(1).toString())

            val sb = StringBuilder("xy")
            sb.deleteAt(0)
            println(sb.toString())

            val implicit = with(StringBuilder("rust")) {
                deleteAt(1)
                toString()
            }
            println(implicit)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringBuilderDeleteAtEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                ac
                y
                rst
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesStringBuilderDeleteRangeEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("abcdef").deleteRange(1, 4).toString())

            val sb = StringBuilder("012345")
            sb.deleteRange(2, 5)
            println(sb.toString())

            val implicit = with(StringBuilder("abcdef")) {
                deleteRange(0, 2)
                toString()
            }
            println(implicit)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringBuilderDeleteRangeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                aef
                015
                cdef
                """
                + "\n"
            )
        }
    }
}
