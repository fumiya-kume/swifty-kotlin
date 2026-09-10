#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-978: Iterable.groupBy/groupByTo must bind to the generic bundled Kotlin
/// source declarations while preserving the existing List owner-specific paths.
@Suite
struct IterableGroupSourceMigrationTests {
    @Test
    func groupFamilyUsesTheExactSourceReceiverForIterableAndList() throws {
        let source = """
        fun iterableGroup(values: Iterable<Int>): Map<Int, List<Int>> {
            return values.groupBy { it % 2 }
        }
        fun iterableGroupTransformed(values: Iterable<Int>): Map<Int, List<String>> {
            return values.groupBy({ it % 2 }, { "v=$it" })
        }
        fun iterableGroupTo(
            values: Iterable<Int>,
            destination: MutableMap<Any, MutableList<Int>>
        ): MutableMap<Any, MutableList<Int>> {
            return values.groupByTo(destination) { it % 2 }
        }
        fun iterableGroupToTransformed(
            values: Iterable<Int>,
            destination: MutableMap<Any, MutableList<Int>>
        ): MutableMap<Any, MutableList<Int>> {
            return values.groupByTo(destination, { it % 2 }, { it * 10 })
        }
        fun listGroup(values: List<Int>): Map<Int, List<Int>> {
            return values.groupBy { it % 2 }
        }
        fun listGroupTo(
            values: List<Int>,
            destination: MutableMap<Int, MutableList<Int>>
        ): MutableMap<Int, MutableList<Int>> {
            return values.groupByTo(destination) { it % 2 }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let userFileID = try #require(
            ctx.sourceManager.fileIDs().first { ctx.sourceManager.origin(of: $0) == .user }
        )
        let expected: [(receiver: String, sourcePath: String)] = [
            ("kotlin.collections.Iterable", "__bundled_kotlin/collections/Iterables.kt"),
            ("kotlin.collections.Iterable", "__bundled_kotlin/collections/Iterables.kt"),
            ("kotlin.collections.Iterable", "__bundled_kotlin/collections/Iterables.kt"),
            ("kotlin.collections.Iterable", "__bundled_kotlin/collections/Iterables.kt"),
            ("kotlin.collections.List", "__bundled_kotlin/collections/ListAssociationHOF.kt"),
            ("kotlin.collections.List", "__bundled_kotlin/collections/ListAssociationHOF.kt"),
        ]
        let calls: [ExprID] = ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  ["groupBy", "groupByTo"].contains(ctx.interner.resolve(callee)),
                  range.start.file == userFileID
            else {
                return nil
            }
            return exprID
        }
        #expect(calls.count == expected.count, "Expected six user group-family calls, got \(calls.count)")

        for (call, expectation) in zip(calls, expected) {
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            #expect(sema.symbols.isSourceBackedSymbol(chosen))
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            let receiverType = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol),
                  let sourceFileID = sema.symbols.sourceFileID(for: chosen)
            else {
                Issue.record("Expected a nominal source receiver for the group-family call")
                continue
            }
            let receiverName = receiverSymbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
            #expect(receiverName == expectation.receiver, "Expected \(expectation.receiver), got \(receiverName)")
            #expect(ctx.sourceManager.path(of: sourceFileID) == expectation.sourcePath)
        }

        let collections = ["kotlin", "collections"].map(ctx.interner.intern)
        let iterable = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("Iterable")]))
        for name in ["groupBy", "groupByTo"] {
            let symbols = sema.symbols.lookupAll(fqName: collections + [ctx.interner.intern(name)]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      receiverClass.classSymbol == iterable,
                      let sourceFileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/collections/Iterables.kt"
            }
            #expect(symbols.count == 2, "Expected two Iterable.\(name) declarations, got \(symbols.count)")
            #expect(symbols.allSatisfy { sema.symbols.isSourceBackedSymbol($0) })
            #expect(symbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
            #expect(symbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true })
        }
    }
}
#endif
