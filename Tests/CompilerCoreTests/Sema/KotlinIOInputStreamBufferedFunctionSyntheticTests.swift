@testable import CompilerCore
import XCTest

final class KotlinIOInputStreamBufferedFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "InputStream.buffered surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testInputStreamBufferedFunctionsAreRegistered() throws {
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
        let bufferedInputStreamSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("BufferedInputStream"),
        ]))
        let bufferedInputStreamType = sema.types.make(.classType(ClassType(
            classSymbol: bufferedInputStreamSymbol,
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
            return signature.receiverType == inputStreamType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedInputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_input_stream_buffered_default")

        let bufferSizeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == bufferedInputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: bufferSizeOverload), "kk_input_stream_buffered")
    }

    func testInputStreamBufferedFunctionsResolveInSource() throws {
        let source = """
        import java.io.BufferedInputStream
        import java.io.InputStream
        import kotlin.io.buffered

        fun defaultBuffered(input: InputStream): BufferedInputStream = input.buffered()
        fun sizedBuffered(input: InputStream): BufferedInputStream = input.buffered(1024)
        """

        _ = try makeSema(source: source)
    }
}
