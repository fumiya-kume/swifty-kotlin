@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesScopeFunctions() throws {
        let source = """
        class Builder {
            var x: Int = 0
            var y: Int = 0
        }

        fun main() {
            println("Hello".let { it.length })
            println("Hello".run { length })
            val built = Builder().apply {
                x = 10
                y = 20
            }
            println(built.x + built.y)
            println("Hello".also { println(it.length) }.length)
            println(with("Hello") { length })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ScopeFunctions",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "5\n5\n30\n5\n5\n5\n")
        }
    }
}
