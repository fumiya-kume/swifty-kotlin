@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCompareByDescendingComparatorSelector() throws {
        let source = """
        fun main() {
            val byLength = compareByDescending<String, Int>(compareBy<Int> { it }) { it.length }
            println(listOf("pear", "fig", "apple").sortedWith(byLength))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CompareByDescendingComparatorSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[apple, pear, fig]\n")
        }
    }

    func testCodegenCompilesComparatorCompositionEdgeCases() throws {
        throw XCTSkip("Comparator composition not yet implemented")
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )

            val chained = compareBy<Entry> { it.group }
                .thenBy { -it.score }
            println(values.sortedWith(chained).map { "${it.group}:${it.score}" })

            println(values.sortedWith(chained.reversed()).map { "${it.group}:${it.score}" })

            val words = listOf("pear", "fig", "apple")
            println(words.sortedWith(reverseOrder()))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparatorCompositionEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1:30, 1:20, 2:40, 2:10]
                [2:10, 2:40, 1:20, 1:30]
                [pear, fig, apple]
                """
                + "\n"
            )
        }
    }
}
