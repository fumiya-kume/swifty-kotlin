@testable import CompilerCore
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceJoinToStringUsesRuntimeHelper() throws {
        let source = """
        fun render(): String {
            return sequenceOf(1, 2, 3).joinToString(separator = ":", prefix = "[", postfix = "]")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceJoinToStringKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_sequence_joinToString"))
        }
    }
}
