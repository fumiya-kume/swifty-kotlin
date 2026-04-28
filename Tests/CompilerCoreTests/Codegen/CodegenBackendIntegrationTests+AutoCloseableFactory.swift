@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesAutoCloseableFactory() throws {
        let source = """
        fun main() {
            var closed = 0
            val resource: AutoCloseable = AutoCloseable {
                closed = closed + 1
                println("closed:" + closed)
            }
            resource.close()
            println("after-close:" + closed)
            AutoCloseable {
                println("use-close")
            }.use {
                println("use-body")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "AutoCloseableFactory",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "closed:1\nafter-close:1\nuse-body\nuse-close\n")
        }
    }
}
