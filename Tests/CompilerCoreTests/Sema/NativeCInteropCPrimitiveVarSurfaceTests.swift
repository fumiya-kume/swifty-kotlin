@testable import CompilerCore
import XCTest

final class NativeCInteropCPrimitiveVarSurfaceTests: XCTestCase {
    func testCPrimitiveVarClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPrimitiveVar surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let cPrimitiveVarSymbol = try cinteropSymbol("CPrimitiveVar")
        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cPrimitiveVarTypeSymbol = try cinteropSymbol("CPrimitiveVar", "Type")
        let cVariableTypeSymbol = try cinteropSymbol("CVariable", "Type")
        let nativePtrType = try cinteropType("NativePtr")
        let cPrimitiveVarType = try cinteropType("CPrimitiveVar")
        let cPrimitiveVarTypeClassType = try cinteropType("CPrimitiveVar", "Type")
        let fqName = try XCTUnwrap(sema.symbols.symbol(cPrimitiveVarSymbol)?.fqName)
        let typeFQName = try XCTUnwrap(sema.symbols.symbol(cPrimitiveVarTypeSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(cPrimitiveVarSymbol)?.flags)
        let typeFlags = try XCTUnwrap(sema.symbols.symbol(cPrimitiveVarTypeSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(cPrimitiveVarSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.sealedType))
        XCTAssertTrue(flags.contains(.abstractType))
        XCTAssertTrue(flags.contains(.openType))
        XCTAssertEqual(sema.symbols.propertyType(for: cPrimitiveVarSymbol), cPrimitiveVarType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cPrimitiveVarSymbol), [cVariableSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cPrimitiveVarSymbol), [cVariableSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSymbol = try XCTUnwrap(constructors.first {
            guard let signature = sema.symbols.functionSignature(for: $0) else {
                return false
            }
            return signature.parameterTypes == [nativePtrType]
                && signature.returnType == cPrimitiveVarType
        })
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
        XCTAssertEqual(sema.symbols.symbol(constructorSymbol)?.visibility, .protected)
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])

        XCTAssertEqual(sema.symbols.symbol(cPrimitiveVarTypeSymbol)?.kind, .class)
        XCTAssertTrue(typeFlags.contains(.openType))
        XCTAssertEqual(sema.symbols.propertyType(for: cPrimitiveVarTypeSymbol), cPrimitiveVarTypeClassType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cPrimitiveVarTypeSymbol), [cVariableTypeSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cPrimitiveVarTypeSymbol), [cVariableTypeSymbol])

        let typeConstructors = sema.symbols.lookupAll(fqName: typeFQName + [interner.intern("<init>")])
        let typeConstructorSignature = try XCTUnwrap(typeConstructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [sema.types.intType] && $0.returnType == cPrimitiveVarTypeClassType
        })
        XCTAssertEqual(typeConstructorSignature.valueParameterHasDefaultValues, [false])
    }

    func testCPrimitiveVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPrimitiveVar

        fun pass(value: CPrimitiveVar): CPrimitiveVar {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPrimitiveVar to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
