@testable import CompilerCore
import XCTest

final class NativeCInteropCVariableSurfaceTests: XCTestCase {
    func testCVariableClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CVariable surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cVariableTypeSymbol = try cinteropSymbol("CVariable", "Type")
        let cPointedSymbol = try cinteropSymbol("CPointed")
        let nativePtrType = try cinteropType("NativePtr")
        let cVariableType = try cinteropType("CVariable")
        let cVariableTypeClassType = try cinteropType("CVariable", "Type")
        let fqName = try XCTUnwrap(sema.symbols.symbol(cVariableSymbol)?.fqName)
        let typeFQName = try XCTUnwrap(sema.symbols.symbol(cVariableTypeSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(cVariableSymbol)?.flags)
        let typeFlags = try XCTUnwrap(sema.symbols.symbol(cVariableTypeSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(cVariableSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.abstractType))
        XCTAssertEqual(sema.symbols.propertyType(for: cVariableSymbol), cVariableType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cVariableSymbol), [cPointedSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cVariableSymbol), [cPointedSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cVariableType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])

        XCTAssertEqual(sema.symbols.symbol(cVariableTypeSymbol)?.kind, .class)
        XCTAssertTrue(typeFlags.contains(.openType))
        XCTAssertEqual(sema.symbols.propertyType(for: cVariableTypeSymbol), cVariableTypeClassType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cVariableTypeSymbol), [])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cVariableTypeSymbol), [])
        XCTAssertTrue(
            sema.symbols.annotations(for: cVariableTypeSymbol).contains {
                $0.annotationFQName == "kotlin.Deprecated" &&
                    $0.arguments == ["message = \"Use sizeOf<T>() or alignOf<T>() instead.\""]
            }
        )

        let typeConstructors = sema.symbols.lookupAll(fqName: typeFQName + [interner.intern("<init>")])
        let typeConstructorSignature = try XCTUnwrap(typeConstructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [sema.types.longType, sema.types.intType]
                && $0.returnType == cVariableTypeClassType
        })
        XCTAssertEqual(typeConstructorSignature.valueParameterHasDefaultValues, [false, false])

        let sizeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: typeFQName + [interner.intern("size")]))
        XCTAssertEqual(sema.symbols.propertyType(for: sizeSymbol), sema.types.longType)
        let alignSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: typeFQName + [interner.intern("align")]))
        XCTAssertEqual(sema.symbols.propertyType(for: alignSymbol), sema.types.intType)
    }

    func testCVariableResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.NativePtr

        fun upcast(value: CVariable): CPointed {
            return value
        }

        fun raw(value: CVariable): NativePtr {
            return value.rawPtr
        }

        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CVariable members to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
