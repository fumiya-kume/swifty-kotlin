@testable import CompilerCore
import XCTest

final class JsCollectionsArrayTests: XCTestCase {
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
                "Expected kotlin.js.collections.JsArray surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsArrayClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsArray")]
        ))
        let info = try XCTUnwrap(sema.symbols.symbol(jsArraySymbol))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: jsArraySymbol)

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.openType))
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: jsArraySymbol), [.invariant])
        XCTAssertNotNil(sema.symbols.propertyType(for: jsArraySymbol))
        XCTAssertTrue(sema.symbols.annotations(for: jsArraySymbol).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsArrayExtendsReadonlyArray() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsArray")]
        ))
        let readonlyArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyArray")]
        ))
        let typeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: jsArraySymbol).first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.directSupertypes(for: jsArraySymbol), [readonlyArraySymbol])
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: jsArraySymbol, supertype: readonlyArraySymbol),
            [.out(typeParamType)]
        )
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: readonlyArraySymbol), [.out])
    }

    func testJsArrayCanBeImportedAndUsedAsType() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsArray

        fun accept(values: JsArray<String>): JsArray<String> = values
        """
        let (sema, interner) = try makeSema(source: source)
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "collections", "JsArray"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("accept")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected accept() to return JsArray<String>")
        }
        XCTAssertEqual(returnClassType.classSymbol, jsArraySymbol)
        let returnArg: TypeID
        switch try XCTUnwrap(returnClassType.args.first) {
        case let .invariant(arg), let .out(arg):
            returnArg = arg
        case .in, .star:
            return XCTFail("Expected accept() to return JsArray<String>")
        }
        XCTAssertEqual(returnArg, sema.types.stringType)
    }
}
