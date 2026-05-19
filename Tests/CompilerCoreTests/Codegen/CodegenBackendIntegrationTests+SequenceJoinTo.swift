@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceJoinToAppendsToStringBuilder() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun main() {
            val first = StringBuilder("seed:")
            sequenceOf(1, 2, 3).joinTo(first, "|", "<", ">")
            println(first.toString())

            val second = StringBuilder()
            sequenceOf("a", "b", "c").joinTo(second)
            println(second.toString())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceJoinToRuntime",
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
                """ + "\n"
            )
        }
    }

    func testCodegenSequenceJoinToUsesRuntimeHelper() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun render(builder: StringBuilder): String {
            sequenceOf(1, 2, 3).joinTo(builder, "|", "<", ">")
            return builder.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceJoinToKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_sequence_joinTo"))
        }
    }
}
