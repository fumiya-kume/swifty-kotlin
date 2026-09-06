#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Compiles and links `source`, then runs it with `shellInvocation` wrapping
/// the binary (`"$1"` refers to the compiled executable), returning
/// normalized stdout. Shared by the `readLine`/`readln`/`readlnOrNull`
/// stdin tests below, which differ only in the shell-side stdin redirect.
private func runWithStdin(_ source: String, moduleName: String, shellInvocation: String) throws -> String {
    var normalizedStdout = ""
    try withTemporaryFile(contents: source) { path in
        let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let ctx = try runCodegenPipeline(
            inputPath: path,
            moduleName: moduleName,
            emit: .executable,
            outputPath: outputBase
        )
        try LinkPhase().run(ctx)

        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", shellInvocation, "sh", outputBase]
        )
        normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
    }
    return normalizedStdout
}

@Suite
struct CodegenBackendIOHelpersTests {

    @Test
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

        try assertKotlinOutput(source, moduleName: "BuildListRuntime", expected: "2\n1\n2\n")
    }

    @Test
    func testCodegenBuildStringCapacityProducesCorrectly() throws {
        let source = """
        fun main() {
            val positional = buildString(16) {
                append("hello")
                append(" world")
            }
            val named = buildString(capacity = 4) {
                append("cap")
            }
            println(positional)
            println(named)
            try {
                println(buildString(-1) { append("bad") })
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildStringCapacityRuntime", expected: "hello world\ncap\ncaught\n")
    }

    @Test
    func testCodegenBuildStringAppendTypedValuesProducesCorrectly() throws {
        let source = """
        fun main() {
            val text = buildString {
                append("value=")
                append('A')
                append(" ")
                append(true)
                append(" ")
                append(42)
                append(" ")
                append(100L)
                append(" ")
                append(3.5f)
                append(" ")
                append(2.25)
                append(" ")
                append(null)
            }
            println(text)
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildStringAppendTypedValuesRuntime", expected: "value=A true 42 100 3.5 2.25 null\n")
    }

    @Test
    func testCodegenBuildStringBuilderProducesMutableBuilder() throws {
        let source = """
        fun main() {
            val sb = buildStringBuilder {
                append("hello")
                appendLine()
                appendRange("world!", 0, 5)
            }
            sb.append("!")
            println(sb.toString())
            try {
                println(buildStringBuilder(-1) { append("bad") }.toString())
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildStringBuilderRuntime", expected: "hello\nworld!\ncaught\n")
    }

    @Test
    func testCodegenPrintlnNoArgUsesRuntimeNewlineHelper() throws {
        let source = """
        fun main() {
            println()
            println("after")
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintlnNoArgRuntime", expected: "\nafter\n")
    }

    /// KSP-415 follow-up: println's class-typed argument rewrite used to call
    /// toString() unconditionally regardless of nullability, crashing on a
    /// null receiver instead of printing "null".
    @Test
    func testCodegenPrintlnNullableClassNullReceiverPrintsNull() throws {
        let source = """
        class Foo(val x: Int) {
            override fun toString(): String = "Foo(" + x + ")"
        }
        fun main() {
            val f: Foo? = null
            println(f)
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintlnNullableClassNullRuntime", expected: "null\n")
    }

    /// Companion to the null case above: a non-null nullable-typed receiver
    /// must still resolve the custom toString() (not fall back to the
    /// generic "<object 0x...>" representation).
    @Test
    func testCodegenPrintlnNullableClassNonNullReceiverCallsToString() throws {
        let source = """
        class Foo(val x: Int) {
            override fun toString(): String = "Foo(" + x + ")"
        }
        fun main() {
            val f: Foo? = Foo(42)
            println(f)
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintlnNullableClassNonNullRuntime", expected: "Foo(42)\n")
    }

    @Test
    func testCodegenPrintlnNullableDataClassNullReceiverPrintsNull() throws {
        let source = """
        data class Point(val x: Int, val y: Int)
        fun main() {
            val p: Point? = null
            println(p)
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintlnNullableDataClassNullRuntime", expected: "null\n")
    }

    @Test
    func testCodegenPrintlnNullableDataClassNonNullReceiverUsesGeneratedToString() throws {
        let source = """
        data class Point(val x: Int, val y: Int)
        fun main() {
            val p: Point? = Point(1, 2)
            println(p)
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintlnNullableDataClassNonNullRuntime", expected: "Point(x=1, y=2)\n")
    }

    @Test
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

        try assertKotlinOutput(source, moduleName: "RequireLazyRuntime", expected: "java.lang.IllegalArgumentException: value\n")
    }

    @Test
    func testCodegenReadLineEOFReturnsNull() throws {
        let source = """
        fun main() {
            val line = readLine()
            println(line)
        }
        """

        let normalizedStdout = try runWithStdin(source, moduleName: "ReadLineEOF", shellInvocation: "\"$1\" </dev/null")
        #expect(normalizedStdout == "null\n")
    }

    @Test
    func testCodegenReadLineEmptyLineReturnsEmptyString() throws {
        let source = """
        fun main() {
            val line = readLine()
            println(line)
        }
        """

        let normalizedStdout = try runWithStdin(source, moduleName: "ReadLineEmptyLine", shellInvocation: "printf '\\n' | \"$1\"")
        #expect(normalizedStdout == "\n")
    }

    @Test
    func testCodegenReadlnReturnsInputLine() throws {
        let source = """
        fun main() {
            val line = readln()
            println(line)
        }
        """

        let normalizedStdout = try runWithStdin(source, moduleName: "ReadlnInput", shellInvocation: "echo hello | \"$1\"")
        #expect(normalizedStdout == "hello\n")
    }

    @Test
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

        let normalizedStdout = try runWithStdin(source, moduleName: "ReadlnEOF", shellInvocation: "\"$1\" </dev/null")
        #expect(
            normalizedStdout.contains("EOF"),
            "Expected EOF-related message, got: \(normalizedStdout)"
        )
    }

    @Test
    func testCodegenReadlnOrNullReturnsInputLine() throws {
        let source = """
        fun main() {
            val line = readlnOrNull()
            println(line)
        }
        """

        let normalizedStdout = try runWithStdin(source, moduleName: "ReadlnOrNullInput", shellInvocation: "echo hello | \"$1\"")
        #expect(normalizedStdout == "hello\n")
    }

    @Test
    func testCodegenReadlnOrNullEOFReturnsNull() throws {
        let source = """
        fun main() {
            val line = readlnOrNull()
            println(line)
        }
        """

        let normalizedStdout = try runWithStdin(source, moduleName: "ReadlnOrNullEOF", shellInvocation: "\"$1\" </dev/null")
        #expect(normalizedStdout == "null\n")
    }

    @Test
    func testCodegenPrintNoArgIsNoOp() throws {
        let source = """
        fun main() {
            print()
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintNoArgRuntime", expected: "done\n")
    }
}
#endif
