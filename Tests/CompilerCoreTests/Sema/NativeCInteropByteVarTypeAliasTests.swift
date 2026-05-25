@testable import CompilerCore
import XCTest

final class NativeCInteropByteVarTypeAliasTests: XCTestCase {
    func testByteVarTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func symbol(_ fqPath: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) }),
                "\(fqPath.joined(separator: ".")) must be registered"
            )
        }

        let aliasSymbol = try symbol(["kotlinx", "cinterop", "ByteVar"])
        let byteVarOfSymbol = try symbol(["kotlinx", "cinterop", "ByteVarOf"])
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        )))
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: byteVarOfSymbol)

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
        XCTAssertEqual(sema.symbols.symbol(byteVarOfSymbol)?.kind, .class)
        XCTAssertEqual(typeParameters.count, 1)
        let typeParameter = try XCTUnwrap(typeParameters.first)
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [sema.types.intType])
    }

    func testByteVarOfClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) }),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let byteVarOfSymbol = try cinteropSymbol("ByteVarOf")
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: byteVarOfSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let byteVarOfType = sema.types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.directSupertypes(for: byteVarOfSymbol), [try cinteropSymbol("CPrimitiveVar")])
        XCTAssertEqual(sema.symbols.directSupertypes(for: try cinteropSymbol("CPrimitiveVar")), [try cinteropSymbol("CVariable")])
        XCTAssertEqual(sema.symbols.directSupertypes(for: try cinteropSymbol("CVariable")), [try cinteropSymbol("CPointed")])

        let fqName = try XCTUnwrap(sema.symbols.symbol(byteVarOfSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == byteVarOfType
        })
        XCTAssertEqual(constructorSignature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(constructorSignature.classTypeParameterCount, 1)

        let valueSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "ByteVarOf", "value"].map { interner.intern($0) })
        )
        XCTAssertEqual(sema.symbols.propertyType(for: valueSymbol), typeParameterType)
    }

    func testByteVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar

        fun roundtrip(value: ByteVar): ByteVar {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testByteVarOfValuePropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVarOf

        fun readByte(value: ByteVarOf<Byte>): Byte {
            return value.value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteVarOf.value to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
