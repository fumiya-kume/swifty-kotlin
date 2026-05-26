@testable import CompilerCore
import XCTest

final class KotlinIOOutputStreamBufferedFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "OutputStream.buffered surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testOutputStreamBufferedFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let outputStreamSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("OutputStream"),
        ]))
        let outputStreamType = sema.types.make(.classType(ClassType(
            classSymbol: outputStreamSymbol,
            args: [],
            nullability: .nonNull
        )))
        let bufferedOutputStreamSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("BufferedOutputStream"),
        ]))
        let bufferedOutputStreamType = sema.types.make(.classType(ClassType(
            classSymbol: bufferedOutputStreamSymbol,
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
            return signature.receiverType == outputStreamType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedOutputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_output_stream_buffered_default")

        let bufferSizeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == outputStreamType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == bufferedOutputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: bufferSizeOverload), "kk_output_stream_buffered")
    }

    func testOutputStreamBufferedFunctionsResolveInSource() throws {
        let source = """
        import java.io.BufferedOutputStream
        import java.io.OutputStream
        import kotlin.io.buffered

        fun defaultBuffered(output: OutputStream): BufferedOutputStream = output.buffered()
        fun sizedBuffered(output: OutputStream): BufferedOutputStream = output.buffered(1024)
        """

        _ = try makeSema(source: source)
    }
}
