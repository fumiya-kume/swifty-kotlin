@testable import CompilerCore
import XCTest

final class NativeCInteropDeferScopeSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected DeferScope surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        return (try XCTUnwrap(ctx.sema), ctx.interner)
    }

    private func cinteropSymbol(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) }),
            "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered",
            file: file,
            line: line
        )
    }

    private func cinteropSymbol(
        _ path: String...,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try cinteropSymbol(path, sema: sema, interner: interner, file: file, line: line)
    }

    private func cinteropType(
        _ path: String...,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol(path, sema: sema, interner: interner, file: file, line: line),
            args: [],
            nullability: .nonNull
        )))
    }

    func testDeferScopeClassSurfaceMatchesNativeShape() throws {
        let (sema, interner) = try makeSema()

        let deferScopeSymbol = try cinteropSymbol("DeferScope", sema: sema, interner: interner)
        let deferScopeType = try cinteropType("DeferScope", sema: sema, interner: interner)
        let fqName = try XCTUnwrap(sema.symbols.symbol(deferScopeSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(deferScopeSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(deferScopeSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.openType))
        XCTAssertEqual(sema.symbols.propertyType(for: deferScopeSymbol), deferScopeType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: deferScopeSymbol), [])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: deferScopeSymbol), [])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes.isEmpty && $0.returnType == deferScopeType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [])
    }

    func testDeferScopeDeferMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let deferScopeSymbol = try cinteropSymbol("DeferScope", sema: sema, interner: interner)
        let deferScopeType = try cinteropType("DeferScope", sema: sema, interner: interner)
        let fqName = try XCTUnwrap(sema.symbols.symbol(deferScopeSymbol)?.fqName)
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.unitType
        )))
        let deferMembers = sema.symbols.lookupAll(fqName: fqName + [interner.intern("defer")])
        let deferSymbol = try XCTUnwrap(deferMembers.first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == deferScopeType
                && signature.parameterTypes == [blockType]
                && signature.returnType == sema.types.unitType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: deferSymbol))

        XCTAssertTrue(sema.symbols.symbol(deferSymbol)?.flags.isSuperset(of: [.synthetic, .inlineFunction]) == true)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false])
        let blockParameter = try XCTUnwrap(signature.valueParameterSymbols.first)
        XCTAssertEqual(sema.symbols.symbol(blockParameter)?.name, interner.intern("block"))
        XCTAssertEqual(sema.symbols.propertyType(for: blockParameter), blockType)
    }

    func testDeferScopeResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.DeferScope

        fun makeScope(): DeferScope {
            return DeferScope()
        }

        fun register(scope: DeferScope) {
            scope.defer {
            }
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected DeferScope constructor and defer member to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
