import Foundation

extension CollectionLiteralLoweringPass {
    func collectBuilderLambdaKinds(
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        interner: StringInterner
    ) -> [InternedString: InternedString] {
        var symbolToFuncName: [SymbolID: InternedString] = [:]
        for decl in module.arena.declarations {
            if case let .function(funcDecl) = decl {
                symbolToFuncName[funcDecl.symbol] = funcDecl.name
            }
        }

        var builderLambdaKinds: [InternedString: InternedString] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }

            let (exprSymbolMap, entries) = scanBuilderLambdaEntries(
                body: function.body, lookup: lookup
            )

            for entry in entries {
                if let symbol = exprSymbolMap[entry.argID] {
                    let lambdaName = interner.intern("kk_lambda_\(entry.argID)")
                    builderLambdaKinds[lambdaName] = entry.callee
                    if let funcName = symbolToFuncName[symbol] {
                        builderLambdaKinds[funcName] = entry.callee
                    }
                }
            }
        }
        return builderLambdaKinds
    }

    private func scanBuilderLambdaEntries(
        body: [KIRInstruction],
        lookup: CollectionLiteralLookupTables
    ) -> (exprSymbolMap: [Int32: SymbolID], entries: [(argID: Int32, callee: InternedString)]) {
        var exprSymbolMap: [Int32: SymbolID] = [:]
        var entries: [(argID: Int32, callee: InternedString)] = []
        for instruction in body {
            switch instruction {
            case let .constValue(result, .symbolRef(symbol)):
                exprSymbolMap[result.rawValue] = symbol
            case let .call(symbol, callee, arguments, _, _, _, _):
                if symbol == nil, lookup.builderDSLNames.contains(callee), !arguments.isEmpty {
                    entries.append((argID: arguments[0].rawValue, callee: callee))
                }
            default:
                break
            }
        }
        return (exprSymbolMap, entries)
    }

    func collectInitialCollectionExprIDs(
        function: KIRFunction,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>
    ) {
        for instruction in function.body {
            switch instruction {
            case let .call(_, callee, arguments, result, _, _, _):
                if lookup.listFactoryNames.contains(callee) || callee == lookup.kkListOfName {
                    if let result { listExprIDs.insert(result.rawValue) }
                } else if callee == lookup.kkStringSplitName {
                    if let result { listExprIDs.insert(result.rawValue) }
                } else if lookup.mapFactoryNames.contains(callee) || callee == lookup.kkMapOfName {
                    if let result { mapExprIDs.insert(result.rawValue) }
                } else if lookup.arrayOfFactoryNames.contains(callee) {
                    if let result { arrayExprIDs.insert(result.rawValue) }
                }

                if callee == lookup.asSequenceName, arguments.count == 1 {
                    if let result { sequenceExprIDs.insert(result.rawValue) }
                } else if callee == lookup.toListName, arguments.count == 1 {
                    if sequenceExprIDs.contains(arguments[0].rawValue) {
                        if let result { listExprIDs.insert(result.rawValue) }
                    }
                } else if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.takeName {
                    if !arguments.isEmpty, sequenceExprIDs.contains(arguments[0].rawValue) {
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                    }
                }
            case let .virtualCall(_, callee, receiver, _, result, _, _, _):
                if callee == lookup.asSequenceName {
                    if let result { sequenceExprIDs.insert(result.rawValue) }
                } else if callee == lookup.kkStringSplitName {
                    if let result { listExprIDs.insert(result.rawValue) }
                } else if callee == lookup.toListName {
                    if sequenceExprIDs.contains(receiver.rawValue) {
                        if let result { listExprIDs.insert(result.rawValue) }
                    }
                } else if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.takeName {
                    if sequenceExprIDs.contains(receiver.rawValue) {
                        if let result { sequenceExprIDs.insert(result.rawValue) }
                    }
                }
            case let .copy(from, to):
                if listExprIDs.contains(from.rawValue) {
                    listExprIDs.insert(to.rawValue)
                }
                if mapExprIDs.contains(from.rawValue) {
                    mapExprIDs.insert(to.rawValue)
                }
                if arrayExprIDs.contains(from.rawValue) {
                    arrayExprIDs.insert(to.rawValue)
                }
                if sequenceExprIDs.contains(from.rawValue) {
                    sequenceExprIDs.insert(to.rawValue)
                }
            default:
                break
            }
        }
    }
}
