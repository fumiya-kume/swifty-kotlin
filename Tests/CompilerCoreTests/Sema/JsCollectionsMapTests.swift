@testable import CompilerCore
import XCTest

final class JsCollectionsMapTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected kotlin.js.collections.JsMap surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsMapClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let jsMapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsMap")]
        ))
        let info = try XCTUnwrap(sema.symbols.symbol(jsMapSymbol))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: jsMapSymbol)

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.openType))
        XCTAssertEqual(typeParams.count, 2)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: jsMapSymbol), [.invariant, .invariant])
        XCTAssertNotNil(sema.symbols.propertyType(for: jsMapSymbol))
        XCTAssertTrue(sema.symbols.annotations(for: jsMapSymbol).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsMapExtendsReadonlyMap() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let jsMapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsMap")]
        ))
        let readonlyMapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyMap")]
        ))
        let typeParamSymbols = sema.types.nominalTypeParameterSymbols(for: jsMapSymbol)
        let keyTypeParamSymbol = try XCTUnwrap(typeParamSymbols.first)
        let valueTypeParamSymbol = try XCTUnwrap(typeParamSymbols.dropFirst().first)
        let keyType = sema.types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: valueTypeParamSymbol,
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.directSupertypes(for: jsMapSymbol), [readonlyMapSymbol])
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: jsMapSymbol, supertype: readonlyMapSymbol),
            [.invariant(keyType), .out(valueType)]
        )
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: readonlyMapSymbol), [.invariant, .out])
    }

    func testJsMapCanBeImportedAndUsedAsType() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsMap

        fun accept(values: JsMap<String, Int>): JsMap<String, Int> = values
        """
        let (sema, interner) = try makeSema(source: source)
        let jsMapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "collections", "JsMap"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("accept")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected accept() to return JsMap<String, Int>")
        }
        XCTAssertEqual(returnClassType.classSymbol, jsMapSymbol)
        XCTAssertEqual(returnClassType.args.count, 2)
        let returnArgs = try returnClassType.args.map { projection -> TypeID in
            switch projection {
            case let .invariant(arg), let .out(arg):
                return arg
            case .in, .star:
                throw XCTSkip("Expected accept() to return JsMap<String, Int>")
            }
        }
        XCTAssertEqual(returnArgs[0], sema.types.stringType)
        XCTAssertEqual(returnArgs[1], sema.types.intType)
    }
}
