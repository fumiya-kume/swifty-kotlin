@testable import CompilerCore
import XCTest

final class KotlinIOFileExtensionPropertySyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.extension surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let propertyFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("extension"),
        ]

        let propertySymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: symbolID) == fileType
        })
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.stringType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_file_extension")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_file_extension")
        XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.receiverType, fileType)
        XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.returnType, sema.types.stringType)
    }

    func testFileExtensionPropertyResolvesInSource() throws {
        let source = """
        import java.io.File
        import kotlin.io.extension

        fun extensionOf(file: File): String = file.extension
        """

        _ = try makeSema(source: source)
    }
}
