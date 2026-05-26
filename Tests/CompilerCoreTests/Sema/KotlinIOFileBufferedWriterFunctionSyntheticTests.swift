@testable import CompilerCore
import XCTest

final class KotlinIOFileBufferedWriterFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.bufferedWriter surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileBufferedWriterFunctionIsRegistered() throws {
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
        let bufferedWriterSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("BufferedWriter"),
        ]))
        let bufferedWriterType = sema.types.make(.classType(ClassType(
            classSymbol: bufferedWriterSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("bufferedWriter"),
        ]

        let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_file_bufferedWriter")
    }

    func testFileBufferedWriterFunctionResolvesInSource() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.File

        fun writer(file: File): BufferedWriter = file.bufferedWriter()
        """

        _ = try makeSema(source: source)
    }
}
