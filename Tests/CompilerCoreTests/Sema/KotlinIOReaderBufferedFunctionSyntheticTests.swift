@testable import CompilerCore
import XCTest

final class KotlinIOReaderBufferedFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Reader.buffered surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testReaderBufferedFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let readerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("Reader"),
        ]))
        let readerType = sema.types.make(.classType(ClassType(
            classSymbol: readerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let bufferedReaderSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("BufferedReader"),
        ]))
        let bufferedReaderType = sema.types.make(.classType(ClassType(
            classSymbol: bufferedReaderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("buffered"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == readerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedReaderType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_reader_buffered_default")

        let bufferSizeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == readerType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == bufferedReaderType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: bufferSizeOverload), "kk_reader_buffered")
    }

    func testReaderBufferedFunctionsResolveInSource() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.Reader
        import kotlin.io.buffered

        fun defaultBuffered(reader: Reader): BufferedReader = reader.buffered()
        fun sizedBuffered(reader: Reader): BufferedReader = reader.buffered(1024)
        """

        _ = try makeSema(source: source)
    }
}
