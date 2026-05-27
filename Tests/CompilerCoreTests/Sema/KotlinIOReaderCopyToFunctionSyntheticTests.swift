@testable import CompilerCore
import XCTest

final class KotlinIOReaderCopyToFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Reader.copyTo surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testReaderCopyToFunctionsAreRegistered() throws {
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
        let writerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("Writer"),
        ]))
        let writerType = sema.types.make(.classType(ClassType(
            classSymbol: writerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("copyTo"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == readerType
                && signature.parameterTypes == [writerType]
                && signature.returnType == sema.types.longType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_reader_copyTo_default")

        let bufferSizeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == readerType
                && signature.parameterTypes == [writerType, sema.types.intType]
                && signature.returnType == sema.types.longType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: bufferSizeOverload), "kk_reader_copyTo")
    }

    func testReaderCopyToFunctionsResolveInSource() throws {
        let source = """
        import java.io.Reader
        import java.io.Writer
        import kotlin.io.copyTo

        fun copyDefault(reader: Reader, writer: Writer): Long = reader.copyTo(writer)
        fun copySized(reader: Reader, writer: Writer): Long = reader.copyTo(writer, 1024)
        """

        _ = try makeSema(source: source)
    }
}
