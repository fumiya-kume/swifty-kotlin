@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenIterableJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.joinToString())
            println(collection.joinToString(" | "))
            println(collection.joinToString(prefix = "<", postfix = ">"))
            println(collection.joinToString(separator = ":", prefix = "[", postfix = "]"))

            val set: Set<String> = setOf("x", "y")
            println(set.joinToString(";"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableJoinToStringRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1, 2, 3\n1 | 2 | 3\n<1, 2, 3>\n[1:2:3]\nx;y\n")
        }
    }
}
