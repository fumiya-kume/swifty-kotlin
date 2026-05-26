@testable import CompilerCore
import XCTest

final class KotlinIOStringByteInputStreamFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "String.byteInputStream surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testStringByteInputStreamFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
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
            interner.intern("byteInputStream"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes.isEmpty
                && signature.returnType == byteArrayInputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_string_byteInputStream_default")

        let charsetOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes == [charsetType]
                && signature.returnType == byteArrayInputStreamType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: charsetOverload), "kk_string_byteInputStream")
    }

    func testStringByteInputStreamFunctionsResolveInSource() throws {
        let source = """
        import java.io.ByteArrayInputStream
        import kotlin.io.byteInputStream
        import kotlin.text.Charsets

        fun defaultStream(value: String): ByteArrayInputStream = value.byteInputStream()
        fun charsetStream(value: String): ByteArrayInputStream = value.byteInputStream(Charsets.UTF_8)
        """

        _ = try makeSema(source: source)
    }
}
