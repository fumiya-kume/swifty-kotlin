@testable import CompilerCore
import XCTest

final class JsArrayInteropTests: XCTestCase {
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
                "Expected JsArray interop surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testListToJsArrayIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPkg + [interner.intern("List")]
        ))
        let listTypeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: listSymbol).first)
        let listTypeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol,
            nullability: .nonNull
        )))
        let listType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsArray")]
        ))
        let jsArrayType = sema.types.make(.classType(ClassType(
            classSymbol: jsArraySymbol,
            args: [.invariant(listTypeParamType)],
            nullability: .nonNull
        )))
        let toJsArray = try XCTUnwrap(
            sema.symbols.lookupAll(
                fqName: collectionsPkg + [interner.intern("List"), interner.intern("toJsArray")]
            ).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == listType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == jsArrayType
            },
            "List.toJsArray() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(toJsArray))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toJsArray))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.typeParameterSymbols, [listTypeParamSymbol])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
        XCTAssertEqual(sema.symbols.externalLinkName(for: toJsArray), "kk_list_toJsArray")
    }

    func testListToJsArrayResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsArray

        fun strings(values: List<String>): JsArray<String> = values.toJsArray()
        """

        let (sema, interner) = try makeSema(source: source)
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "JsArray"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: [interner.intern("strings")]
        ))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected strings() to return JsArray<String>")
        }

        XCTAssertEqual(returnClassType.classSymbol, jsArraySymbol)
        XCTAssertEqual(returnClassType.args, [.invariant(sema.types.stringType)])
    }

    func testArrayToJsArrayIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinPkg = ["kotlin"].map { interner.intern($0) }
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let arraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinPkg + [interner.intern("Array")]
        ))
        let arrayTypeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: arraySymbol).first)
        let arrayTypeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: arrayTypeParamSymbol,
            nullability: .nonNull
        )))
        let arrayType = sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(arrayTypeParamType)],
            nullability: .nonNull
        )))
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsArray")]
        ))
        let jsArrayType = sema.types.make(.classType(ClassType(
            classSymbol: jsArraySymbol,
            args: [.invariant(arrayTypeParamType)],
            nullability: .nonNull
        )))
        let toJsArray = try XCTUnwrap(
            sema.symbols.lookupAll(
                fqName: kotlinPkg + [interner.intern("Array"), interner.intern("toJsArray")]
            ).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == arrayType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == jsArrayType
            },
            "Array.toJsArray() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(toJsArray))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toJsArray))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.typeParameterSymbols, [arrayTypeParamSymbol])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
        XCTAssertEqual(sema.symbols.externalLinkName(for: toJsArray), "kk_array_toJsArray")
    }

    func testArrayToJsArrayResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsArray

        fun strings(values: Array<String>): JsArray<String> = values.toJsArray()
        """

        let (sema, interner) = try makeSema(source: source)
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "js", "JsArray"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: [interner.intern("strings")]
        ))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected strings() to return JsArray<String>")
        }

        XCTAssertEqual(returnClassType.classSymbol, jsArraySymbol)
        XCTAssertEqual(returnClassType.args, [.invariant(sema.types.stringType)])
    }
}
