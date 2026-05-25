@testable import CompilerCore
import XCTest

final class NativeCInteropCEnumVarSurfaceTests: XCTestCase {
    func testCEnumVarClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CEnumVar surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) }),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cEnumVarSymbol = try cinteropSymbol("CEnumVar")
        let cEnumVarType = sema.types.make(.classType(ClassType(
            classSymbol: cEnumVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(cEnumVarSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(cEnumVarSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(sema.symbols.propertyType(for: cEnumVarSymbol), cEnumVarType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cEnumVarSymbol), [try cinteropSymbol("CPrimitiveVar")])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cEnumVarSymbol), [try cinteropSymbol("CPrimitiveVar")])

        let fqName = try XCTUnwrap(sema.symbols.symbol(cEnumVarSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cEnumVarType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])
    }

    func testCEnumVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CEnumVar

        fun pass(value: CEnumVar): CEnumVar {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CEnumVar to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
