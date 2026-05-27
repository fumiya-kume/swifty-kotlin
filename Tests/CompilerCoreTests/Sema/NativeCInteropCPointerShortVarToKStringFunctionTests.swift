@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerShortVarToKStringFunctionTests: XCTestCase {
    func testCPointerShortVarToKStringFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let shortVarSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]))
        let shortVarType = sema.types.make(.classType(ClassType(classSymbol: shortVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(shortVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
        let fn = try XCTUnwrap(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        XCTAssertTrue(try XCTUnwrap(sema.symbols.symbol(fn)?.flags).contains(.synthetic))
    }

    func testCPointerShortVarToKStringFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.ShortVar
        import kotlinx.cinterop.toKString

        fun decode(p: CPointer<ShortVar>): String {
            return p.toKString()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
