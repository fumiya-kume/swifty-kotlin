@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerUShortVarToKStringFromUtf16FunctionTests: XCTestCase {
    func testCPointerUShortVarToKStringFromUtf16FunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let uShortVarSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]))
        let uShortVarType = sema.types.make(.classType(ClassType(classSymbol: uShortVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(uShortVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKStringFromUtf16")])
        let fn = try XCTUnwrap(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        XCTAssertTrue(try XCTUnwrap(sema.symbols.symbol(fn)?.flags).contains(.synthetic))
    }

    func testCPointerUShortVarToKStringFromUtf16FunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.UShortVar
        import kotlinx.cinterop.toKStringFromUtf16

        fun decode(p: CPointer<UShortVar>): String {
            return p.toKStringFromUtf16()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
