#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MutableDataSourceMigrationTests {
    @Test
    func testMutableDataConstructorIsSourceBackedWithKotlin2310Contract() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected bundled MutableData source to type-check, got: " + String(describing: errors))
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let mutableDataFQName = ["kotlin", "native", "concurrent", "MutableData"].map(interner.intern)
            let mutableDataSymbol = try #require(sema.symbols.lookup(fqName: mutableDataFQName))
            let mutableDataInfo = try #require(sema.symbols.symbol(mutableDataSymbol))
            #expect(mutableDataInfo.kind == .class)
            #expect(mutableDataInfo.visibility == .public)
            #expect(!mutableDataInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(mutableDataSymbol))

            let sourceFileID = try #require(sema.symbols.sourceFileID(for: mutableDataSymbol))
            let expectedSourcePath = "__bundled_kotlin/native/concurrent/MutableData/Stdlib.kt"
            #expect(ctx.sourceManager.path(of: sourceFileID) == expectedSourcePath)

            let mutableDataType = sema.types.make(.classType(ClassType(
                classSymbol: mutableDataSymbol,
                args: [],
                nullability: .nonNull
            )))
            let constructor = try #require(
                sema.symbols.lookupAll(fqName: mutableDataFQName + [interner.intern("<init>")]).first {
                    sema.symbols.symbol($0)?.kind == .constructor
                }
            )
            let constructorInfo = try #require(sema.symbols.symbol(constructor))
            let signature = try #require(sema.symbols.functionSignature(for: constructor))
            #expect(constructorInfo.visibility == .public)
            #expect(!constructorInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(constructor))
            #expect(signature.receiverType == mutableDataType)
            #expect(signature.parameterTypes == [sema.types.intType])
            #expect(signature.returnType == mutableDataType)
            #expect(signature.valueParameterHasDefaultValues == [true])
            let parameterNames = signature.valueParameterSymbols.compactMap { parameterSymbol in
                sema.symbols.symbol(parameterSymbol)?.name
            }.map { interner.resolve($0) }
            #expect(parameterNames == ["capacity"])
            #expect(sema.symbols.externalLinkName(for: constructor) == nil)

            let annotations = sema.symbols.annotations(for: mutableDataSymbol)
            #expect(annotations.contains { $0.annotationFQName == "Deprecated" })
            #expect(
                annotations.contains {
                    $0.annotationFQName == "DeprecatedSinceKotlin"
                        && $0.arguments.contains { $0.contains("errorSince") && $0.contains("2.1") }
                }
            )
        }
    }
}
#endif
