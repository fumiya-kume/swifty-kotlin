@testable import CompilerCore
import XCTest

final class NativeCInteropCStructVarSurfaceTests: XCTestCase {
    func testCStructVarClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CStructVar surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let cStructVarSymbol = try cinteropSymbol("CStructVar")
        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cStructVarTypeSymbol = try cinteropSymbol("CStructVar", "Type")
        let cVariableTypeSymbol = try cinteropSymbol("CVariable", "Type")
        let nativePtrType = try cinteropType("NativePtr")
        let cStructVarType = try cinteropType("CStructVar")
        let cStructVarTypeClassType = try cinteropType("CStructVar", "Type")
        let fqName = try XCTUnwrap(sema.symbols.symbol(cStructVarSymbol)?.fqName)
        let typeFQName = try XCTUnwrap(sema.symbols.symbol(cStructVarTypeSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(cStructVarSymbol)?.flags)
        let typeFlags = try XCTUnwrap(sema.symbols.symbol(cStructVarTypeSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(cStructVarSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.abstractType))
        XCTAssertTrue(flags.contains(.openType))
        XCTAssertEqual(sema.symbols.propertyType(for: cStructVarSymbol), cStructVarType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cStructVarSymbol), [cVariableSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cStructVarSymbol), [cVariableSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cStructVarType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])

        XCTAssertEqual(sema.symbols.symbol(cStructVarTypeSymbol)?.kind, .class)
        XCTAssertTrue(typeFlags.contains(.openType))
        XCTAssertEqual(sema.symbols.propertyType(for: cStructVarTypeSymbol), cStructVarTypeClassType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cStructVarTypeSymbol), [cVariableTypeSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cStructVarTypeSymbol), [cVariableTypeSymbol])

        let typeConstructors = sema.symbols.lookupAll(fqName: typeFQName + [interner.intern("<init>")])
        let typeConstructorSignature = try XCTUnwrap(typeConstructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [sema.types.longType, sema.types.intType]
                && $0.returnType == cStructVarTypeClassType
        })
        XCTAssertEqual(typeConstructorSignature.valueParameterHasDefaultValues, [false, false])
    }

    func testCStructVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CStructVar

        fun pass(value: CStructVar): CStructVar {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CStructVar to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
