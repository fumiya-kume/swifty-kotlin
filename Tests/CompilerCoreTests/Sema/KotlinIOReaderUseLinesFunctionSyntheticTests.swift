@testable import CompilerCore
import XCTest

final class KotlinIOReaderUseLinesFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Reader.useLines surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testReaderUseLinesFunctionIsRegistered() throws {
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
        let listSymbol = try XCTUnwrap(sema.symbols.lookupByShortName(interner.intern("List")).first)
        let listOfStringType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(sema.types.stringType)],
            nullability: .nonNull
        )))
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [listOfStringType],
            returnType: sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("useLines"),
        ]

        let functionSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == readerType
                && signature.parameterTypes == [blockType]
                && signature.returnType == sema.types.anyType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_reader_useLines")
    }

    func testReaderUseLinesFunctionResolvesInSource() throws {
        let source = """
        import java.io.Reader
        import kotlin.io.useLines

        fun consume(reader: Reader) {
            reader.useLines { lines ->
                lines.forEach { line -> println(line) }
            }
        }
        """

        _ = try makeSema(source: source)
    }
}
