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
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>
    ) {
        for instruction in function.body {
            switch instruction {
            case let .call(_, callee, arguments, result, _, _, _):
                handleCallInstruction(
                    callee: callee, arguments: arguments, result: result,
                    lookup: lookup, listExprIDs: &listExprIDs,
                    setExprIDs: &setExprIDs,
                    mapExprIDs: &mapExprIDs, arrayExprIDs: &arrayExprIDs,
                    sequenceExprIDs: &sequenceExprIDs
                )
            case let .virtualCall(_, callee, receiver, _, result, _, _, _):
                handleVirtualCallInstruction(
                    callee: callee, receiver: receiver, result: result,
                    lookup: lookup, listExprIDs: &listExprIDs,
                    mapExprIDs: &mapExprIDs,
                    sequenceExprIDs: &sequenceExprIDs
                )
            case let .copy(from, to):
                handleCopyInstruction(
                    from: from, to: to,
                    listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
                    setExprIDs: &setExprIDs,
                    arrayExprIDs: &arrayExprIDs, sequenceExprIDs: &sequenceExprIDs
                )
            default:
                break
            }
        }
    }

    private func handleCallInstruction(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>
    ) {
        classifyFactoryCall(
            callee: callee, result: result, lookup: lookup,
            listExprIDs: &listExprIDs, setExprIDs: &setExprIDs,
            mapExprIDs: &mapExprIDs, arrayExprIDs: &arrayExprIDs
        )
        propagateCollectionOperation(
            callee: callee, arguments: arguments, result: result, lookup: lookup,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            sequenceExprIDs: &sequenceExprIDs
        )
    }

    private func classifyFactoryCall(
        callee: InternedString,
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>
    ) {
        guard let result else { return }
        if lookup.listFactoryNames.contains(callee) || callee == lookup.kkListOfName
            || callee == lookup.kkStringSplitName
        {
            listExprIDs.insert(result.rawValue)
        } else if lookup.setFactoryNames.contains(callee) || callee == lookup.kkSetOfName {
            setExprIDs.insert(result.rawValue)
        } else if lookup.mapFactoryNames.contains(callee) || callee == lookup.kkMapOfName {
            mapExprIDs.insert(result.rawValue)
        } else if lookup.arrayOfFactoryNames.contains(callee) {
            arrayExprIDs.insert(result.rawValue)
        }
    }

    private func propagateCollectionOperation(
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>
    ) {
        guard let result, !arguments.isEmpty else { return }
        let src = arguments[0].rawValue
        if callee == lookup.asSequenceName {
            sequenceExprIDs.insert(result.rawValue)
        } else if callee == lookup.toListName, sequenceExprIDs.contains(src) {
            listExprIDs.insert(result.rawValue)
        } else if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.takeName,
                  sequenceExprIDs.contains(src)
        {
            sequenceExprIDs.insert(result.rawValue)
        } else if callee == lookup.groupByName || callee == lookup.associateByName
            || callee == lookup.associateWithName || callee == lookup.associateName,
            listExprIDs.contains(src)
        {
            mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.mapName, mapExprIDs.contains(src) {
            listExprIDs.insert(result.rawValue)
        } else if callee == lookup.filterName, mapExprIDs.contains(src) {
            mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.withIndexName || callee == lookup.takeName || callee == lookup.dropName
            || callee == lookup.reversedName || callee == lookup.sortedName || callee == lookup.distinctName,
            listExprIDs.contains(src)
        {
            listExprIDs.insert(result.rawValue)
        }
    }

    private func handleVirtualCallInstruction(
        callee: InternedString,
        receiver: KIRExprID,
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>
    ) {
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
        } else if callee == lookup.groupByName || callee == lookup.associateByName
            || callee == lookup.associateWithName || callee == lookup.associateName
        {
            if listExprIDs.contains(receiver.rawValue) {
                if let result { mapExprIDs.insert(result.rawValue) }
            }
        } else if callee == lookup.mapName {
            if mapExprIDs.contains(receiver.rawValue) {
                if let result { listExprIDs.insert(result.rawValue) }
            }
        } else if callee == lookup.filterName {
            if mapExprIDs.contains(receiver.rawValue) {
                if let result { mapExprIDs.insert(result.rawValue) }
            }
        } else if callee == lookup.withIndexName {
            if listExprIDs.contains(receiver.rawValue) {
                if let result { listExprIDs.insert(result.rawValue) }
            }
        } else if callee == lookup.takeName || callee == lookup.dropName
            || callee == lookup.reversedName || callee == lookup.sortedName || callee == lookup.distinctName
        {
            if listExprIDs.contains(receiver.rawValue) {
                if let result { listExprIDs.insert(result.rawValue) }
            }
        }
    }

    private func handleCopyInstruction(
        from: KIRExprID,
        to: KIRExprID,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>
    ) {
        if listExprIDs.contains(from.rawValue) {
            listExprIDs.insert(to.rawValue)
        }
        if setExprIDs.contains(from.rawValue) {
            setExprIDs.insert(to.rawValue)
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
    }
}
