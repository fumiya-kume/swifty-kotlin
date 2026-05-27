@testable import CompilerCore
import XCTest

final class KotlinIOFileCopyToFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.copyTo surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileCopyToFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("copyTo"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType]
                && signature.returnType == fileType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_file_copyTo_default")

        let overwriteOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType, sema.types.booleanType]
                && signature.returnType == fileType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: overwriteOverload), "kk_file_copyTo_overwrite")

        let fullOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType, sema.types.booleanType, sema.types.intType]
                && signature.returnType == fileType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: fullOverload), "kk_file_copyTo")
    }

    func testFileCopyToFunctionsResolveInSource() throws {
        let source = """
        import java.io.File

        fun copyDefault(source: File, target: File): File = source.copyTo(target)
        fun copyOverwrite(source: File, target: File): File = source.copyTo(target, true)
        fun copySized(source: File, target: File): File = source.copyTo(target, true, 1024)
        """

        _ = try makeSema(source: source)
    }
}
