@testable import CompilerCore
import XCTest

final class KotlinIOURLReadTextFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "URL.readText surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testURLReadTextFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let urlSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("net"),
            interner.intern("URL"),
        ]))
        let urlType = sema.types.make(.classType(ClassType(
            classSymbol: urlSymbol,
            args: [],
            nullability: .nonNull
        )))
        let charsetSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Charset"),
        ]))
        let charsetType = sema.types.make(.classType(ClassType(
            classSymbol: charsetSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("readText"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == urlType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_url_readText_default")

        let charsetOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == urlType
                && signature.parameterTypes == [charsetType]
                && signature.returnType == sema.types.stringType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: charsetOverload), "kk_url_readText")
    }

    func testURLReadTextFunctionsResolveInSource() throws {
        let source = """
        import java.net.URL
        import kotlin.io.readText
        import kotlin.text.Charsets

        fun readDefault(url: URL): String = url.readText()
        fun readCharset(url: URL): String = url.readText(Charsets.UTF_8)
        """

        _ = try makeSema(source: source)
    }
}
