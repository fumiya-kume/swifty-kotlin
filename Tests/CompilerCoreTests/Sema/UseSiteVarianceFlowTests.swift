@testable import CompilerCore
import Foundation
import XCTest

final class UseSiteVarianceFlowTests: XCTestCase {
    func testOutProjectionBlocksWriteAndPreservesReadType() throws {
        let source = """
        class E

        class Box<T> {
            fun get(): T = throw E()
            fun set(v: T) {}
        }

        fun readOnly(box: Box<out Any>): Any = box.get()

        fun writeBlocked(box: Box<out Any>) {
            box.set(42)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let getCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "get"
            })
            XCTAssertEqual(sema.bindings.exprType(for: getCall), sema.types.anyType)

            assertHasDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testStarProjectionReadsAsNullableAnyAndBlocksWrite() throws {
        let source = """
        class E

        class Box<T> {
            fun get(): T = throw E()
            fun set(v: T) {}
        }

        fun starRead(box: Box<*>): Any? = box.get()

        fun starWrite(box: Box<*>) {
            box.set(42)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let getCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "get"
            })
            XCTAssertEqual(sema.bindings.exprType(for: getCall), sema.types.nullableAnyType)

            assertHasDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }
}
