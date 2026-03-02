@testable import CompilerCore
import Foundation
import XCTest

final class IntersectionTypeFlowTests: XCTestCase {
    func testIntersectionWithAnyMakesTypeParamDefinitelyNonNull() throws {
        let source = """
        fun <T : Any?> identity(x: T & Any): T & Any = x
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let xRef = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .nameRef(name, _) = expr else { return false }
                return ctx.interner.resolve(name) == "x"
            })
            let xType = try XCTUnwrap(sema.bindings.exprType(for: xRef))

            guard case let .intersection(parts) = sema.types.kind(of: xType) else {
                XCTFail("Expected intersection type for `x`, got \(sema.types.kind(of: xType))")
                return
            }

            let hasAny = parts.contains { sema.types.kind(of: $0) == .any(.nonNull) }
            let hasTypeParam = parts.contains {
                if case .typeParam = sema.types.kind(of: $0) {
                    return true
                }
                return false
            }

            XCTAssertTrue(hasAny)
            XCTAssertTrue(hasTypeParam)
            XCTAssertTrue(sema.types.isDefinitelyNonNull(xType))
            XCTAssertEqual(sema.types.nullability(of: xType), .nonNull)
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    func testDefinitelyNonNullIntersectionReceiverSupportsDirectAndSafeCalls() throws {
        let source = """
        fun Any.id(): Int = 1

        fun <T : Any?> direct(x: T & Any): Int = x.id()
        fun <T : Any?> safe(x: T & Any): Int? = x?.id()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let directCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "id"
            })
            let safeCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .safeMemberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "id"
            })

            XCTAssertEqual(sema.bindings.exprType(for: directCall), sema.types.intType)
            XCTAssertEqual(
                sema.bindings.exprType(for: safeCall),
                sema.types.makeNullable(sema.types.intType)
            )
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    func testIntersectionParameterInferenceAtCallSite() throws {
        let source = """
        fun Any.idTag(): Int = 7

        fun <T : Any?> directValue(x: T & Any): Int = x.idTag()
        fun <T : Any?> safeValue(x: T & Any): Int? = x?.idTag()

        fun main() {
            println(directValue("hello"))
            println(safeValue("world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }
}
