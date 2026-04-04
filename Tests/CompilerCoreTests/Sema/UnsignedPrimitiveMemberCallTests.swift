@testable import CompilerCore
import XCTest

final class UnsignedPrimitiveMemberCallTests: XCTestCase {
    func testUnsignedMemberCallsInferExpectedTypes() throws {
        let source = """
        fun sample(ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            ub.and(ub)
            us.xor(us)
            ui.shl(1)
            ul.ushr(1)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)

        let expectedTypes: [String: TypeID] = [
            "and": sema.types.ubyteType,
            "xor": sema.types.ushortType,
            "shl": sema.types.uintType,
            "ushr": sema.types.ulongType,
        ]

        for (memberName, expectedType) in expectedTypes {
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else {
                        return false
                    }
                    return ctx.interner.resolve(callee) == memberName
                },
                "Expected a call expression for \(memberName)"
            )
            XCTAssertEqual(
                sema.bindings.exprTypes[callExpr],
                expectedType,
                "\(memberName) should infer expected type"
            )
        }
    }

    func testUnsignedMemberCallsRejectMixedWidths() {
        let source = """
        fun sample(ub: UByte, us: UShort) {
            ub.and(us)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnsignedMemberCallsRejectNullableRhs() {
        let source = """
        fun sample(ub: UByte, rhs: UByte?) {
            ub.and(rhs)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnsignedMemberCallsRejectShiftOnUByte() {
        let source = """
        fun sample(ub: UByte) {
            ub.shl(1)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnsignedMemberCallsRejectShiftOnUShort() {
        let source = """
        fun sample(us: UShort) {
            us.shr(1)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnsignedSafeInvCallsCompile() throws {
        let source = """
        fun sample(ub: UByte?, us: UShort?) {
            ub?.inv()
            us?.inv()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected unsigned safe inv calls to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }
}
