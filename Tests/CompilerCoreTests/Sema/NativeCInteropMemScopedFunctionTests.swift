@testable import CompilerCore
import XCTest

final class NativeCInteropMemScopedFunctionTests: XCTestCase {
    func testMemScopedFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected memScoped surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) }),
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

        let memScopeType = try cinteropType("MemScope")
        let memScopedFQName = cinteropPkg + [interner.intern("memScoped")]
        let memScopedSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: memScopedFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memScopedSymbol))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedBlockType = sema.types.make(.functionType(FunctionType(
            receiver: memScopeType,
            params: [],
            returnType: typeParameterType
        )))
        let blockParameter = try XCTUnwrap(signature.valueParameterSymbols.first)
        let flags = try XCTUnwrap(sema.symbols.symbol(memScopedSymbol)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(signature.parameterTypes, [expectedBlockType])
        XCTAssertEqual(signature.returnType, typeParameterType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[]])
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("R"))
        XCTAssertEqual(sema.symbols.symbol(blockParameter)?.name, interner.intern("block"))
        XCTAssertEqual(sema.symbols.propertyType(for: blockParameter), expectedBlockType)
        XCTAssertEqual(sema.symbols.parentSymbol(for: memScopedSymbol), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testMemScopedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.memScoped

        fun scopedValue(): Int {
            return memScoped<Int> {
                42
            }
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected memScoped to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
