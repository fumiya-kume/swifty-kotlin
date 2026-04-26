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
}
