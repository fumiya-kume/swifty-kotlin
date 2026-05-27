@testable import CompilerCore
import XCTest

final class KotlinIOFileCopyRecursivelyFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.copyRecursively surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileCopyRecursivelyFunctionsAreRegistered() throws {
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
            interner.intern("copyRecursively"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType]
                && signature.returnType == sema.types.booleanType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_file_copyRecursively_default")

        let overwriteOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [fileType, sema.types.booleanType]
                && signature.returnType == sema.types.booleanType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: overwriteOverload), "kk_file_copyRecursively_overwrite")
    }

    func testFileCopyRecursivelyFunctionsResolveInSource() throws {
        let source = """
        import java.io.File

        fun copyDefault(source: File, target: File): Boolean = source.copyRecursively(target)
        fun copyOverwrite(source: File, target: File): Boolean = source.copyRecursively(target, true)
        """

        _ = try makeSema(source: source)
    }
}
