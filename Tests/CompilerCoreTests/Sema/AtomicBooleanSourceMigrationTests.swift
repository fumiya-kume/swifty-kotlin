#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1110: the canonical `kotlin.concurrent.atomics.AtomicBoolean(Boolean)`
/// constructor is represented by a source-backed factory until the receiver
/// members are migrated by KSP-1111.
@Suite(.serialized)
struct AtomicBooleanSourceMigrationTests {
    @Test
    func testAtomicBooleanConstructorIsSourceBackedAtCanonicalPackage() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicBoolean

        fun makeFlag(): AtomicBoolean = AtomicBoolean(true)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected AtomicBoolean constructor source to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let constructorFQName = ["kotlin", "concurrent", "atomics", "AtomicBoolean"].map(interner.intern)
            let underlyingFQName = ["kotlin", "concurrent", "AtomicBoolean"].map(interner.intern)
            let underlyingSymbol = try #require(sema.symbols.lookup(fqName: underlyingFQName))
            let expectedReturn = sema.types.make(.classType(ClassType(
                classSymbol: underlyingSymbol,
                args: [],
                nullability: .nonNull
            )))

            let factory = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [sema.types.booleanType]
                    && signature.returnType == expectedReturn
            })

            let symbol = try #require(sema.symbols.symbol(factory))
            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(factory))
            #expect(sema.symbols.externalLinkName(for: factory) == nil)
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: factory))
            #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/atomics/AtomicBoolean/Stdlib.kt")

            let annotations = sema.symbols.annotations(for: factory)
            #expect(
                annotations.contains { $0.annotationFQName == "kotlin.concurrent.atomics.ExperimentalAtomicApi" },
                "Expected ExperimentalAtomicApi annotation, got: \(annotations.map(\.annotationFQName))"
            )
            #expect(annotations.contains {
                $0.annotationFQName == "SinceKotlin"
                    && $0.arguments.contains(where: { $0.contains("2.1") })
            })

            let ast = try #require(ctx.ast)
            let call = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(callee, _, _, range) = expr,
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      interner.resolve(name) == "AtomicBoolean"
                else {
                    return nil
                }
                return exprID
            }.first)
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee == factory)
        }
    }
}
#endif
