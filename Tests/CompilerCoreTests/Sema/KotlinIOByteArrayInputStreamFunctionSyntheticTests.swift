@testable import CompilerCore
import XCTest

final class KotlinIOByteArrayInputStreamFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "ByteArray.inputStream surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testByteArrayInputStreamFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let byteArraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ByteArray"),
        ]))
        let byteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let byteArrayInputStreamSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("ByteArrayInputStream"),
        ]))
        let byteArrayInputStreamType = sema.types.make(.classType(ClassType(
            classSymbol: byteArrayInputStreamSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("inputStream"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == byteArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == byteArrayInputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_bytearray_inputStream")

        let rangeOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == byteArrayType
                && signature.parameterTypes == [sema.types.intType, sema.types.intType]
                && signature.returnType == byteArrayInputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: rangeOverload), "kk_bytearray_inputStream_range")
    }

    func testByteArrayInputStreamFunctionsResolveInSource() throws {
        let source = """
        import java.io.ByteArrayInputStream
        import kotlin.io.inputStream

        fun stream(bytes: ByteArray): ByteArrayInputStream = bytes.inputStream()
        fun streamRange(bytes: ByteArray): ByteArrayInputStream = bytes.inputStream(1, 2)
        """

        _ = try makeSema(source: source)
    }
}
