@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testUuidParseHexDashOrNullLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            Uuid.parseHexDashOrNull("550e8400-e29b-41d4-a716-446655440000")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_uuid_parseHexDashOrNull"),
                "Expected Uuid.parseHexDashOrNull runtime call"
            )
        }
    }
}
