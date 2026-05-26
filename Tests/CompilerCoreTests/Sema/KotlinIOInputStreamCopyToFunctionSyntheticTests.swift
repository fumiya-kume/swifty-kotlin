@testable import CompilerCore
import XCTest

final class KotlinIOInputStreamCopyToFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "InputStream.copyTo surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testInputStreamCopyToFunctionsAreRegistered() throws {
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
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("copyTo"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes == [outputStreamType]
                && signature.returnType == sema.types.longType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_input_stream_copyTo_default")

        let bufferSizeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes == [outputStreamType, sema.types.intType]
                && signature.returnType == sema.types.longType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: bufferSizeOverload), "kk_input_stream_copyTo")
    }

    func testInputStreamCopyToFunctionsResolveInSource() throws {
        let source = """
        import java.io.InputStream
        import java.io.OutputStream
        import kotlin.io.copyTo

        fun copyDefault(input: InputStream, output: OutputStream): Long = input.copyTo(output)
        fun copySized(input: InputStream, output: OutputStream): Long = input.copyTo(output, 1024)
        """

        _ = try makeSema(source: source)
    }
}
