@testable import CompilerCore
import XCTest

final class Base64SyntheticSurfaceTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner, ASTModule) {
        var result: (SemaModule, StringInterner, ASTModule)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Base64 surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner, XCTUnwrap(ctx.ast))
        }
        return try XCTUnwrap(
            result,
            "makeSema failed: semantic context was not created for source: \(source)"
        )
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

    private func paddingOptionType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
            interner.intern("PaddingOption"),
        ]))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func testBase64VariantObjectsAreRegisteredAsBase64Subtypes() throws {
        let (sema, interner, _) = try makeSema()
        let base64 = try base64Symbol(sema: sema, interner: interner)

        for variant in ["Default", "UrlSafe", "Mime", "Pem"] {
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

    func testBase64PaddingOptionEnumEntriesAreRegistered() throws {
        let (sema, interner, _) = try makeSema()
        let paddingOption = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
            interner.intern("PaddingOption"),
        ]))
        let enumType = try paddingOptionType(sema: sema, interner: interner)

        for entry in ["PRESENT", "ABSENT", "PRESENT_OPTIONAL", "ABSENT_OPTIONAL"] {
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern("PaddingOption"),
                interner.intern(entry),
            ]), "Base64.PaddingOption.\(entry) must be registered")
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), paddingOption)
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), enumType)
        }
    }

    func testBase64VariantExpressionsTypeCheckAsBase64() throws {
        let source = """
        import kotlin.io.encoding.Base64

        fun defaultVariant(): Base64 = Base64.Default
        fun urlSafeVariant(): Base64 = Base64.UrlSafe
        fun mimeVariant(): Base64 = Base64.Mime
        fun pemVariant(): Base64 = Base64.Pem
        """
        let (sema, interner, _) = try makeSema(source: source)
        let base64 = try base64Symbol(sema: sema, interner: interner)
        let base64Type = sema.types.make(.classType(ClassType(
            classSymbol: base64,
            args: [],
            nullability: .nonNull
        )))

        for variant in ["Default", "UrlSafe", "Mime", "Pem"] {
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
        let (sema, interner, _) = try makeSema()
        let base64 = try base64Symbol(sema: sema, interner: interner)
        let base64Type = sema.types.make(.classType(ClassType(
            classSymbol: base64,
            args: [],
            nullability: .nonNull
        )))
        let byteArray = try byteArrayType(sema: sema, interner: interner)
        let paddingOption = try paddingOptionType(sema: sema, interner: interner)

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

        let encodeToByteArray = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
            interner.intern("encodeToByteArray"),
        ]))
        let encodeToByteArraySignature = try XCTUnwrap(sema.symbols.functionSignature(for: encodeToByteArray))
        XCTAssertEqual(encodeToByteArraySignature.receiverType, base64Type)
        XCTAssertEqual(encodeToByteArraySignature.parameterTypes, [byteArray])
        XCTAssertEqual(encodeToByteArraySignature.returnType, byteArray)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: encodeToByteArray),
            "kk_base64_encodeToByteArray_default"
        )

        let decodeFromByteArray = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
            interner.intern("decodeFromByteArray"),
        ]))
        let decodeFromByteArraySignature = try XCTUnwrap(sema.symbols.functionSignature(for: decodeFromByteArray))
        XCTAssertEqual(decodeFromByteArraySignature.receiverType, base64Type)
        XCTAssertEqual(decodeFromByteArraySignature.parameterTypes, [byteArray])
        XCTAssertEqual(decodeFromByteArraySignature.returnType, byteArray)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: decodeFromByteArray),
            "kk_base64_decodeFromByteArray_default"
        )

        let withPadding = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("encoding"),
            interner.intern("Base64"),
            interner.intern("withPadding"),
        ]))
        let withPaddingSignature = try XCTUnwrap(sema.symbols.functionSignature(for: withPadding))
        XCTAssertEqual(withPaddingSignature.receiverType, base64Type)
        XCTAssertEqual(withPaddingSignature.parameterTypes, [paddingOption])
        XCTAssertEqual(withPaddingSignature.returnType, base64Type)
        XCTAssertEqual(sema.symbols.externalLinkName(for: withPadding), "kk_base64_withPadding_instance")
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

        @OptIn(ExperimentalEncodingApi::class)
        fun useBase64ByteArray(source: ByteArray): ByteArray {
            val encoded: ByteArray = Base64.Default.encodeToByteArray(source)
            return Base64.Default.decodeFromByteArray(encoded)
        }

        @OptIn(ExperimentalEncodingApi::class)
        fun useCustomPadding(source: ByteArray): ByteArray {
            val custom: Base64 = Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT_OPTIONAL)
            val encoded: String = custom.encode(source)
            return custom.decode(encoded)
        }
        """

        let (sema, interner, ast) = try makeSema(source: source)
        let defaultBase64Symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern("Default"),
            ])
        )
        let defaultBase64Type = sema.types.make(.classType(ClassType(
            classSymbol: defaultBase64Symbol,
            args: [],
            nullability: .nonNull
        )))
        let urlSafeBase64Symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern("UrlSafe"),
            ])
        )
        let urlSafeBase64Type = sema.types.make(.classType(ClassType(
            classSymbol: urlSafeBase64Symbol,
            args: [],
            nullability: .nonNull
        )))
        let defaultEncode = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern("Default"),
                interner.intern("encode"),
            ]),
            "Expected Base64.Default.encode to be registered"
        )
        let defaultDecode = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern("Default"),
                interner.intern("decode"),
            ]),
            "Expected Base64.Default.decode to be registered"
        )
        let urlSafeEncode = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
                interner.intern("UrlSafe"),
                interner.intern("encode"),
            ]),
            "Expected Base64.UrlSafe.encode to be registered"
        )

        let defaultEncodeCall = try XCTUnwrap(
            firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr else { return false }
                return sema.bindings.exprTypes[receiver] == defaultBase64Type
                    && interner.resolve(callee) == "encode"
            },
            "Expected Base64.Default.encode call in AST"
        )
        let defaultDecodeCall = try XCTUnwrap(
            firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr else { return false }
                return sema.bindings.exprTypes[receiver] == defaultBase64Type
                    && interner.resolve(callee) == "decode"
            },
            "Expected Base64.Default.decode call in AST"
        )
        let urlSafeEncodeCall = try XCTUnwrap(
            firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr else { return false }
                return sema.bindings.exprTypes[receiver] == urlSafeBase64Type
                    && interner.resolve(callee) == "encode"
            },
            "Expected Base64.UrlSafe.encode call in AST"
        )

        XCTAssertEqual(
            try XCTUnwrap(sema.bindings.callBinding(for: defaultEncodeCall)?.chosenCallee),
            defaultEncode,
            "Base64.Default.encode must resolve to the default encode member"
        )
        XCTAssertEqual(
            sema.bindings.exprTypes[defaultEncodeCall],
            sema.types.stringType,
            "Base64.Default.encode should return String"
        )
        XCTAssertEqual(
            try XCTUnwrap(sema.bindings.callBinding(for: defaultDecodeCall)?.chosenCallee),
            defaultDecode,
            "Base64.Default.decode must resolve to the default decode member"
        )
        XCTAssertEqual(
            sema.bindings.exprTypes[defaultDecodeCall],
            try byteArrayType(sema: sema, interner: interner),
            "Base64.Default.decode should return ByteArray"
        )
        XCTAssertEqual(
            try XCTUnwrap(sema.bindings.callBinding(for: urlSafeEncodeCall)?.chosenCallee),
            urlSafeEncode,
            "Base64.UrlSafe.encode must resolve to the url-safe encode member"
        )
        XCTAssertEqual(
            sema.bindings.exprTypes[urlSafeEncodeCall],
            sema.types.stringType,
            "Base64.UrlSafe.encode should return String"
        )
    }
}
