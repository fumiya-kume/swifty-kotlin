@testable import CompilerCore
import XCTest

final class KotlinIOWriterBufferedFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Writer.buffered surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testWriterBufferedFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
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
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("buffered"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == writerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_writer_buffered_default")

        let bufferSizeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == writerType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == bufferedWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: bufferSizeOverload), "kk_writer_buffered")
    }

    func testWriterBufferedFunctionsResolveInSource() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.Writer
        import kotlin.io.buffered

        fun defaultBuffered(writer: Writer): BufferedWriter = writer.buffered()
        fun sizedBuffered(writer: Writer): BufferedWriter = writer.buffered(1024)
        """

        _ = try makeSema(source: source)
    }
}
