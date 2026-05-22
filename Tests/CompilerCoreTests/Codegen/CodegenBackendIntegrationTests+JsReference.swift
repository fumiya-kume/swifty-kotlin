@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenJsReferenceGetUsesRuntimeHelper() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

        import kotlin.js.JsReference

        fun unwrap(ref: JsReference<Int>): Int = ref.get()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "JsReferenceGetKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "unwrap", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_js_reference_get"))
        }
    }
}
