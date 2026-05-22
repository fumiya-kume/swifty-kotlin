@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testBuildKIRLowersJsReferenceGetToRuntimeCall() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

        import kotlin.js.JsReference

        fun unwrap(ref: JsReference<Int>): Int = ref.get()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "unwrap", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callNames.contains("kk_js_reference_get"))
            XCTAssertFalse(callNames.contains("get"))
        }
    }

    func testABILoweringMarksJsReferenceGetAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(callees.contains(interner.intern("kk_js_reference_get")))
    }
}
