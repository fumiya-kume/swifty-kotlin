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

    func testCodegenCompilesNullableAutoCloseableUse() throws {
        let source = """
        fun main() {
            var closed = 0
            val missing: AutoCloseable? = null
            val missingResult = missing.use { resource ->
                if (resource == null) "missing" else "bad"
            }
            println(missingResult)
            println("closed:" + closed)

            val present: AutoCloseable? = AutoCloseable {
                closed = closed + 1
                println("closed:" + closed)
            }
            val presentResult = present.use { resource ->
                if (resource == null) "bad" else "present"
            }
            println(presentResult)
            println("after:" + closed)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "NullableAutoCloseableUse",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "missing\nclosed:0\nclosed:1\npresent\nafter:1\n")
        }
    }
}
