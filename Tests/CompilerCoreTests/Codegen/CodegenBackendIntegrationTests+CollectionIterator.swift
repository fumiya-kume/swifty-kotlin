@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionIteratorUsesListRuntimeHelper() throws {
        let source = """
        fun firstList(values: List<Int>): Int {
            val iterator = values.iterator()
            return if (iterator.hasNext()) iterator.next() else -1
        }

        fun firstSet(values: Set<Int>): Int {
            val iterator = values.iterator()
            return if (iterator.hasNext()) iterator.next() else -1
        }

        fun firstCollection(values: Collection<Int>): Int {
            val iterator = values.iterator()
            return if (iterator.hasNext()) iterator.next() else -1
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CollectionIteratorRuntime", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            for functionName in ["firstList", "firstSet", "firstCollection"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                XCTAssertTrue(callees.contains("kk_list_iterator"), "\(functionName) should call kk_list_iterator")
                XCTAssertFalse(callees.contains("kk_range_iterator"), "\(functionName) should not call kk_range_iterator")
            }
        }
    }
}
