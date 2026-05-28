@testable import CompilerCore
import XCTest

final class NativeCInteropArrayCPointerToCValuesFunctionTests: XCTestCase {
    func testArrayCPointerToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Array<CPointer<T>?>.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let arraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("Array")]),
            "kotlin.Array must be registered"
        )
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let cPointerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]),
            "kotlinx.cinterop.CPointer must be registered"
        )
        let cPointerVarOfSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointerVarOf")]),
            "kotlinx.cinterop.CPointerVarOf must be registered"
        )

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try XCTUnwrap(
            toCValuesCandidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                guard let receiverType = signature.receiverType,
                      signature.parameterTypes.isEmpty else {
                    return false
                }
                // Receiver must be Array<...>
                guard case .classType(let rt) = sema.types.kind(of: receiverType),
                      rt.classSymbol == arraySymbol else {
                    return false
                }
                // Return type must be CValues<CPointerVarOf<CPointer<T>>>
                guard case .classType(let ret) = sema.types.kind(of: signature.returnType),
                      ret.classSymbol == cValuesSymbol,
                      ret.args.count == 1,
                      case .invariant(let varOfType) = ret.args[0],
                      case .classType(let varOf) = sema.types.kind(of: varOfType),
                      varOf.classSymbol == cPointerVarOfSymbol,
                      varOf.args.count == 1,
                      case .invariant(let ptrType) = varOf.args[0],
                      case .classType(let ptr) = sema.types.kind(of: ptrType),
                      ptr.classSymbol == cPointerSymbol else {
                    return false
                }
                return true
            },
            "Array<CPointer<T>?>.toCValues() must be registered"
        )
        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testArrayCPointerToCValuesFunctionHasOneTypeParameter() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Array<CPointer<T>?>.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let arraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("Array")])
        )
        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try XCTUnwrap(
            toCValuesCandidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType else { return false }
                guard case .classType(let rt) = sema.types.kind(of: receiverType),
                      rt.classSymbol == arraySymbol else { return false }
                return true
            }
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toCValues))
        XCTAssertEqual(
            signature.typeParameterSymbols.count,
            1,
            "toCValues on Array<CPointer<T>?> must have exactly one type parameter T"
        )
    }
}
