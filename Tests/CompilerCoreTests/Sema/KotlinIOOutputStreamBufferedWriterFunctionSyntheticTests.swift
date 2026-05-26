@testable import CompilerCore
import XCTest

final class KotlinIOOutputStreamBufferedWriterFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "OutputStream.bufferedWriter surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testOutputStreamBufferedWriterFunctionsAreRegistered() throws {
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
            interner.intern("bufferedWriter"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == outputStreamType
                && signature.parameterTypes.isEmpty
                && signature.returnType == bufferedWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_output_stream_bufferedWriter_default")

        let charsetOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == outputStreamType
                && signature.parameterTypes == [charsetType]
                && signature.returnType == bufferedWriterType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: charsetOverload), "kk_output_stream_bufferedWriter")
    }

    func testOutputStreamBufferedWriterFunctionsResolveInSource() throws {
        let source = """
        import java.io.BufferedWriter
        import java.io.OutputStream
        import kotlin.io.bufferedWriter
        import kotlin.text.Charsets

        fun defaultWriter(output: OutputStream): BufferedWriter = output.bufferedWriter()
        fun charsetWriter(output: OutputStream): BufferedWriter = output.bufferedWriter(Charsets.UTF_8)
        """

        _ = try makeSema(source: source)
    }
}
