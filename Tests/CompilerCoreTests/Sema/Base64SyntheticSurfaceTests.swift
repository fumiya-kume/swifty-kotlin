@testable import CompilerCore
import XCTest

final class Base64SyntheticSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Base64 surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func base64Symbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
        ]))
    }

    private func byteArrayType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ByteArray"),
        ]))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func testBase64VariantObjectsAreRegisteredAsBase64Subtypes() throws {
        let (sema, interner) = try makeSema()
        let base64 = try base64Symbol(sema: sema, interner: interner)

        for variant in ["Default", "UrlSafe", "Mime", "Pem", "PemMime"] {
            let variantSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern(variant),
            ]), "Base64.\(variant) must be registered")
            let symbol = try XCTUnwrap(sema.symbols.symbol(variantSymbol))
            XCTAssertEqual(symbol.kind, .object)
            XCTAssertEqual(sema.symbols.parentSymbol(for: variantSymbol), base64)
            XCTAssertTrue(
                sema.symbols.directSupertypes(for: variantSymbol).contains(base64),
                "Base64.\(variant) must inherit Base64"
            )
        }
    }

    func testBase64VariantExpressionsTypeCheckAsBase64() throws {
        let source = """
        import kotlin.io.encoding.Base64

        fun defaultVariant(): Base64 = Base64.Default
        fun urlSafeVariant(): Base64 = Base64.UrlSafe
        fun mimeVariant(): Base64 = Base64.Mime
        fun pemVariant(): Base64 = Base64.Pem
        fun pemMimeVariant(): Base64 = Base64.PemMime
        """
        let (sema, interner) = try makeSema(source: source)
        let base64 = try base64Symbol(sema: sema, interner: interner)
        let base64Type = sema.types.make(.classType(ClassType(
            classSymbol: base64,
            args: [],
            nullability: .nonNull
        )))

        for variant in ["Default", "UrlSafe", "Mime", "Pem", "PemMime"] {
            let variantSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern(variant),
            ]))
            let variantType = sema.types.make(.classType(ClassType(
                classSymbol: variantSymbol,
                args: [],
                nullability: .nonNull
            )))
            XCTAssertTrue(
                sema.types.isSubtype(variantType, base64Type),
                "Base64.\(variant) must be assignable to Base64"
            )
        }
    }

    func testBase64EncodeDecodeMemberLinksAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let base64 = try base64Symbol(sema: sema, interner: interner)
        let base64Type = sema.types.make(.classType(ClassType(
            classSymbol: base64,
            args: [],
            nullability: .nonNull
        )))
        let byteArray = try byteArrayType(sema: sema, interner: interner)

        let encode = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
            interner.intern("encode"),
        ]))
        let encodeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: encode))
        XCTAssertEqual(encodeSignature.receiverType, base64Type)
        XCTAssertEqual(encodeSignature.parameterTypes, [byteArray])
        XCTAssertEqual(encodeSignature.returnType, sema.types.stringType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: encode), "kk_base64_encode_default")

        let decode = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
            interner.intern("decode"),
        ]))
        let decodeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: decode))
        XCTAssertEqual(decodeSignature.receiverType, base64Type)
        XCTAssertEqual(decodeSignature.parameterTypes, [sema.types.stringType])
        XCTAssertEqual(decodeSignature.returnType, byteArray)
        XCTAssertEqual(sema.symbols.externalLinkName(for: decode), "kk_base64_decode_default")
    }

    func testBase64EncodeDecodeCallsTypeCheckOnVariants() throws {
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun useBase64(source: ByteArray): ByteArray {
            val encoded: String = Base64.Default.encode(source)
            return Base64.Default.decode(encoded)
        }

        @OptIn(ExperimentalEncodingApi::class)
        fun useUrlSafe(source: ByteArray): String =
            Base64.UrlSafe.encode(source)
        """

        _ = try makeSema(source: source)
    }
}
