@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesSynchronizedBlocks() throws {
        let source = """
        fun main() {
            val lock = object {}
            var counter = 0
            val result = synchronized(lock) {
                counter += 1
                val nested = synchronized(lock) { counter + 40 }
                nested + 1
            }
            println(result)
            println(counter)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SynchronizedBlocks",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "42\n1\n")
        }
    }

    func testCodegenPropagatesThrowFromSynchronizedBlock() throws {
        let source = """
        fun fail(): Int {
            throw IllegalStateException("boom")
        }

        fun main() {
            val lock = object {}
            try {
                synchronized(lock) { fail() }
                println("unreachable")
            } catch (e: Throwable) {
                println(e.message ?: "missing")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SynchronizedThrow",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "boom\n")
        }
    }
}
