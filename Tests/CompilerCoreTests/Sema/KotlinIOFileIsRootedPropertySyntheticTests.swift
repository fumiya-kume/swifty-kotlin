@testable import CompilerCore
import XCTest

final class KotlinIOFileIsRootedPropertySyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.isRooted surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileIsRootedPropertyIsRegistered() throws {
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
            interner.intern("isRooted"),
        ]

        let propertySymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: symbolID) == fileType
        })
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.booleanType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_file_isRooted")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_file_isRooted")
        XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.receiverType, fileType)
        XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.returnType, sema.types.booleanType)
    }

    func testFileIsRootedPropertyResolvesInSource() throws {
        let source = """
        import java.io.File
        import kotlin.io.isRooted

        fun rooted(file: File): Boolean = file.isRooted
        """

        _ = try makeSema(source: source)
    }
}
