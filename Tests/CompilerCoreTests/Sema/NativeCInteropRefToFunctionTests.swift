@testable import CompilerCore
import XCTest

final class NativeCInteropRefToFunctionTests: XCTestCase {
    // ByteVar is a type alias for ByteVarOf<Byte>; the stub uses ByteVarOf<Int> (same underlying).
    func testByteArrayRefToFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteArray.refTo(index) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let byteArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ByteArray")]),
            "kotlin.ByteArray must be registered"
        )
        let byteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesRefSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValuesRef")]),
            "kotlinx.cinterop.CValuesRef must be registered"
        )
        // ByteVar is a type alias for ByteVarOf<Byte>; stub uses ByteVarOf<Int> (same Byte representation).
        let byteVarOfSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ByteVarOf")]),
            "kotlinx.cinterop.ByteVarOf must be registered"
        )
        let byteVarType = sema.types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesRefSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))

        let refToFQName = cinteropPkg + [interner.intern("refTo")]
        let refToCandidates = sema.symbols.lookupAll(fqName: refToFQName)
        let refTo = try XCTUnwrap(refToCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == byteArrayType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == expectedReturnType
        }, "ByteArray.refTo(Int): CValuesRef<ByteVarOf<Int>> must be registered")
        let flags = try XCTUnwrap(sema.symbols.symbol(refTo)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: refTo), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testIntArrayRefToFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected IntArray.refTo(index) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let intArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("IntArray")]),
            "kotlin.IntArray must be registered"
        )
        let intArrayType = sema.types.make(.classType(ClassType(
            classSymbol: intArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesRefSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValuesRef")]),
            "kotlinx.cinterop.CValuesRef must be registered"
        )
        let intVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("IntVar")]),
            "kotlinx.cinterop.IntVar must be registered"
        )
        let intVarType = sema.types.make(.classType(ClassType(
            classSymbol: intVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesRefSymbol,
            args: [.invariant(intVarType)],
            nullability: .nonNull
        )))

        let refToFQName = cinteropPkg + [interner.intern("refTo")]
        let refToCandidates = sema.symbols.lookupAll(fqName: refToFQName)
        let refTo = try XCTUnwrap(refToCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == intArrayType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == expectedReturnType
        }, "IntArray.refTo(Int): CValuesRef<IntVar> must be registered")
        let flags = try XCTUnwrap(sema.symbols.symbol(refTo)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: refTo), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testDoubleArrayRefToFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected DoubleArray.refTo(index) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let doubleArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("DoubleArray")]),
            "kotlin.DoubleArray must be registered"
        )
        let doubleArrayType = sema.types.make(.classType(ClassType(
            classSymbol: doubleArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesRefSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValuesRef")]),
            "kotlinx.cinterop.CValuesRef must be registered"
        )
        let doubleVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("DoubleVar")]),
            "kotlinx.cinterop.DoubleVar must be registered"
        )
        let doubleVarType = sema.types.make(.classType(ClassType(
            classSymbol: doubleVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesRefSymbol,
            args: [.invariant(doubleVarType)],
            nullability: .nonNull
        )))

        let refToFQName = cinteropPkg + [interner.intern("refTo")]
        let refToCandidates = sema.symbols.lookupAll(fqName: refToFQName)
        let refTo = try XCTUnwrap(refToCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == doubleArrayType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == expectedReturnType
        }, "DoubleArray.refTo(Int): CValuesRef<DoubleVar> must be registered")
        let flags = try XCTUnwrap(sema.symbols.symbol(refTo)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: refTo), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testIntArrayRefToFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.IntVar
        import kotlinx.cinterop.CValuesRef
        import kotlinx.cinterop.refTo

        fun getIntRef(ints: IntArray, index: Int): CValuesRef<IntVar> {
            return ints.refTo(index)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected IntArray.refTo() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testFloatArrayRefToFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.FloatVar
        import kotlinx.cinterop.CValuesRef
        import kotlinx.cinterop.refTo

        fun getFloatRef(floats: FloatArray, index: Int): CValuesRef<FloatVar> {
            return floats.refTo(index)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected FloatArray.refTo() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
