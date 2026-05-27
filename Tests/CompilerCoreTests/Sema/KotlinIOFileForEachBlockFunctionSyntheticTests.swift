@testable import CompilerCore
import XCTest

final class KotlinIOFileForEachBlockFunctionSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.forEachBlock surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileForEachBlockFunctionsAreRegistered() throws {
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
        let byteArraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ByteArray"),
        ]))
        let byteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let actionType = sema.types.make(.functionType(FunctionType(
            params: [byteArrayType, sema.types.intType],
            returnType: sema.types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let functionFQName = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
            interner.intern("forEachBlock"),
        ]
        let functions = sema.symbols.lookupAll(fqName: functionFQName)

        let defaultOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [actionType]
                && signature.returnType == sema.types.unitType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: defaultOverload), "kk_file_forEachBlock_default")

        let sizedOverload = try XCTUnwrap(functions.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == fileType
                && signature.parameterTypes == [sema.types.intType, actionType]
                && signature.returnType == sema.types.unitType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: sizedOverload), "kk_file_forEachBlock")
    }

    func testFileForEachBlockFunctionsResolveInSource() throws {
        let source = """
        import java.io.File

        fun consume(file: File) {
            file.forEachBlock { buffer, bytesRead ->
                println(buffer)
                println(bytesRead)
            }
            file.forEachBlock(1024) { buffer, bytesRead ->
                println(buffer)
                println(bytesRead)
            }
        }
        """

        _ = try makeSema(source: source)
    }
}
