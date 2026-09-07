#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-975: Iterable.flatten is a bundled source extension whose generic
/// receiver must coexist with the more specific List.flatten overload.
@Suite
struct IterableFlattenSourceMigrationTests {
    @Test
    func iterableFlattenResolvesToBundledSourceAndPreservesListOverload() throws {
        let source = """
        fun probeList(values: List<List<Int>>): List<Int> = values.flatten()
        fun probeIterable(values: Iterable<Iterable<Int>>): List<Int> = values.flatten()
        fun probeLocal(values: List<List<Int>>): List<Int> {
            val iterable: Iterable<Iterable<Int>> = values
            return iterable.flatten()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(callee) == "flatten"
                else {
                    return nil
                }
                return exprID
            }
            #expect(callExprIDs.count == 3, "Expected List, Iterable, and local Iterable flatten calls")

            var receiverOwners: [[String]] = []
            for callExprID in callExprIDs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    "Expected a Sema binding for flatten"
                )
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)

                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let receiverType = sema.types.makeNonNullable(try #require(signature.receiverType))
                if case let .classType(classType) = sema.types.kind(of: receiverType),
                   let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                {
                    receiverOwners.append(receiverSymbol.fqName.map(ctx.interner.resolve))
                }

                let resultType = try #require(sema.bindings.exprType(for: callExprID))
                guard case let .classType(resultClass) = sema.types.kind(of: sema.types.makeNonNullable(resultType)) else {
                    Issue.record("Expected flatten to return a List")
                    continue
                }
                #expect(
                    sema.symbols.symbol(resultClass.classSymbol)?.fqName.map(ctx.interner.resolve)
                        == ["kotlin", "collections", "List"]
                )
            }

            #expect(receiverOwners.contains(["kotlin", "collections", "List"]))
            #expect(receiverOwners.contains(["kotlin", "collections", "Iterable"]))

            let iterableFQName = ["kotlin", "collections", "flatten"].map(ctx.interner.intern)
            let iterableSourceSymbols = sema.symbols.lookupAll(fqName: iterableFQName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID),
                      ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/Iterables.kt",
                      let receiverType = sema.symbols.functionSignature(for: symbolID)?.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    return false
                }
                return receiverSymbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "Iterable"]
            }
            #expect(iterableSourceSymbols.count == 1)
            #expect(iterableSourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        }
    }
}
#endif
