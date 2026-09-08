@testable import CompilerCore
import Testing

/// KSP-976: Iterable.fold/foldIndexed must bind to the generic Iterable source
/// declarations without changing the specialized receiver paths.
@Suite
struct IterableFoldSourceMigrationTests {
    @Test
    func foldFamilyUsesTheExactSourceReceiverForEachCollectionKind() throws {
        let source = """
        fun probe(
            iterable: Iterable<Int>,
            list: List<Int>,
            set: Set<Int>,
            sequence: Sequence<Int>,
            genericArray: Array<Int>,
            primitiveArray: IntArray
        ) {
            iterable.fold(0) { acc, value -> acc + value }
            iterable.foldIndexed(0) { index, acc, value -> acc + index + value }
            list.fold(0) { acc, value -> acc + value }
            list.foldIndexed(0) { index, acc, value -> acc + index + value }
            set.fold(0) { acc, value -> acc + value }
            set.foldIndexed(0) { index, acc, value -> acc + index + value }
            sequence.fold(0) { acc, value -> acc + value }
            sequence.foldIndexed(0) { index, acc, value -> acc + index + value }
            genericArray.fold(0) { acc, value -> acc + value }
            genericArray.foldIndexed(0) { index, acc, value -> acc + index + value }
            primitiveArray.fold(0) { acc, value -> acc + value }
            primitiveArray.foldIndexed(0) { index, acc, value -> acc + index + value }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected fold-family receiver matrix to type-check, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let expected: [(receiver: String, path: String)] = [
            ("kotlin.collections.Iterable", "__bundled_kotlin/collections/Iterables.kt"),
            ("kotlin.collections.Iterable", "__bundled_kotlin/collections/Iterables.kt"),
            ("kotlin.collections.List", "__bundled_kotlin/collections/ListAggregateHOF.kt"),
            ("kotlin.collections.List", "__bundled_kotlin/collections/ListAggregateHOF.kt"),
            ("kotlin.collections.Set", "__bundled_kotlin/collections/SetHOF.kt"),
            ("kotlin.collections.Set", "__bundled_kotlin/collections/SetHOF.kt"),
            ("kotlin.sequences.Sequence", "__bundled_kotlin/sequences/SequenceConversionsAndSetOps.kt"),
            ("kotlin.sequences.Sequence", "__bundled_kotlin/sequences/SequenceConversionsAndSetOps.kt"),
            ("kotlin.Array", "__bundled_kotlin/collections/ArrayAggregateHOF.kt"),
            ("kotlin.Array", "__bundled_kotlin/collections/ArrayAggregateHOF.kt"),
            ("kotlin.IntArray", "__bundled_kotlin/collections/PrimitiveArrayHOF.kt"),
            ("kotlin.IntArray", "__bundled_kotlin/collections/PrimitiveArrayHOF.kt"),
        ]

        let calls: [ExprID] = ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  ["fold", "foldIndexed"].contains(ctx.interner.resolve(callee)),
                  !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            else {
                return nil
            }
            return exprID
        }
        #expect(calls.count == expected.count, "Expected the user receiver matrix to contain \(expected.count) calls, got \(calls.count)")

        for (call, expectation) in zip(calls, expected) {
            let binding = try #require(sema.bindings.callBinding(for: call))
            let callee = try #require(binding.chosenCallee)
            #expect(sema.symbols.isSourceBackedSymbol(callee))
            #expect(sema.symbols.externalLinkName(for: callee) == nil)
            let signature = try #require(sema.symbols.functionSignature(for: callee))
            let receiverType = try #require(signature.receiverType)
            guard case let .classType(classType) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected a nominal source receiver for \(expectation.receiver)")
                continue
            }
            #expect(
                receiverSymbol.fqName.map(ctx.interner.resolve).joined(separator: ".") == expectation.receiver,
                "Expected \(expectation.receiver), got \(receiverSymbol.fqName.map(ctx.interner.resolve).joined(separator: "."))"
            )
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: callee))
            #expect(ctx.sourceManager.path(of: sourceFileID) == expectation.path)
        }
    }
}
