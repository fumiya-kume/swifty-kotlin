@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenBuildListProducesCorrectly() throws {
        let source = """
        fun main() {
            val list = buildList {
                add(1)
                add(2)
            }
            println(list.size)
            println(list.get(0))
            println(list.get(1))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BuildListRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2\n1\n2\n")
        }
    }

    func testCodegenPrintlnNoArgUsesRuntimeNewlineHelper() throws {
        let source = """
        fun main() {
            println()
            println("after")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrintlnNoArgRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "\nafter\n")
        }
    }

    func testCodegenRequireLazyMessageUsesCapturedValue() throws {
        let source = """
        fun main() {
            val suffix = "value"
            try {
                require(false) { suffix }
            } catch (e: Throwable) {
                println(e)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RequireLazyRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "Throwable(value)\n")
        }
    }

    func testCodegenReadLineEOFReturnsNull() throws {
        let source = """
        fun main() {
            val line = readLine()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadLineEOF",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "\"$1\" </dev/null", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "null\n")
        }
    }

    func testCodegenReadLineEmptyLineReturnsEmptyString() throws {
        let source = """
        fun main() {
            val line = readLine()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadLineEmptyLine",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "printf '\\n' | \"$1\"", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "\n")
        }
    }
}
