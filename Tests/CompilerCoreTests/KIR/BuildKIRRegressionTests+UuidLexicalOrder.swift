@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testUuidLexicalOrderCompanionPropertyLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val lexicalOrder = Uuid.LEXICAL_ORDER
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_uuid_lexicalOrder"), "Expected Uuid.LEXICAL_ORDER runtime call")
        }
    }

    func testABILoweringMarksUuidLexicalOrderAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_uuid_lexicalOrder")))
        XCTAssertFalse(callees.contains(interner.intern("kk_uuid_parse")))
    }
}
