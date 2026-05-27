@testable import CompilerCore
import XCTest

final class KotlinIOFilePrintWriterFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.printWriter surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFilePrintWriterFunctionIsRegistered() throws {
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
        let printWriterSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("PrintWriter"),
        ]))
        let printWriterType = sema.types.make(.classType(ClassType(
            classSymbol: printWriterSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("printWriter"),
        ]

        let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes.isEmpty
                && signature.returnType == printWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_file_printWriter")
    }

    func testFilePrintWriterFunctionResolvesInSource() throws {
        let source = """
        import java.io.File
        import java.io.PrintWriter

        fun writer(file: File): PrintWriter = file.printWriter()
        fun write(file: File) {
            file.printWriter().write("hello")
        }
        """

        _ = try makeSema(source: source)
    }
}
