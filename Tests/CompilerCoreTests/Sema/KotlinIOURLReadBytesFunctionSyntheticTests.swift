@testable import CompilerCore
import XCTest

final class KotlinIOURLReadBytesFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "URL.readBytes surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testURLReadBytesFunctionIsRegistered() throws {
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
        let byteArraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ByteArray"),
        ]))
        let byteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("readBytes"),
        ]

        let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == urlType
                && signature.parameterTypes.isEmpty
                && signature.returnType == byteArrayType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_url_readBytes")
    }

    func testURLReadBytesFunctionResolvesInSource() throws {
        let source = """
        import java.net.URL
        import kotlin.io.readBytes

        fun read(url: URL): ByteArray = url.readBytes()
        """

        _ = try makeSema(source: source)
    }
}
