@testable import CompilerCore
import XCTest

final class KotlinIOFileDeleteRecursivelyFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.deleteRecursively surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileDeleteRecursivelyFunctionIsRegistered() throws {
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
        let functions = sema.symbols.lookupAll(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("deleteRecursively"),
        ])

        let deleteRecursively = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == []
                && signature.returnType == sema.types.booleanType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: deleteRecursively), "kk_file_deleteRecursively")
    }

    func testFileDeleteRecursivelyFunctionResolvesInSource() throws {
        let source = """
        import java.io.File

        fun removeAll(file: File): Boolean = file.deleteRecursively()
        """

        _ = try makeSema(source: source)
    }
}
