@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesComparisonsEdgeCases() throws {
        let source = """
        data class User(val name: String, val age: Int)

        fun main() {
            println(compareValues(1, 2))
            println(compareValues(2, 2))
            println(compareValues(3, 2))

            val users = listOf(
                User("bob", 20),
                User("alice", 20),
                User("carol", 18),
            )
            val sorted = users.sortedWith(compareBy<User> { it.age }.thenBy { it.name })
            println(sorted.map { "${it.age}:${it.name}" })

            val nullable = listOf(2, null, 1)
            println(nullable.sortedWith(compareBy<Int?> { it }.nullsFirst()))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparisonsEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                -1
                0
                1
                [18:carol, 20:alice, 20:bob]
                [null, 1, 2]
                """
            )
        }
    }
}
