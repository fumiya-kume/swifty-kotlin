@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesContractEdgeCases() throws {
        let source = """
        fun main() {
            val nullable: String? = "hello"
            require(nullable != null)
            println(nullable.length)

            val anyValue: Any = "world"
            check(anyValue is String)
            println(anyValue.uppercase())

            val left: String? = "ab"
            val right: String? = "cd"
            require(left != null && right != null)
            println(left.length + right.length)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ContractEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                5
                WORLD
                4
                """ + "\n"
            )
        }
    }
}
