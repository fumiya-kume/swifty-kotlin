@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenIterableJoinToAppendsToStringBuilder() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun main() {
            val values: Collection<Int> = listOf(1, 2, 3)
            val first = StringBuilder("seed:")
            values.joinTo(first, "|", "<", ">")
            println(first.toString())

            val second = StringBuilder()
            listOf("a", "b", "c").joinTo(second)
            println(second.toString())

            val third = StringBuilder()
            setOf("x", "y").joinTo(third, ";", "[", "]")
            println(third.toString())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionJoinToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                seed:<1|2|3>
                a, b, c
                [x;y]
                """ + "\n"
            )
        }
    }

    func testCodegenIterableJoinToUsesRuntimeHelper() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun render(values: Collection<Int>, builder: StringBuilder): String {
            values.joinTo(builder, "|", "<", ">")
            return builder.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CollectionJoinToKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_iterable_joinTo"))
        }
    }
}
