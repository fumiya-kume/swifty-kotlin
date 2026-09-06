class CollectionLiteralLoweringSupport {}

struct CollectionLiteralLookupRegistry {
    static let name = "CollectionLiteralLookupTables"

    let tables: CollectionLiteralLookupTables

    init(interner: StringInterner) {
        tables = CollectionLiteralLookupTables(interner: interner)
    }
}

final class CollectionLiteralConstructionLoweringPass: CollectionLiteralLoweringSupport {
    static let name = "CollectionLiteralConstructionLowering"
}

final class CollectionVirtualCallRewriteLoweringPass: CollectionLiteralLoweringSupport {
    static let name = "CollectionVirtualCallRewrite"

    func lowerVirtualCallInstruction(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        arguments: [KIRExprID],
        result: KIRExprID?,
        origCanThrow: Bool,
        origThrownResult: KIRExprID?,
        functionBody: [KIRInstruction],
        module: KIRModule,
        ctx: KIRContext,
        lookup: CollectionLiteralLookupTables,
        state: inout CollectionRewriteState,
        loweredBody: inout [KIRInstruction]
    ) -> Bool {
        rewriteVirtualCallInstruction(
            symbol: symbol,
            callee: callee,
            receiver: receiver,
            arguments: arguments,
            result: result,
            origCanThrow: origCanThrow,
            origThrownResult: origThrownResult,
            context: .init(
                module: module,
                lookup: lookup,
                functionBody: functionBody,
                sema: ctx.sema,
                interner: ctx.interner
            ),
            listExprIDs: &state.listExprIDs,
            setExprIDs: &state.setExprIDs,
            mapExprIDs: &state.mapExprIDs,
            arrayExprIDs: &state.arrayExprIDs,
            sequenceExprIDs: &state.sequenceExprIDs,
            rangeExprIDs: &state.rangeExprIDs,
            charRangeExprIDs: &state.charRangeExprIDs,
            ulongRangeExprIDs: &state.ulongRangeExprIDs,
            fileExprIDs: &state.fileExprIDs,
            pathExprIDs: &state.pathExprIDs,
            indexingIterableExprIDs: &state.indexingIterableExprIDs,
            listIteratorExprIDs: &state.listIteratorExprIDs,
            loweredBody: &loweredBody
        )
    }
}

struct CollectionLiteralLoweringRegistry {
    let lookupRegistry: CollectionLiteralLookupRegistry
    let constructionPass: CollectionLiteralConstructionLoweringPass
    let virtualCallRewritePass: CollectionVirtualCallRewriteLoweringPass

    init(interner: StringInterner) {
        lookupRegistry = CollectionLiteralLookupRegistry(interner: interner)
        constructionPass = CollectionLiteralConstructionLoweringPass()
        virtualCallRewritePass = CollectionVirtualCallRewriteLoweringPass()
    }

    var componentNames: [String] {
        [
            CollectionLiteralLookupRegistry.name,
            CollectionLiteralConstructionLoweringPass.name,
            CollectionVirtualCallRewriteLoweringPass.name,
        ]
    }

    func run(module: KIRModule, ctx: KIRContext, recordAs loweringName: String) throws {
        let lookup = lookupRegistry.tables
        let builderLambdaKinds = constructionPass.collectBuilderLambdaKinds(
            module: module,
            lookup: lookup,
            ctx: ctx
        )

        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated = function
            var state = CollectionLiteralLoweringSupport.CollectionRewriteState()

            constructionPass.collectInitialCollectionExprIDs(
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
                fileExprIDs: &state.fileExprIDs,
                pathExprIDs: &state.pathExprIDs
            )

            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count + 32)

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, _, _):
                    constructionPass.lowerCallInstruction(
                        instruction: instruction,
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
                    )

                case let .virtualCall(symbol, callee, receiver, arguments, result, origCanThrow, origThrownResult, _):
                    if virtualCallRewritePass.lowerVirtualCallInstruction(
                        symbol: symbol,
                        callee: callee,
                        receiver: receiver,
                        arguments: arguments,
                        result: result,
                        origCanThrow: origCanThrow,
                        origThrownResult: origThrownResult,
                        functionBody: function.body,
                        module: module,
                        ctx: ctx,
                        lookup: lookup,
                        state: &state,
                        loweredBody: &loweredBody
                    ) {
                        continue
                    }
                    loweredBody.append(instruction)

                case let .copy(from, to):
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
        module.recordLowering(loweringName)
    }
}
