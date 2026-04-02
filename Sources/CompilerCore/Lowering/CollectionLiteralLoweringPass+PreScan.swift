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
            case let .call(symbol, callee, arguments, _, _, _, _, _):
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
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        rangeExprIDs: inout Set<Int32>,
        charRangeExprIDs: inout Set<Int32>,
        ulongRangeExprIDs: inout Set<Int32>,
        stringExprIDs: inout Set<Int32>,
        fileExprIDs: inout Set<Int32>
    ) {
        // Seed tracking sets from static type information (LOWERING-001).
        // This covers function parameters, return values, and any expression
        // whose KIR type is a known collection class (List, MutableList, Set,
        // MutableSet, Map, MutableMap, etc.).
        seedCollectionExprIDsFromStaticTypes(
            function: function,
            arena: arena,
            sema: sema,
            interner: interner,
            listExprIDs: &listExprIDs,
            setExprIDs: &setExprIDs,
            mapExprIDs: &mapExprIDs,
            arrayExprIDs: &arrayExprIDs,
            sequenceExprIDs: &sequenceExprIDs,
            stringExprIDs: &stringExprIDs
        )

        // First pass: collect char-valued and ulong-valued expression IDs to detect
        // char range and ULong range arguments (STDLIB-290, STDLIB-524).
        var charValuedExprIDs: Set<Int32> = []
        var ulongValuedExprIDs: Set<Int32> = []
        for instruction in function.body {
            switch instruction {
            case let .call(_, callee, _, result, _, _, _, _):
                if callee == lookup.kkBoxCharName, let result {
                    charValuedExprIDs.insert(result.rawValue)
                }
            case let .constValue(result, .charLiteral):
                charValuedExprIDs.insert(result.rawValue)
            case let .constValue(result, .ulongLiteral):
                ulongValuedExprIDs.insert(result.rawValue)
            case let .copy(from, to):
                if charValuedExprIDs.contains(from.rawValue) {
                    charValuedExprIDs.insert(to.rawValue)
                }
                if ulongValuedExprIDs.contains(from.rawValue) {
                    ulongValuedExprIDs.insert(to.rawValue)
                }
            default:
                break
            }
        }

        if let sema {
            seedULongValuedExprIDsFromStaticTypes(
                function: function,
                arena: arena,
                sema: sema,
                ulongValuedExprIDs: &ulongValuedExprIDs
            )
        }

        for instruction in function.body {
            switch instruction {
            case let .call(_, callee, arguments, result, _, _, _, _):
                handleCallInstruction(
                    callee: callee, arguments: arguments, result: result,
                    lookup: lookup, listExprIDs: &listExprIDs,
                    setExprIDs: &setExprIDs,
                    mapExprIDs: &mapExprIDs, arrayExprIDs: &arrayExprIDs,
                    sequenceExprIDs: &sequenceExprIDs,
                    rangeExprIDs: &rangeExprIDs,
                    charRangeExprIDs: &charRangeExprIDs,
                    charValuedExprIDs: charValuedExprIDs,
                    ulongRangeExprIDs: &ulongRangeExprIDs,
                    ulongValuedExprIDs: ulongValuedExprIDs,
                    stringExprIDs: &stringExprIDs,
                    fileExprIDs: &fileExprIDs
                )
            case let .virtualCall(_, callee, receiver, _, result, _, _, _):
                handleVirtualCallInstruction(
                    callee: callee, receiver: receiver, result: result,
                    lookup: lookup, listExprIDs: &listExprIDs,
                    mapExprIDs: &mapExprIDs,
                    sequenceExprIDs: &sequenceExprIDs,
                    rangeExprIDs: &rangeExprIDs,
                    charRangeExprIDs: &charRangeExprIDs,
                    ulongRangeExprIDs: &ulongRangeExprIDs,
                    stringExprIDs: &stringExprIDs
                )
            case let .copy(from, to):
                handleCopyInstruction(
                    from: from, to: to,
                    listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
                    setExprIDs: &setExprIDs,
                    arrayExprIDs: &arrayExprIDs, sequenceExprIDs: &sequenceExprIDs,
                    rangeExprIDs: &rangeExprIDs,
                    charRangeExprIDs: &charRangeExprIDs,
                    ulongRangeExprIDs: &ulongRangeExprIDs,
                    stringExprIDs: &stringExprIDs,
                    fileExprIDs: &fileExprIDs
                )
            case let .constValue(result, .stringLiteral):
                stringExprIDs.insert(result.rawValue)
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
        sequenceExprIDs: inout Set<Int32>,
        rangeExprIDs: inout Set<Int32>,
        charRangeExprIDs: inout Set<Int32>,
        charValuedExprIDs: Set<Int32>,
        ulongRangeExprIDs: inout Set<Int32>,
        ulongValuedExprIDs: Set<Int32>,
        stringExprIDs: inout Set<Int32>,
        fileExprIDs: inout Set<Int32>
    ) {
        classifyFactoryCall(
            callee: callee, result: result, lookup: lookup,
            listExprIDs: &listExprIDs, setExprIDs: &setExprIDs,
            mapExprIDs: &mapExprIDs, arrayExprIDs: &arrayExprIDs
        )
        // Classify range factory calls
        if let result,
           callee == lookup.kkOpRangeToName || callee == lookup.kkOpRangeUntilName
           || callee == lookup.kkOpULongRangeUntilName
           || callee == lookup.kkOpDownToName || callee == lookup.kkOpStepName
        {
            rangeExprIDs.insert(result.rawValue)
            // Detect CharRange: if any argument is a char-valued expression (STDLIB-290)
            if arguments.contains(where: { charValuedExprIDs.contains($0.rawValue) }) {
                charRangeExprIDs.insert(result.rawValue)
            }
            // Detect ULongRange: if any argument is a ULong-valued expression (STDLIB-524)
            if arguments.contains(where: { ulongValuedExprIDs.contains($0.rawValue) }) {
                ulongRangeExprIDs.insert(result.rawValue)
            }
            // step on a char range propagates char range
            if callee == lookup.kkOpStepName, !arguments.isEmpty,
               charRangeExprIDs.contains(arguments[0].rawValue)
            {
                charRangeExprIDs.insert(result.rawValue)
            }
            // step on a ULong range propagates ULong range (STDLIB-524)
            if callee == lookup.kkOpStepName, !arguments.isEmpty,
               ulongRangeExprIDs.contains(arguments[0].rawValue)
            {
                ulongRangeExprIDs.insert(result.rawValue)
            }
        }
        // Classify sequence factory calls (STDLIB-097, STDLIB-317)
        if let result,
           callee == lookup.sequenceOfName || callee == lookup.generateSequenceName
            || callee == lookup.kkStringAsSequenceName
        {
            sequenceExprIDs.insert(result.rawValue)
        }
        // STDLIB-189: Classify string-producing calls
        if let result, lookup.stringProducingCallees.contains(callee) {
            stringExprIDs.insert(result.rawValue)
        }
        propagateCollectionOperation(
            callee: callee, arguments: arguments, result: result, lookup: lookup,
            listExprIDs: &listExprIDs, mapExprIDs: &mapExprIDs,
            sequenceExprIDs: &sequenceExprIDs,
            stringExprIDs: &stringExprIDs
        )
        // Classify map property accessor results: keys/entries -> set, values -> list.
        if let result {
            if callee == lookup.kkMapKeysName || callee == lookup.kkMapEntriesName {
                setExprIDs.insert(result.rawValue)
            } else if callee == lookup.kkMapValuesName {
                listExprIDs.insert(result.rawValue)
            }
        }
        // STDLIB-565: Classify File constructor calls.
        // KNOWN LIMITATION: Only direct File("...") / kk_file_new constructor
        // calls are seeded here.  File receivers originating from function
        // parameters, return values, or field loads are not tracked, so their
        // member calls will fall through to the default virtualCall path.  A
        // future improvement could use the receiver's static type for dispatch
        // instead of *ExprIDs membership (same pattern as the sequence rewrite
        // limitation noted above).
        if let result,
           callee == lookup.fileConstructorName || callee == lookup.kkFileNewName
        {
            fileExprIDs.insert(result.rawValue)
        }
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
        if lookup.listFactoryNames.contains(callee) || lookup.mutableListConstructorNames.contains(callee)
            || callee == lookup.kkListOfName
            || callee == lookup.kkStringSplitName
            || callee == lookup.kkStringChunkedName
            || callee == lookup.kkStringWindowedName
            || callee == lookup.kkStringAsIterableName
            || callee == lookup.kkArrayToListName
        {
            listExprIDs.insert(result.rawValue)
        } else if lookup.setFactoryNames.contains(callee) || lookup.mutableSetConstructorNames.contains(callee)
                    || callee == lookup.kkSetOfName {
            setExprIDs.insert(result.rawValue)
        } else if lookup.mapFactoryNames.contains(callee) || lookup.mutableMapConstructorNames.contains(callee)
                    || callee == lookup.kkMapOfName {
            mapExprIDs.insert(result.rawValue)
        } else if lookup.arrayOfFactoryNames.contains(callee) || callee == lookup.kkArrayNewName {
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
        sequenceExprIDs: inout Set<Int32>,
        stringExprIDs _: inout Set<Int32>
    ) {
        guard let result, !arguments.isEmpty else { return }
        let src = arguments[0].rawValue
        if callee == lookup.asSequenceName
            || callee == lookup.kkListAsSequenceName
            || callee == lookup.kkArrayAsSequenceName
            || callee == lookup.kkStringAsSequenceName
        {
            sequenceExprIDs.insert(result.rawValue)
        } else if callee == lookup.toListName, sequenceExprIDs.contains(src) {
            listExprIDs.insert(result.rawValue)
        } else if callee == lookup.toMapName, sequenceExprIDs.contains(src) {
            mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.groupByName, sequenceExprIDs.contains(src) {
            mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.flattenName, sequenceExprIDs.contains(src) {
            sequenceExprIDs.insert(result.rawValue)
        } else if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.takeName
            || callee == lookup.flatMapName || callee == lookup.dropName
            || callee == lookup.distinctName || callee == lookup.zipName,
            sequenceExprIDs.contains(src)
        {
            sequenceExprIDs.insert(result.rawValue)
        } else if callee == lookup.kkSequenceMapName || callee == lookup.kkSequenceFilterName
            || callee == lookup.kkSequenceTakeName || callee == lookup.kkSequenceFlatMapName
            || callee == lookup.kkSequenceDropName || callee == lookup.kkSequenceDistinctName
            || callee == lookup.kkSequenceZipName
        {
            // The KIR builder's sequence HOF handler may emit kk_sequence_*
            // directly.  Track these results as sequence expressions so that
            // downstream toList/filter rewrites fire correctly.
            sequenceExprIDs.insert(result.rawValue)
        } else if callee == lookup.groupByName || callee == lookup.associateByName
            || callee == lookup.associateWithName || callee == lookup.associateName
            || callee == lookup.associateByToName || callee == lookup.associateWithToName
            || callee == lookup.groupByToName,
            listExprIDs.contains(src)
        {
            mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.mapName, mapExprIDs.contains(src) {
            listExprIDs.insert(result.rawValue)
        } else if callee == lookup.filterName, mapExprIDs.contains(src) {
            mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.mapValuesName || callee == lookup.mapKeysName
                    || callee == lookup.filterKeysName || callee == lookup.filterValuesName,
                  mapExprIDs.contains(src) {
            mapExprIDs.insert(result.rawValue)
        } else if callee == lookup.toListName, mapExprIDs.contains(src) {
            listExprIDs.insert(result.rawValue)
        } else if callee == lookup.takeName || callee == lookup.dropName
            || callee == lookup.reversedName || callee == lookup.asReversedName || callee == lookup.sortedName || callee == lookup.distinctName
            || callee == lookup.shuffledName
            || callee == lookup.kkListTakeName || callee == lookup.kkListDropName
            || callee == lookup.kkListReversedName || callee == lookup.kkListSortedName
            || callee == lookup.kkListDistinctName || callee == lookup.kkListShuffledName
            || callee == lookup.kkListShuffledRandomName,
            listExprIDs.contains(src)
        {
            listExprIDs.insert(result.rawValue)
        }
        // STDLIB-345: list plus/minus produce new lists
        if callee == lookup.kkListPlusElementName
            || callee == lookup.kkListPlusCollectionName
            || callee == lookup.kkListMinusElementName
            || callee == lookup.kkListMinusCollectionName,
            listExprIDs.contains(src)
        {
            listExprIDs.insert(result.rawValue)
        }
        // withIndex returns IndexingIterable, not List — do not add to listExprIDs
    }

    private func handleVirtualCallInstruction(
        callee: InternedString,
        receiver: KIRExprID,
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        listExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        rangeExprIDs: inout Set<Int32>,
        charRangeExprIDs: inout Set<Int32>,
        ulongRangeExprIDs: inout Set<Int32>,
        stringExprIDs: inout Set<Int32>
    ) {
        if callee == lookup.asSequenceName
            || callee == lookup.kkStringAsSequenceName
        {
            if let result { sequenceExprIDs.insert(result.rawValue) }
            return
        }
        if callee == lookup.kkStringSplitName
            || callee == lookup.kkStringChunkedName
            || callee == lookup.kkStringWindowedName
            || callee == lookup.kkStringAsIterableName
        {
            if let result { listExprIDs.insert(result.rawValue) }
            return
        }

        let receiverRaw = receiver.rawValue
        if sequenceExprIDs.contains(receiverRaw) {
            if callee == lookup.toListName {
                if let result { listExprIDs.insert(result.rawValue) }
            } else if callee == lookup.mapName || callee == lookup.filterName || callee == lookup.takeName
                || callee == lookup.flatMapName || callee == lookup.dropName
                || callee == lookup.distinctName || callee == lookup.zipName
            {
                if let result { sequenceExprIDs.insert(result.rawValue) }
            }
            return
        }

        if mapExprIDs.contains(receiverRaw) {
            if callee == lookup.mapName || callee == lookup.toListName {
                if let result { listExprIDs.insert(result.rawValue) }
            } else if callee == lookup.filterName || callee == lookup.mapValuesName || callee == lookup.mapKeysName
                        || callee == lookup.filterKeysName || callee == lookup.filterValuesName {
                if let result { mapExprIDs.insert(result.rawValue) }
            }
            return
        }

        if listExprIDs.contains(receiverRaw) {
            if callee == lookup.groupByName || callee == lookup.associateByName
                || callee == lookup.associateWithName || callee == lookup.associateName
                || callee == lookup.associateByToName || callee == lookup.associateWithToName
                || callee == lookup.groupByToName
            {
                if let result { mapExprIDs.insert(result.rawValue) }
            } else if callee == lookup.takeName || callee == lookup.dropName
                || callee == lookup.reversedName || callee == lookup.asReversedName || callee == lookup.sortedName || callee == lookup.distinctName
                || callee == lookup.shuffledName
                || callee == lookup.kkListTakeName || callee == lookup.kkListDropName
                || callee == lookup.kkListReversedName || callee == lookup.kkListSortedName
                || callee == lookup.kkListDistinctName || callee == lookup.kkListShuffledName
                || callee == lookup.kkListShuffledRandomName
            {
                if let result { listExprIDs.insert(result.rawValue) }
            }
            // withIndex returns IndexingIterable, not List — do not add to listExprIDs
        }

        // Track range member calls that return ranges
        if rangeExprIDs.contains(receiverRaw) {
            if callee == lookup.reversedName {
                if let result {
                    rangeExprIDs.insert(result.rawValue)
                    // Propagate char range through reversed() (STDLIB-290)
                    if charRangeExprIDs.contains(receiverRaw) {
                        charRangeExprIDs.insert(result.rawValue)
                    }
                    // Propagate ULong range through reversed() (STDLIB-524)
                    if ulongRangeExprIDs.contains(receiverRaw) {
                        ulongRangeExprIDs.insert(result.rawValue)
                    }
                }
            } else if callee == lookup.toListName || callee == lookup.mapName {
                if let result { listExprIDs.insert(result.rawValue) }
            }
        }

        // STDLIB-189: Track string HOF results
        if stringExprIDs.contains(receiverRaw) {
            if callee == lookup.mapName || callee == lookup.filterName, let result {
                stringExprIDs.insert(result.rawValue)
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
        sequenceExprIDs: inout Set<Int32>,
        rangeExprIDs: inout Set<Int32>,
        charRangeExprIDs: inout Set<Int32>,
        ulongRangeExprIDs: inout Set<Int32>,
        stringExprIDs: inout Set<Int32>,
        fileExprIDs: inout Set<Int32>
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
        if rangeExprIDs.contains(from.rawValue) {
            rangeExprIDs.insert(to.rawValue)
        }
        if charRangeExprIDs.contains(from.rawValue) {
            charRangeExprIDs.insert(to.rawValue)
        }
        if ulongRangeExprIDs.contains(from.rawValue) {
            ulongRangeExprIDs.insert(to.rawValue)
        }
        if stringExprIDs.contains(from.rawValue) {
            stringExprIDs.insert(to.rawValue)
        }
        if fileExprIDs.contains(from.rawValue) {
            fileExprIDs.insert(to.rawValue)
        }
    }

    // MARK: - Static type based collection classification (LOWERING-001)

    /// Seed the collection tracking sets using the static type information
    /// stored in the KIR arena's `exprTypes` map.  This handles expressions
    /// whose concrete collection kind cannot be determined from factory/call
    /// patterns alone, such as function parameters typed as `List<T>` or
    /// return values from user-defined functions returning `Set<T>`.
    private func seedCollectionExprIDsFromStaticTypes(
        function: KIRFunction,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        stringExprIDs: inout Set<Int32>
    ) {
        guard let sema else { return }
        let types = sema.types
        let symbols = sema.symbols

        // For each expression referenced in this function's body that has
        // a TypeID in the arena, resolve the TypeKind.  If it is a classType,
        // check the classSymbol's simple name against known collection names.

        // Collect expression IDs relevant to call/virtual-call rewriting
        // from this function's body so we only classify relevant expressions.
        // NOTE: This intentionally covers a subset of instruction kinds
        // (call, virtualCall, copy, constValue, returnValue) that participate
        // in collection-type propagation.  Other instruction kinds do not
        // produce or consume collection-typed operands today.
        var referencedExprIDs: Set<Int32> = []
        for instruction in function.body {
            switch instruction {
            case let .call(_, _, arguments, result, _, _, _, _):
                for arg in arguments { referencedExprIDs.insert(arg.rawValue) }
                if let result { referencedExprIDs.insert(result.rawValue) }
            case let .virtualCall(_, _, receiver, arguments, result, _, _, _):
                referencedExprIDs.insert(receiver.rawValue)
                for arg in arguments { referencedExprIDs.insert(arg.rawValue) }
                if let result { referencedExprIDs.insert(result.rawValue) }
            case let .copy(from, to):
                referencedExprIDs.insert(from.rawValue)
                referencedExprIDs.insert(to.rawValue)
            case let .constValue(result, _):
                referencedExprIDs.insert(result.rawValue)
            case let .returnValue(expr):
                referencedExprIDs.insert(expr.rawValue)
            default:
                break
            }
        }

        for rawID in referencedExprIDs {
            let exprID = KIRExprID(rawValue: rawID)
            guard let typeID = arena.exprType(exprID) else { continue }
            // Already classified by factory-call scan — skip.
            if listExprIDs.contains(rawID) || setExprIDs.contains(rawID)
                || mapExprIDs.contains(rawID) || arrayExprIDs.contains(rawID)
                || sequenceExprIDs.contains(rawID) || stringExprIDs.contains(rawID)
            {
                continue
            }
            classifyExprByTypeID(
                rawID: rawID, typeID: typeID,
                types: types, symbols: symbols, interner: interner,
                listExprIDs: &listExprIDs, setExprIDs: &setExprIDs,
                mapExprIDs: &mapExprIDs, arrayExprIDs: &arrayExprIDs,
                sequenceExprIDs: &sequenceExprIDs,
                stringExprIDs: &stringExprIDs
            )
        }
    }

    private func seedULongValuedExprIDsFromStaticTypes(
        function: KIRFunction,
        arena: KIRArena,
        sema: SemaModule,
        ulongValuedExprIDs: inout Set<Int32>
    ) {
        var referencedExprIDs: Set<Int32> = []
        for instruction in function.body {
            switch instruction {
            case let .call(_, _, arguments, result, _, _, _, _):
                for arg in arguments { referencedExprIDs.insert(arg.rawValue) }
                if let result { referencedExprIDs.insert(result.rawValue) }
            case let .virtualCall(_, _, receiver, arguments, result, _, _, _):
                referencedExprIDs.insert(receiver.rawValue)
                for arg in arguments { referencedExprIDs.insert(arg.rawValue) }
                if let result { referencedExprIDs.insert(result.rawValue) }
            case let .copy(from, to):
                referencedExprIDs.insert(from.rawValue)
                referencedExprIDs.insert(to.rawValue)
            case let .constValue(result, _):
                referencedExprIDs.insert(result.rawValue)
            case let .returnValue(expr):
                referencedExprIDs.insert(expr.rawValue)
            default:
                break
            }
        }

        for rawID in referencedExprIDs {
            let exprID = KIRExprID(rawValue: rawID)
            guard let typeID = arena.exprType(exprID),
                  sema.types.makeNonNullable(typeID) == sema.types.ulongType
            else {
                continue
            }
            ulongValuedExprIDs.insert(rawID)
        }
    }

    private func classifyExprByTypeID(
        rawID: Int32,
        typeID: TypeID,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner,
        listExprIDs: inout Set<Int32>,
        setExprIDs: inout Set<Int32>,
        mapExprIDs: inout Set<Int32>,
        arrayExprIDs: inout Set<Int32>,
        sequenceExprIDs: inout Set<Int32>,
        stringExprIDs: inout Set<Int32>
    ) {
        let kind = types.kind(of: typeID)
        guard case let .classType(classType) = kind else { return }

        let classSymbol = classType.classSymbol
        guard let symInfo = symbols.symbol(classSymbol) else { return }
        guard let simpleName = symInfo.fqName.last else { return }

        let resolved = interner.resolve(simpleName)

        // TODO(LOWERING-001): This matches on simple name only.  A user-defined
        // type named e.g. `foo.bar.List` would be misclassified as a stdlib
        // collection.  Ideally we should validate the FQN prefix against
        // `kotlin.collections.*` / `kotlin.*` before seeding the tracking sets.
        // For now this is acceptable because the sema phase resolves stdlib
        // symbols with canonical FQNs and user types rarely shadow them.
        switch resolved {
        // NOTE: We intentionally do NOT include "Collection" / "MutableCollection"
        // here.  In Kotlin, Collection<T> is the common supertype of both
        // List<T> and Set<T>.  Mapping it to listExprIDs would cause incorrect
        // kk_list_* rewrites when the actual runtime value is a Set.
        case "List", "MutableList", "ArrayList",
             "AbstractList", "AbstractMutableList":
            listExprIDs.insert(rawID)
        case "Set", "MutableSet", "HashSet", "LinkedHashSet",
             "AbstractSet", "AbstractMutableSet":
            setExprIDs.insert(rawID)
        case "Map", "MutableMap", "HashMap", "LinkedHashMap",
             "AbstractMap", "AbstractMutableMap":
            mapExprIDs.insert(rawID)
        case "Array", "IntArray", "LongArray", "DoubleArray",
             "FloatArray", "BooleanArray", "CharArray",
             "ByteArray", "ShortArray", "UByteArray", "UShortArray", "UIntArray", "ULongArray":
            arrayExprIDs.insert(rawID)
        case "Sequence":
            sequenceExprIDs.insert(rawID)
        case "String":
            stringExprIDs.insert(rawID)
        default:
            break
        }
    }
}
