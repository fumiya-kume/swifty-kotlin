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
            XCTAssertEqual(normalizedStdout, "Throwable(IllegalArgumentException: value)\n")
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

    // MARK: - readln / readlnOrNull (STDLIB-658, STDLIB-659)

    func testCodegenReadlnReturnsInputLine() throws {
        let source = """
        fun main() {
            val line = readln()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnInput",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "echo hello | \"$1\"", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hello\n")
        }
    }

    func testCodegenReadlnEOFThrows() throws {
        let source = """
        fun main() {
            try {
                val line = readln()
                println(line)
            } catch (e: RuntimeException) {
                println(e.message)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnEOF",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "\"$1\" </dev/null", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertTrue(
                normalizedStdout.contains("EOF"),
                "Expected EOF-related message, got: \(normalizedStdout)"
            )
        }
    }

    func testCodegenReadlnOrNullReturnsInputLine() throws {
        let source = """
        fun main() {
            val line = readlnOrNull()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnOrNullInput",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "echo hello | \"$1\"", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hello\n")
        }
    }

    func testCodegenReadlnOrNullEOFReturnsNull() throws {
        let source = """
        fun main() {
            val line = readlnOrNull()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnOrNullEOF",
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

    // MARK: - print() 0-arg (STDLIB-572)

    func testCodegenPrintNoArgIsNoOp() throws {
        let source = """
        fun main() {
            print()
            println("done")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrintNoArgRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "done\n")
        }
    }
}
