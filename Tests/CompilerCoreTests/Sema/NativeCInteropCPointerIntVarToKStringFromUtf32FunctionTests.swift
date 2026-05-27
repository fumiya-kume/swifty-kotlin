@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerIntVarToKStringFromUtf32FunctionTests: XCTestCase {
    func testCPointerIntVarToKStringFromUtf32FunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let intVarSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("IntVar")]))
        let intVarType = sema.types.make(.classType(ClassType(classSymbol: intVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(intVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKStringFromUtf32")])
        let fn = try XCTUnwrap(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        XCTAssertTrue(try XCTUnwrap(sema.symbols.symbol(fn)?.flags).contains(.synthetic))
    }

    func testCPointerIntVarToKStringFromUtf32FunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.IntVar
        import kotlinx.cinterop.toKStringFromUtf32

        fun decode(p: CPointer<IntVar>): String {
            return p.toKStringFromUtf32()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
