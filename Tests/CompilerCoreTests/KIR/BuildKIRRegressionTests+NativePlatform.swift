@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testNativePlatformMemoryModelLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform

        fun main() {
            val memoryModel = Platform.memoryModel
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_platform_memoryModel"),
                "Expected Platform.memoryModel runtime call"
            )
        }
    }

    func testABILoweringMarksNativePlatformMemoryModelAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        XCTAssertTrue(
            callees.contains(interner.intern("kk_platform_memoryModel")),
            "kk_platform_memoryModel should not receive an outThrown slot during ABI lowering"
        )
    }
}
