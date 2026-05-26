@testable import CompilerCore
import XCTest

final class KotlinIOFileResolveSiblingFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.resolveSibling surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileResolveSiblingFunctionsAreRegistered() throws {
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
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("resolveSibling"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let fileOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType]
                && signature.returnType == fileType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: fileOverload), "kk_file_resolveSibling_file")

        let stringOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == fileType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: stringOverload), "kk_file_resolveSibling_string")
    }

    func testFileResolveSiblingFunctionsResolveInSource() throws {
        let source = """
        import java.io.File
        import kotlin.io.resolveSibling

        fun withFile(file: File, relative: File): File = file.resolveSibling(relative)
        fun withString(file: File): File = file.resolveSibling("other.txt")
        """

        _ = try makeSema(source: source)
    }
}
