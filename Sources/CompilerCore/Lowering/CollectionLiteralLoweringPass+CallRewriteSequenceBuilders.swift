/// Sequence and iterator builder call rewrites.
extension CollectionLiteralLoweringPass {
    func rewriteSequenceBuilderCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
    // sequence { ... } builder → kk_sequence_builder_build
    if callee == lookup.sequenceName, arguments.count == 1 || arguments.count == 2 {
        loweredBody.append(.call(
            symbol: nil,
            callee: lookup.kkSequenceBuilderBuildName,
            arguments: arguments,
            result: result,
            canThrow: canThrow,
            thrownResult: thrownResult
        ))
        if let result { state.sequenceExprIDs.insert(result.rawValue) }
        return true
    }

    // iterator { ... } builder → kk_iterator_builder_build (STDLIB-331)
    // Mirror the sequence {} builder rewrite. The sema layer
    // already special-cases the synthetic stdlib builder, so
    // by this point plain `iterator { ... }` should refer to
    // kotlin.sequences.iterator rather than a user-defined
    // overload. Keep the runtime call non-throwing.
    if callee == lookup.iteratorBuilderName, arguments.count == 1, symbol == nil {
        loweredBody.append(.call(
            symbol: nil,
            callee: lookup.kkIteratorBuilderBuildName,
            arguments: arguments,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        if let result { state.iteratorBuilderExprIDs.insert(result.rawValue) }
        return true
    }

    // yield(value) inside sequence builder → kk_sequence_builder_yield
    if callee == lookup.yieldName, arguments.count == 2 {
        loweredBody.append(.call(
            symbol: nil,
            callee: lookup.kkSequenceBuilderYieldName,
            arguments: arguments,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return true
    }

    // yieldAll(iterable) inside sequence builder → kk_sequence_builder_yieldAll (STDLIB-553)
    if callee == lookup.yieldAllName, arguments.count == 2 {
        loweredBody.append(.call(
            symbol: nil,
            callee: lookup.kkSequenceBuilderYieldAllName,
            arguments: arguments,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return true
    }

        return false
    }
}
