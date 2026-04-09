@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesStringEdgeCases() throws {
        let source = """
        fun dumpLines(prefix: String, values: List<String>) {
            println("$prefix:${values.joinToString("|")}")
        }

        fun main() {
            println("hello".substringBefore("."))
            println("hello.world.kt".substringBefore("."))
            println("hello.world.kt".substringBeforeLast("."))
            println("nodelem".substringBefore(":"))

            println("hello".replaceFirstChar { 'H' })
            println("beta".replaceFirstChar { 'B' })
            println("".replaceFirstChar { 'X' })

            dumpLines("lines-empty", "".lines())
            dumpLines("lines-ascii", "a\\nb\\n".lines())
            dumpLines("lines-unicode", "こんにちは\\n世界".lines())

            dumpLines("seq-empty", "".lineSequence().toList())
            dumpLines("seq-mixed", "a\\r\\nb\\nc".lineSequence().toList())
            dumpLines("seq-head-tail", "\\nalpha\\n".lineSequence().toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                hello
                hello
                hello.world
                nodelem
                Hello
                Beta
                
                lines-empty:
                lines-ascii:a|b|
                lines-unicode:こんにちは|世界
                seq-empty:
                seq-mixed:a|b|c
                seq-head-tail:|alpha|
                """
            )
        }
    }
}
