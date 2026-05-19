@testable import CompilerCore
import XCTest

final class JsCollectionsSetTests: XCTestCase {
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
                "Expected kotlin.js.collections.JsSet surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsSetClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let jsSetSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsSet")]
        ))
        let info = try XCTUnwrap(sema.symbols.symbol(jsSetSymbol))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: jsSetSymbol)

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.openType))
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: jsSetSymbol), [.invariant])
        XCTAssertNotNil(sema.symbols.propertyType(for: jsSetSymbol))
        XCTAssertTrue(sema.symbols.annotations(for: jsSetSymbol).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsSetExtendsReadonlySet() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let jsSetSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsSet")]
        ))
        let readonlySetSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlySet")]
        ))
        let typeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: jsSetSymbol).first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.directSupertypes(for: jsSetSymbol), [readonlySetSymbol])
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: jsSetSymbol, supertype: readonlySetSymbol),
            [.out(typeParamType)]
        )
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: readonlySetSymbol), [.out])
    }

    func testJsSetCanBeImportedAndUsedAsType() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsSet

        fun accept(values: JsSet<String>): JsSet<String> = values
        """
        let (sema, interner) = try makeSema(source: source)
        let jsSetSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "collections", "JsSet"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("accept")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected accept() to return JsSet<String>")
        }
        XCTAssertEqual(returnClassType.classSymbol, jsSetSymbol)
        let returnArg: TypeID
        switch try XCTUnwrap(returnClassType.args.first) {
        case let .invariant(arg), let .out(arg):
            returnArg = arg
        case .in, .star:
            return XCTFail("Expected accept() to return JsSet<String>")
        }
        XCTAssertEqual(returnArg, sema.types.stringType)
    }
}
