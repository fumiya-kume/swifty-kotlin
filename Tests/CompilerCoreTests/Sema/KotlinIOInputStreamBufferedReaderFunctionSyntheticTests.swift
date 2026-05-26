@testable import CompilerCore
import XCTest

final class KotlinIOInputStreamBufferedReaderFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "InputStream.bufferedReader surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testInputStreamBufferedReaderFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let inputStreamSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("InputStream"),
        ]))
        let inputStreamType = sema.types.make(.classType(ClassType(
            classSymbol: inputStreamSymbol,
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
        let charsetSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Charset"),
        ]))
        let charsetType = sema.types.make(.classType(ClassType(
            classSymbol: charsetSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("bufferedReader"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedReaderType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_input_stream_bufferedReader_default")

        let charsetOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes == [charsetType]
                && signature.returnType == bufferedReaderType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: charsetOverload), "kk_input_stream_bufferedReader")
    }

    func testInputStreamBufferedReaderFunctionsResolveInSource() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.InputStream
        import kotlin.io.bufferedReader
        import kotlin.text.Charsets

        fun defaultReader(input: InputStream): BufferedReader = input.bufferedReader()
        fun charsetReader(input: InputStream): BufferedReader = input.bufferedReader(Charsets.UTF_8)
        """

        _ = try makeSema(source: source)
    }
}
