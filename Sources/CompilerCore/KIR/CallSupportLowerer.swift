import Foundation

struct NormalizedCallResult {
    let arguments: [KIRExprID]
    let defaultMask: Int64
}

final class CallSupportLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func collectFunctionDefaultArgumentExpressions(
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID: [ExprID?]] {
        var mapping: [SymbolID: [ExprID?]] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                collectFunctionDefaults(declID, ast: ast, sema: sema, mapping: &mapping)
            }
        }
        return mapping
    }

    func collectFunctionDefaults(
        _ declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        mapping: inout [SymbolID: [ExprID?]]
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case let .funDecl(function):
            guard let symbol = sema.bindings.declSymbols[declID] else { return }
            let defaults = function.valueParams.map(\.defaultValue)
            if defaults.contains(where: { $0 != nil }) {
                mapping[symbol] = defaults
            }
        case let .classDecl(classDecl):
            // Collect default arguments for primary constructor parameters.
            collectConstructorDefaults(classDecl, ast: ast, sema: sema, mapping: &mapping)
            for item in classDecl.memberFunctions + classDecl.nestedClasses + classDecl.nestedObjects {
                collectFunctionDefaults(item, ast: ast, sema: sema, mapping: &mapping)
            }
        case let .objectDecl(objectDecl):
            for item in objectDecl.memberFunctions + objectDecl.nestedClasses + objectDecl.nestedObjects {
                collectFunctionDefaults(item, ast: ast, sema: sema, mapping: &mapping)
            }
        default:
            break
        }
    }

    func collectConstructorDefaults(
        _ classDecl: ClassDecl,
        ast _: ASTModule,
        sema: SemaModule,
        mapping: inout [SymbolID: [ExprID?]]
    ) {
        // Primary constructor default arguments.
        let primaryDefaults = classDecl.primaryConstructorParams.map(\.defaultValue)
        if primaryDefaults.contains(where: { $0 != nil }) {
            let ctorSymbols = sema.symbols.symbols(atDeclSite: classDecl.range).compactMap { sema.symbols.symbol($0) }.filter {
                $0.kind == .constructor
            }
            if let primaryCtorSymbol = ctorSymbols.first {
                mapping[primaryCtorSymbol.id] = primaryDefaults
            }
        }
        // Secondary constructor default arguments.
        for secondaryCtor in classDecl.secondaryConstructors {
            let secDefaults = secondaryCtor.valueParams.map(\.defaultValue)
            if secDefaults.contains(where: { $0 != nil }) {
                let secCtorSymbols = sema.symbols.symbols(atDeclSite: secondaryCtor.range).compactMap { sema.symbols.symbol($0) }.filter {
                    $0.kind == .constructor
                }
                if let secCtorSymbol = secCtorSymbols.first {
                    mapping[secCtorSymbol.id] = secDefaults
                }
            }
        }
    }

    func defaultStubSymbol(for originalSymbol: SymbolID) -> SymbolID {
        SyntheticSymbolScheme.defaultStubSymbol(for: originalSymbol)
    }

    func defaultStubMaskSymbol(for originalSymbol: SymbolID) -> SymbolID {
        SyntheticSymbolScheme.defaultMaskSymbol(for: originalSymbol)
    }

    func generateDefaultStubFunction(
        originalSymbol: SymbolID,
        originalName: InternedString,
        signature: FunctionSignature,
        defaultExpressions: [ExprID?],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) -> KIRDeclID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let paramCount = signature.parameterTypes.count

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.setCurrentFunctionSymbol(originalSymbol)

        var params: [KIRParameter] = []
        if let receiverType = signature.receiverType {
            let receiverSym = syntheticReceiverParameterSymbol(functionSymbol: originalSymbol)
            params.append(KIRParameter(symbol: receiverSym, type: receiverType))
            let receiverExpr = arena.appendExpr(.symbolRef(receiverSym), type: receiverType)
            driver.ctx.setImplicitReceiver(symbol: receiverSym, exprID: receiverExpr)
        }
        for (paramSymbol, paramType) in zip(signature.valueParameterSymbols, signature.parameterTypes) {
            params.append(KIRParameter(symbol: paramSymbol, type: paramType))
        }
        var reifiedTokenSymbols: [SymbolID] = []
        if !signature.reifiedTypeParameterIndices.isEmpty {
            for index in signature.reifiedTypeParameterIndices.sorted() {
                guard index < signature.typeParameterSymbols.count else { continue }
                let typeParamSymbol = signature.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                params.append(KIRParameter(symbol: tokenSymbol, type: intType))
                reifiedTokenSymbols.append(tokenSymbol)
            }
        }
        let maskSymbol = defaultStubMaskSymbol(for: originalSymbol)
        params.append(KIRParameter(symbol: maskSymbol, type: intType))

        var body: [KIRInstruction] = [.beginBlock]

        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }

        let maskExpr = arena.appendExpr(.symbolRef(maskSymbol), type: intType)
        body.append(.constValue(result: maskExpr, value: .symbolRef(maskSymbol)))

        var resolvedParamExprs: [KIRExprID] = []
        for i in 0 ..< paramCount {
            let paramSymbol = signature.valueParameterSymbols[i]
            let paramType = signature.parameterTypes[i]
            let paramExpr = arena.appendExpr(.symbolRef(paramSymbol), type: paramType)
            body.append(.constValue(result: paramExpr, value: .symbolRef(paramSymbol)))

            if i < defaultExpressions.count, let defaultExprID = defaultExpressions[i] {
                let bitValue = Int64(1) << i
                let divisorExpr = arena.appendExpr(.intLiteral(bitValue), type: intType)
                body.append(.constValue(result: divisorExpr, value: .intLiteral(bitValue)))
                let dividedExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                body.append(.binary(op: .divide, lhs: maskExpr, rhs: divisorExpr, result: dividedExpr))
                let twoExpr = arena.appendExpr(.intLiteral(2), type: intType)
                body.append(.constValue(result: twoExpr, value: .intLiteral(2)))
                let bitExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                body.append(.binary(op: .modulo, lhs: dividedExpr, rhs: twoExpr, result: bitExpr))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))

                let skipLabel = driver.ctx.makeLoopLabel()
                let afterLabel = driver.ctx.makeLoopLabel()
                body.append(.jumpIfEqual(lhs: bitExpr, rhs: zeroExpr, target: skipLabel))

                driver.ctx.setLocalValue(paramExpr, for: paramSymbol)
                let defaultVal = driver.lowerExpr(
                    defaultExprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &body
                )
                let resolvedExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: paramType)
                body.append(.copy(from: defaultVal, to: resolvedExpr))
                body.append(.jump(afterLabel))

                body.append(.label(skipLabel))
                body.append(.copy(from: paramExpr, to: resolvedExpr))

                body.append(.label(afterLabel))
                driver.ctx.setLocalValue(resolvedExpr, for: paramSymbol)
                resolvedParamExprs.append(resolvedExpr)
            } else {
                driver.ctx.setLocalValue(paramExpr, for: paramSymbol)
                resolvedParamExprs.append(paramExpr)
            }
        }

        var callArgs: [KIRExprID] = []
        if let receiverExpr = driver.ctx.activeImplicitReceiverExprID() {
            callArgs.append(receiverExpr)
        }
        callArgs.append(contentsOf: resolvedParamExprs)
        for tokenSym in reifiedTokenSymbols {
            let tokenExpr = arena.appendExpr(.symbolRef(tokenSym), type: intType)
            body.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSym)))
            callArgs.append(tokenExpr)
        }

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: signature.returnType)
        body.append(.call(
            symbol: originalSymbol,
            callee: originalName,
            arguments: callArgs,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(result))
        body.append(.endBlock)

        let stubSym = defaultStubSymbol(for: originalSymbol)
        let stubName = interner.intern(interner.resolve(originalName) + "$default")

        let declID = arena.appendDecl(.function(KIRFunction(
            symbol: stubSym,
            name: stubName,
            params: params,
            returnType: signature.returnType,
            body: body,
            isSuspend: signature.isSuspend,
            isInline: false
        )))

        driver.ctx.restoreScope(scopeSnapshot)

        return declID
    }

    func normalizedCallArguments(
        providedArguments: [KIRExprID],
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        spreadFlags: [Bool],
        ast _: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers _: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> NormalizedCallResult {
        guard let callBinding,
              let chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosenCallee)
        else {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }

        let parameterCount = signature.parameterTypes.count
        guard parameterCount > 0 else {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }
        let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee)
        let isVararg = normalizeBoolFlags(signature.valueParameterIsVararg, count: parameterCount)
        let hasDefaultValues = normalizeBoolFlags(signature.valueParameterHasDefaultValues, count: parameterCount)
        let preserveArrayVarargs = externalLinkName == "kk_array_of" || externalLinkName == "kk_sequence_of"

        var argIndicesByParameter: [Int: [Int]] = [:]
        for (argIndex, paramIndex) in callBinding.parameterMapping {
            guard argIndex >= 0, argIndex < providedArguments.count else {
                continue
            }
            argIndicesByParameter[paramIndex, default: []].append(argIndex)
        }
        for key in Array(argIndicesByParameter.keys) {
            argIndicesByParameter[key]?.sort()
        }

        let hasOutOfRangeMapping = argIndicesByParameter.keys.contains(where: { $0 < 0 || $0 >= parameterCount })
        let hasMergedParameterMapping = argIndicesByParameter.values.contains(where: { $0.count > 1 })
        if hasOutOfRangeMapping {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }
        if hasMergedParameterMapping {
            let allMergedAreVararg = argIndicesByParameter.allSatisfy { paramIndex, argIndices in
                argIndices.count <= 1 || isVararg[paramIndex]
            }
            if !allMergedAreVararg {
                return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
            }
        }

        if externalLinkName == "kk_array_of",
           parameterCount == 1,
           isVararg.first == true
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let argIndices = argIndicesByParameter[0] ?? []
            let packedArray: KIRExprID
            if argIndices.isEmpty {
                packedArray = emitArrayNew(
                    count: 0,
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.anyType,
                    instructions: &instructions
                )
            } else {
                packedArray = packVarargArguments(
                    argIndices: argIndices,
                    providedArguments: providedArguments,
                    spreadFlags: spreadFlags,
                    listifyResult: false,
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.anyType,
                    instructions: &instructions
                )
            }

            let hasAnySpread = argIndices.contains { idx in
                idx < spreadFlags.count && spreadFlags[idx]
            }
            let countExpr: KIRExprID
            if hasAnySpread {
                countExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_size"),
                    arguments: [packedArray],
                    result: countExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                countExpr = arena.appendExpr(.intLiteral(Int64(argIndices.count)), type: intType)
                instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(argIndices.count))))
            }
            return NormalizedCallResult(arguments: [packedArray, countExpr], defaultMask: 0)
        }

        if externalLinkName == "kk_compareValuesBy_vararg",
           parameterCount == 3,
           isVararg.count >= 3,
           isVararg[2]
        {
            guard let aArgIndex = argIndicesByParameter[0]?.first,
                  let bArgIndex = argIndicesByParameter[1]?.first
            else {
                return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
            }
            let selectorArgIndices = argIndicesByParameter[2] ?? []
            let packedSelectors = packCompareValuesBySelectorPairs(
                selectorArgIndices: selectorArgIndices,
                providedArguments: providedArguments,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return NormalizedCallResult(arguments: [providedArguments[aArgIndex], providedArguments[bArgIndex], packedSelectors], defaultMask: 0)
        }

        var normalized: [KIRExprID] = []
        normalized.reserveCapacity(parameterCount)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        var mask: Int64 = 0

        for paramIndex in 0 ..< parameterCount {
            if let argIndices = argIndicesByParameter[paramIndex] {
                if isVararg[paramIndex] {
                    let packed = packVarargArguments(
                        argIndices: argIndices,
                        providedArguments: providedArguments,
                        spreadFlags: spreadFlags,
                        listifyResult: !preserveArrayVarargs,
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.anyType,
                        instructions: &instructions
                    )
                    normalized.append(packed)
                } else if let argIndex = argIndices.first {
                    normalized.append(providedArguments[argIndex])
                }
                continue
            }
            if isVararg[paramIndex] {
                let emptyArray = emitArrayNew(
                    count: 0,
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.anyType,
                    instructions: &instructions
                )
                normalized.append(emptyArray)
                continue
            }
            // Use semantic hasDefaultValues flag (callee context) instead of
            // looking up AST default expressions at the caller site.
            guard hasDefaultValues[paramIndex] else {
                return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
            }
            mask |= Int64(1) << paramIndex
            let sentinel = arena.appendExpr(.intLiteral(0), type: signature.parameterTypes[paramIndex])
            instructions.append(.constValue(result: sentinel, value: .intLiteral(0)))
            normalized.append(sentinel)
        }
        return NormalizedCallResult(arguments: normalized, defaultMask: mask)
    }

    func packVarargArguments(
        argIndices: [Int],
        providedArguments: [KIRExprID],
        spreadFlags: [Bool],
        listifyResult: Bool = true,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let hasAnySpread = argIndices.contains { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }
        let allSpread = !argIndices.isEmpty && argIndices.allSatisfy { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }

        if argIndices.count == 1, allSpread {
            let spreadValue = providedArguments[argIndices[0]]
            if listifyResult {
                return emitArrayToList(
                    spreadValue,
                    arena: arena,
                    interner: interner,
                    anyType: anyType,
                    instructions: &instructions
                )
            }
            return spreadValue
        }

        if hasAnySpread {
            let pairsCount = argIndices.count
            let pairsArraySize = pairsCount * 2
            let pairsArray = emitArrayNew(
                count: pairsArraySize,
                arena: arena,
                interner: interner,
                intType: intType,
                anyType: anyType,
                instructions: &instructions
            )
            for (pairIdx, idx) in argIndices.enumerated() {
                let isSpread = idx < spreadFlags.count && spreadFlags[idx]
                let markerValue: Int64 = isSpread ? -1 : 1
                let markerExpr = arena.appendExpr(.intLiteral(markerValue), type: intType)
                instructions.append(.constValue(result: markerExpr, value: .intLiteral(markerValue)))
                let markerIdxExpr = arena.appendExpr(.intLiteral(Int64(pairIdx * 2)), type: intType)
                instructions.append(.constValue(result: markerIdxExpr, value: .intLiteral(Int64(pairIdx * 2))))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, markerIdxExpr, markerExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
                let valueIdxExpr = arena.appendExpr(.intLiteral(Int64(pairIdx * 2 + 1)), type: intType)
                instructions.append(.constValue(result: valueIdxExpr, value: .intLiteral(Int64(pairIdx * 2 + 1))))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, valueIdxExpr, providedArguments[idx]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            let pairCountExpr = arena.appendExpr(.intLiteral(Int64(pairsCount)), type: intType)
            instructions.append(.constValue(result: pairCountExpr, value: .intLiteral(Int64(pairsCount))))
            let concatResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_vararg_spread_concat"),
                arguments: [pairsArray, pairCountExpr],
                result: concatResult,
                canThrow: false,
                thrownResult: nil
            ))
            // Convert the concatenated array to a list since vararg parameters
            // are typed as List<T>.
            if listifyResult {
                return emitArrayToList(
                    concatResult,
                    arena: arena,
                    interner: interner,
                    anyType: anyType,
                    instructions: &instructions
                )
            }
            return concatResult
        }

        let count = argIndices.count
        let arrayID = emitArrayNew(
            count: count,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: anyType,
            instructions: &instructions
        )
        for (slotIndex, argIndex) in argIndices.enumerated() {
            let indexExpr = arena.appendExpr(.intLiteral(Int64(slotIndex)), type: intType)
            instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(slotIndex))))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayID, indexExpr, providedArguments[argIndex]],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }
        // Convert the packed array to a list since vararg parameters are typed
        // as List<T> and the callee uses kk_list_* operations.
        if listifyResult {
            return emitArrayToList(
                arrayID,
                arena: arena,
                interner: interner,
                anyType: anyType,
                instructions: &instructions
            )
        }
        return arrayID
    }

    private func packCompareValuesBySelectorPairs(
        selectorArgIndices: [Int],
        providedArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let packedArray = emitArrayNew(
            count: selectorArgIndices.count * 2,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: sema.types.anyType,
            instructions: &instructions
        )

        for (pairIndex, argIndex) in selectorArgIndices.enumerated() {
            var loweredSelectorID = providedArguments[argIndex]
            var selectorCallableInfo = driver.ctx.callableValueInfo(for: loweredSelectorID)
            if selectorCallableInfo == nil,
               case let .symbolRef(symbol)? = arena.expr(loweredSelectorID),
               let function = arena.function(for: symbol)
            {
                selectorCallableInfo = KIRCallableValueInfo(
                    symbol: function.symbol,
                    callee: function.name,
                    captureArguments: arena.lambdaCaptureArgsBySymbol[function.symbol] ?? [],
                    hasClosureParam: function.params.count >= 2
                )
            }
            if let callableInfo = selectorCallableInfo,
               !callableInfo.hasClosureParam,
               let adaptedInfo = makeCollectionHOFCallableAdapter(
                    callableInfo: callableInfo,
                    loweredArgID: loweredSelectorID,
                    adapterTag: "compareValuesBy_vararg_\(argIndex)",
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            {
                let adaptedExpr = arena.appendExpr(
                    .symbolRef(adaptedInfo.symbol),
                    type: arena.exprType(loweredSelectorID) ?? sema.types.anyType
                )
                instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adaptedInfo.symbol)))
                loweredSelectorID = adaptedExpr
                selectorCallableInfo = adaptedInfo
            }

            let fnSlotExpr = arena.appendExpr(.intLiteral(Int64(pairIndex * 2)), type: intType)
            instructions.append(.constValue(result: fnSlotExpr, value: .intLiteral(Int64(pairIndex * 2))))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [packedArray, fnSlotExpr, loweredSelectorID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))

            let closureRawExpr: KIRExprID
            if let callableInfo = selectorCallableInfo,
               let closureRaw = callableInfo.captureArguments.first
            {
                closureRawExpr = closureRaw
            } else {
                closureRawExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: closureRawExpr, value: .intLiteral(0)))
            }

            let closureSlotExpr = arena.appendExpr(.intLiteral(Int64(pairIndex * 2 + 1)), type: intType)
            instructions.append(.constValue(result: closureSlotExpr, value: .intLiteral(Int64(pairIndex * 2 + 1))))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [packedArray, closureSlotExpr, closureRawExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        return packedArray
    }

    private func emitArrayToList(
        _ arrayID: KIRExprID,
        arena: KIRArena,
        interner: StringInterner,
        anyType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let listID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_toList"),
            arguments: [arrayID],
            result: listID,
            canThrow: false,
            thrownResult: nil
        ))
        return listID
    }

    func emitArrayNew(
        count: Int,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let countExpr = arena.appendExpr(.intLiteral(Int64(count)), type: intType)
        instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
        let arrayID = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [countExpr],
            result: arrayID,
            canThrow: false,
            thrownResult: nil
        ))
        return arrayID
    }

    private func makeCollectionHOFCallableAdapter(
        callableInfo: KIRCallableValueInfo,
        loweredArgID: KIRExprID,
        adapterTag: String,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRCallableValueInfo? {
        let callableType = arena.exprType(loweredArgID) ?? sema.types.anyType
        let nonNullCallableType = sema.types.makeNonNullable(callableType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCallableType) else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_compare_values_hof_adapter_\(adapterTag)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        let valueParams: [KIRParameter] = functionType.params.enumerated().map { _, type in
            KIRParameter(
                symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        var callArguments: [KIRExprID] = []
        if callableInfo.captureArguments.count >= 2 {
            let kkArrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, captureExpr) in callableInfo.captureArguments.enumerated() {
                let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
                let loadedExpr = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: captureType)
                body.append(.call(
                    symbol: nil,
                    callee: kkArrayGet,
                    arguments: [closureExpr, offsetExpr],
                    result: loadedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                callArguments.append(loadedExpr)
            }
        } else if !callableInfo.captureArguments.isEmpty {
            callArguments.append(closureExpr)
        }

        for valueParam in valueParams {
            let valueExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
            body.append(.constValue(result: valueExpr, value: .symbolRef(valueParam.symbol)))
            callArguments.append(valueExpr)
        }

        let callResultType = functionType.returnType
        let callResult = arena.appendExpr(.temporary(Int32(clamping: arena.expressions.count)), type: callResultType)
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        switch sema.types.kind(of: functionType.returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        let generatedFunction = KIRFunction(
            symbol: adapterSymbol,
            name: adapterName,
            params: [closureParam] + valueParams,
            returnType: callResultType,
            body: body,
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(generatedFunction))
        driver.ctx.appendGeneratedCallableDecl(functionID)

        return KIRCallableValueInfo(
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: callableInfo.captureArguments,
            hasClosureParam: true
        )
    }
}
