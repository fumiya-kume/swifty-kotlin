#if canImport(Testing)
// TEST-CHAR-019: End-to-end execution tests for Char arithmetic and CharRange.forEach.
// Char.plus(Int) and Char.minus(Int) have no dedicated runtime symbol — they lower to
// kk_op_add/kk_op_sub via the IR, so codegen is the only layer that can verify them.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCharExecutionTests {

    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testNullableCharCodeUnboxesTheReceiverAndBoxesTheIntResult() throws {
        try assertKotlinOutput(
            """
            fun code(value: Char?): Int? = value?.code
            fun main() {
                val value: Char? = 'a'
                val erased: Any? = value?.code
                println(erased is Int)
                println(erased)
                println(code('\\u0000'))
                println(code('\\uD83D'))
                println(code('\\uDE00'))
                println(code('\\uFFFF'))
                println(code(null))
                println(value?.code == 97)
            }
            """,
            moduleName: "NullableCharCode",
            expected: "true\n97\n0\n55357\n56832\n65535\nnull\ntrue\n"
        )
    }

    @Test
    func testCodegenCharIsISOControlBoundaries() throws {
        let source = """
        fun main() {
            println('\\u001f'.isISOControl())
            println(' '.isISOControl())
            println('\\u007f'.isISOControl())
            println('\\u009f'.isISOControl())
            println('\\u00a0'.isISOControl())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharIsISOControlExecution",
            expected:
                """
                true
                false
                true
                true
                false
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharPlusInt() throws {
        // Char.plus(Int) lowers to kk_op_add; .code extracts the result as Int for safe printing
        let source = """
        fun main() {
            println(('a' + 1).code)
            println(('A' + 25).code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharPlusIntExecution",
            expected:
                """
                98
                90
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharMinusInt() throws {
        // Char.minus(Int) lowers to kk_op_sub; result type is Char, printed via .code
        let source = """
        fun main() {
            println(('b' - 1).code)
            println(('z' - 25).code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharMinusIntExecution",
            expected:
                """
                97
                97
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharMinusChar() throws {
        // Char.minus(Char) dispatches to kk_char_minus and returns Int
        let source = """
        fun main() {
            println('b' - 'a')
            println('a' - 'b')
            println('z' - 'a')
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharMinusCharExecution",
            expected:
                """
                1
                -1
                25
                """
                + "\n"
        )
    }

    @Test
    func testCodegenStringGetByIndex() throws {
        // String.get dispatches to kk_string_get; result is Char, printed via .code
        let source = """
        fun main() {
            println("hello"[1].code)
            println("world"[0].code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringGetIndexExecution",
            expected:
                """
                101
                119
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharRangeForEachAscending() throws {
        let source = """
        fun main() {
            ('a'..'e').forEach { c -> println(c.code) }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharRangeForEachAscending",
            expected:
                """
                97
                98
                99
                100
                101
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharRangeForEachEmpty() throws {
        // ('e'..'a') with implicit step=1 — first > last, so forEach iterates zero times
        let source = """
        fun main() {
            ('e'..'a').forEach { c -> println(c.code) }
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "CharRangeForEachEmpty", expected: "done\n")
    }

    @Test
    func testCodegenCharProgressionForEachDescending() throws {
        // 'e' downTo 'a' produces a CharProgression with step=-1
        let source = """
        fun main() {
            ('e' downTo 'a').forEach { c -> println(c.code) }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharProgressionForEachDescending",
            expected:
                """
                101
                100
                99
                98
                97
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharIsJavaIdentifierPartTypicalValues() throws {
        // Covers letters, digits, connector punctuation (_), currency symbol ($),
        // and characters that are NOT valid identifier parts (space, operator).
        let source = """
        fun main() {
            println('A'.isJavaIdentifierPart())
            println('5'.isJavaIdentifierPart())
            println('_'.isJavaIdentifierPart())
            println('$'.isJavaIdentifierPart())
            println(' '.isJavaIdentifierPart())
            println('+'.isJavaIdentifierPart())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharIsJavaIdentifierPartTypical",
            expected:
                """
                true
                true
                true
                true
                false
                false
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharIsJavaIdentifierPartDigitAllowedButStartForbids() throws {
        // Digits are valid identifier *parts* but NOT valid identifier *starts*.
        // This test documents the semantic difference between the two predicates
        // and ensures both runtime symbols are wired correctly through codegen.
        let source = """
        fun main() {
            println('5'.isJavaIdentifierPart())
            println('5'.isJavaIdentifierStart())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharIsJavaIdentifierPartVsStart",
            expected:
                """
                true
                false
                """
                + "\n"
        )
    }

    // KSP-481: `for (ch in someString)` used to leave the loop variable typed as
    // Any instead of Char, so member calls on it (and explicit `Char` typing)
    // failed to resolve even though runtime iteration was already correct.
    @Test
    func testCodegenForLoopStringIterationMemberCall() throws {
        let source = """
        fun main() {
            for (ch in "abc") {
                println(ch.digitToIntOrNull(16))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopStringIterationMemberCall",
            expected:
                """
                10
                11
                12
                """
                + "\n"
        )
    }

    @Test
    func testCodegenForLoopStringIterationExplicitCharType() throws {
        let source = """
        fun main() {
            for (ch in "abc") {
                val x: Char = ch
                println(x.digitToIntOrNull(16))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopStringIterationExplicitCharType",
            expected:
                """
                10
                11
                12
                """
                + "\n"
        )
    }

    // KSP-481: `for (i in 0 until n)` desugars `until` as an infix memberCall
    // rather than a `.binary` range op, so the for-loop's AST-shape range check
    // missed it and the loop variable fell back to Any -- breaking any strict
    // use of it, including as a String/Array index.
    @Test
    func testCodegenForLoopUntilRangeIndexedStringCharMemberCall() throws {
        let source = """
        fun main() {
            val hex = "abc"
            for (i in 0 until hex.length) {
                val ch = hex[i]
                println(ch.digitToIntOrNull(16))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopUntilRangeIndexedStringCharMemberCall",
            expected:
                """
                10
                11
                12
                """
                + "\n"
        )
    }

    @Test
    func testCodegenForLoopUntilRangeExplicitIntType() throws {
        let source = """
        fun main() {
            for (i in 0 until 3) {
                val x: Int = i
                println(x)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopUntilRangeExplicitIntType",
            expected:
                """
                0
                1
                2
                """
                + "\n"
        )
    }

    // Pre-existing bug (STDLIB-290 follow-up): `for (c in 'a'..'e')` mistyped the
    // loop variable as Int instead of Char. `.forEach { c -> }` already covered
    // CharRange execution (see testCodegenCharRangeForEachAscending above) via a
    // different lambda-typed code path, which is why it didn't catch this.
    @Test
    func testCodegenForLoopCharRangeExplicitCharType() throws {
        let source = """
        fun main() {
            for (c in 'a'..'e') {
                val x: Char = c
                println(x.code)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForLoopCharRangeExplicitCharType",
            expected:
                """
                97
                98
                99
                100
                101
                """
                + "\n"
        )
    }
}
#endif
