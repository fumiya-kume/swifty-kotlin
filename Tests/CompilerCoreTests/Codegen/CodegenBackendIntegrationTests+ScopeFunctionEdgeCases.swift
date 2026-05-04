@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesScopeFunctionEdgeCases() throws {
        let source = """
        fun traceValue(tag: String): String {
            println("value:$tag")
            return tag
        }

        fun makeTaggedBuilder(tag: String): StringBuilder {
            println("make:$tag")
            return StringBuilder(tag)
        }

        fun labeledResult(): String = run {
            if (true) return@run "labeled-return"
            "unreachable"
        }

        fun main() {
            val nullableInput: String? = "hello"
            println(nullableInput?.let { it.uppercase() })
            println((null as String?)?.let { it.uppercase() })

            println(traceValue("takeIf").takeIf { it.startsWith("take") })
            println(traceValue("takeUnless").takeUnless { it.endsWith("less") })

            val alsoResult = makeTaggedBuilder("once").also { it.append(":also") }.toString()
            println(alsoResult)

            val withResult = with(traceValue("with")) {
                this + ":with"
            }
            println(withResult)

            val nested = "kotlin"
                .takeIf { it.startsWith("kot") }
                ?.let { it.takeUnless { inner -> inner.length > 10 } }
            println(nested)

            val applyResult = makeTaggedBuilder("apply").apply {
                append(":done")
            }.toString()
            println(applyResult)

            println(labeledResult())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ScopeFunctionEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                HELLO
                null
                value:takeIf
                null
                value:takeUnless
                null
                make:once
                once:also
                value:with
                with:with
                null
                make:apply
                apply:done
                labeled-return
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesContextHelper() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            val result = context("context-ok") { contextOf<String>() }
            println(result)
            println(context("context-two", 2) { contextOf<String>() })
            println(context(1, 2, "context-six", 4, 5, 6) { contextOf<String>() })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ContextHelper",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                context-ok
                context-two
                context-six
                """
                + "\n"
            )
        }
    }
}
