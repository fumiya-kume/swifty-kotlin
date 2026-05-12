@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListOfNotNullFiltersNullElements() throws {
        let source = """
        fun maybeInt(value: Int): Int? = if (value > 0) value else null
        fun maybeString(value: String?): String? = value

        fun main() {
            val ints = listOfNotNull(maybeInt(1), maybeInt(-1), 2)
            println(ints)
            println(ints.size)

            val words = listOfNotNull(maybeString("alpha"), maybeString(null), "beta")
            println(words)
            println(words.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionListOfNotNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1, 2]\n2\n[alpha, beta]\n2\n")
        }
    }
}
