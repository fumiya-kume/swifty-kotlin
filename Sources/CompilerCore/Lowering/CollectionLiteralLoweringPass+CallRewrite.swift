import Foundation
import RuntimeABI

extension CollectionLiteralLoweringPass {

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func rewriteCalls(module: KIRModule, ctx: KIRContext) throws {
        let lookup = CollectionLiteralLookupTables(interner: ctx.interner)
        let builderLambdaKinds = collectBuilderLambdaKinds(
            module: module,
            lookup: lookup,
            interner: ctx.interner
        )

        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated: KIRFunction = function

            // Phase 1: Identify collection-typed expression IDs
            var state = CollectionRewriteState()

            collectInitialCollectionExprIDs(
                function: function,
                lookup: lookup,
                arena: module.arena,
                sema: ctx.sema,
                interner: ctx.interner,
                listExprIDs: &state.listExprIDs,
                setExprIDs: &state.setExprIDs,
                mapExprIDs: &state.mapExprIDs,
                arrayExprIDs: &state.arrayExprIDs,
                sequenceExprIDs: &state.sequenceExprIDs,
                rangeExprIDs: &state.rangeExprIDs,
                charRangeExprIDs: &state.charRangeExprIDs,
                ulongRangeExprIDs: &state.ulongRangeExprIDs,
                stringExprIDs: &state.stringExprIDs,
                fileExprIDs: &state.fileExprIDs
            )

            // Phase 2: Rewrite instructions
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count + 32)

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, _, _):
                    if rewriteFactoryAndBuilderCall(
                        symbol: symbol,
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        function: function,
                        builderLambdaKinds: builderLambdaKinds,
                        module: module,
                        ctx: ctx,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }

                    if rewriteFileCall(
                        symbol: symbol,
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        module: module,
                        ctx: ctx,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }

                    if rewriteArrayAndIteratorBridgeCall(
                        symbol: symbol,
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        module: module,
                        ctx: ctx,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }

                    if rewriteCollectionMemberCall(
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        module: module,
                        ctx: ctx,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }

                    if rewriteSequenceCollectionCall(
                        symbol: symbol,
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        instruction: instruction,
                        module: module,
                        ctx: ctx,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }

                    if rewriteHigherOrderCollectionCall(
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        function: function,
                        module: module,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }

                    if rewriteRuntimeAdapterCall(
                        callee: callee,
                        arguments: arguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        function: function,
                        module: module,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }

                    // Default: keep instruction as-is
                    loweredBody.append(instruction)

                case let .virtualCall(_, callee, receiver, arguments, result, origCanThrow, origThrownResult, _):
                    if rewriteVirtualCallInstruction(
                        callee: callee,
                        receiver: receiver,
                        arguments: arguments,
                        result: result,
                        origCanThrow: origCanThrow,
                        origThrownResult: origThrownResult,
                        context: .init(module: module, lookup: lookup, functionBody: function.body, sema: ctx.sema, interner: ctx.interner),
                        listExprIDs: &state.listExprIDs,
                        setExprIDs: &state.setExprIDs,
                        mapExprIDs: &state.mapExprIDs,
                        arrayExprIDs: &state.arrayExprIDs,
                        sequenceExprIDs: &state.sequenceExprIDs,
                        rangeExprIDs: &state.rangeExprIDs,
                        charRangeExprIDs: &state.charRangeExprIDs,
                        ulongRangeExprIDs: &state.ulongRangeExprIDs,
                        fileExprIDs: &state.fileExprIDs,
                        indexingIterableExprIDs: &state.indexingIterableExprIDs,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }
                    loweredBody.append(instruction)

                case let .copy(from, to):
                    // Track copies of collection expressions
                    state.propagateCopy(from: from, to: to)
                    loweredBody.append(instruction)

                default:
                    loweredBody.append(instruction)
                }
            }

            updated.replaceBody(loweredBody)
            return updated
        }
        module.arena.transformFunctions(transformFunction)
        module.recordLowering(Self.name)
    }
}
