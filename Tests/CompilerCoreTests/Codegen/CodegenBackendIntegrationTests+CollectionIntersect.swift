import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenListIntersectUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val result = listOf(1, 2, 2, 3, 4).intersect(listOf(2, 4, 5))
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ListIntersectRuntime", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_list_intersect"))
        }
    }
}
