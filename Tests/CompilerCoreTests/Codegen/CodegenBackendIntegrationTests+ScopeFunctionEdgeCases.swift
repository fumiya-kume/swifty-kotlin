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

        fun labeledResult(): String = run outer@{
            "label".let {
                if (it.length == 5) return@outer "labeled-return"
                "unreachable"
            }
        }

        fun main() {
            val nullableInput: String? = "hello"
            println(nullableInput?.let { it.uppercase() })
            println((null as String?)?.let { it.uppercase() })

            println(traceValue("takeIf").takeIf { it.startsWith("take") })
            println(traceValue("takeUnless").takeUnless { it.endsWith("less") })

            val alsoResult = makeTaggedBuilder("once").also { it.append(":also") }.toString()
            println(alsoResult)

            val withResult = with(makeTaggedBuilder("with")) {
                append(":with")
                toString()
            }
            println(withResult)

            val nested = "kotlin"
                .takeIf { it.startsWith("kot") }
                ?.let { it.takeUnless { inner -> inner.length > 10 } }
            println(nested)

            val applyRunResult = makeTaggedBuilder("apply").apply {
                append(":run")
            }.run {
                append(":done")
                toString()
            }
            println(applyRunResult)

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
                nil
                value:takeIf
                takeIf
                value:takeUnless
                null
                make:once
                once:also
                make:with
                with:with
                kotlin
                make:apply
                apply:run:done
                labeled-return
                """
            )
        }
    }
}
