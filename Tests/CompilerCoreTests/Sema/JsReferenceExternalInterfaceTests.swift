@testable import CompilerCore
import XCTest

final class JsReferenceExternalInterfaceTests: XCTestCase {
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
                "Expected JsReference external interface surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsReferenceInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsReference"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsReference must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testJsReferenceGetIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsReferenceFQName = ["kotlin", "js", "JsReference"].map { interner.intern($0) }
        let jsReferenceSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: jsReferenceFQName))
        let typeParamSymbol = try XCTUnwrap(
            sema.types.nominalTypeParameterSymbols(for: jsReferenceSymbol).first
        )
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = try XCTUnwrap(sema.symbols.propertyType(for: jsReferenceSymbol))

        let get = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsReferenceFQName + [interner.intern("get")]).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == typeParamType
                    && signature.typeParameterSymbols == [typeParamSymbol]
                    && signature.classTypeParameterCount == 1
            },
            "JsReference<T>.get() member must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(get))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.externalLinkName(for: get), "kk_js_reference_get")
    }

    func testJsReferenceGetResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsReference

        fun <T : Any> unwrap(ref: JsReference<T>): T = ref.get()
        """
        let (sema, interner) = try makeSema(source: source)

        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("unwrap")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        guard case .typeParam = sema.types.kind(of: signature.returnType) else {
            return XCTFail("unwrap should return T, got \(sema.types.renderType(signature.returnType))")
        }
    }
}
