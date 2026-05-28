@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// STDLIB-TEXT-FN-068: End-to-end verification that `String.slice` lowers to
    /// `kk_string_slice` (IntRange overload) and `kk_string_slice_iterable`
    /// (Iterable<Int> overload), and that the resulting executable produces the
    /// expected substring on stdout.
    func testCodegenStringSliceUsesRangeAndIterableRuntimeHelpers() throws {
        let source = """
        fun printSlices() {
            val s = "abcdef"
            println(s.slice(1..3))
            println(s.slice(listOf(0, 2, 4)))
            println("Kotlin".slice(0..2))
            println("Kotlin".slice(listOf(5, 0, 3)))
        }

        fun main() {
            printSlices()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringSlice",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "bcd\nace\nKot\nnKl\n")
        }
    }
}
