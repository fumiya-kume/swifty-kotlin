@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListLastIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val ints: List<Int> = listOf(1, 2, 3, 2)
            println(ints.lastIndexOf(2))
            println(ints.lastIndexOf(4))

            val words: List<String> = listOf("alpha", "beta", "alpha")
            println(words.lastIndexOf("alpha"))
            println(words.lastIndexOf("gamma"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionLastIndexOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n-1\n2\n-1\n")
        }
    }
}
