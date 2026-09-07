
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
                let dividedExpr = arena.appendTemporary(type: intType)
                body.append(.binary(op: .divide, lhs: maskExpr, rhs: divisorExpr, result: dividedExpr))
                let twoExpr = arena.appendExpr(.intLiteral(2), type: intType)
                body.append(.constValue(result: twoExpr, value: .intLiteral(2)))
                let bitExpr = arena.appendTemporary(type: intType)
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
                let resolvedExpr = arena.appendTemporary(type: paramType)
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

        let result = arena.appendTemporary(type: signature.returnType)
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
        let isSourceBackedPrimitiveArrayFactory = isSourceBackedPrimitiveArrayFactory(
            chosenCallee,
            sema: sema,
            interner: interner
        )
        let preserveArrayVarargs = externalLinkName == "kk_array_of"
            || externalLinkName == "__kk_sequence_of"
            || externalLinkName == "kk_atomic_ref_array_of"
        if isStdlibCollectionFactory(chosenCallee, sema: sema, interner: interner) {
            return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
        }
        var boxedArguments = providedArguments

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
        if isSourceBackedPrimitiveArrayFactory {
            let argIndices = argIndicesByParameter[0] ?? []
            let hasAnySpread = argIndices.contains { idx in
                idx < spreadFlags.count && spreadFlags[idx]
            }
            guard hasAnySpread else {
                return NormalizedCallResult(arguments: providedArguments, defaultMask: 0)
            }

            let intType = sema.types.make(.primitive(.int, .nonNull))
            let packed = packVarargArguments(
                argIndices: argIndices,
                providedArguments: providedArguments,
                spreadFlags: spreadFlags,
                listifyResult: false,
                boxPrimitiveElements: false,
                resultType: signature.returnType,
                arena: arena,
                interner: interner,
                intType: intType,
                anyType: sema.types.anyType,
                types: sema.types,
                symbols: sema.symbols,
                instructions: &instructions
            )
            return NormalizedCallResult(arguments: [packed], defaultMask: 0)
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
                // `kk_array_of` backs both generic arrayOf<T> and primitive array
                // factories. Preserve erased-type boxing and skip boxing for concrete
                // primitive storage.
                boxNonSpreadVarargArguments(
                    argIndices,
                    in: &boxedArguments,
                    elementType: signature.parameterTypes[0],
                    spreadFlags: spreadFlags,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                packedArray = packVarargArguments(
                    argIndices: argIndices,
                    providedArguments: boxedArguments,
                    spreadFlags: spreadFlags,
                    listifyResult: false,
                    boxPrimitiveElements: false,
                    arena: arena,
                    interner: interner,
                    intType: intType,
                    anyType: sema.types.anyType,
                    types: sema.types,
                    symbols: sema.symbols,
                    instructions: &instructions
                )
            }

            let hasAnySpread = argIndices.contains { idx in
                idx < spreadFlags.count && spreadFlags[idx]
            }
            let countExpr: KIRExprID
            if hasAnySpread {
                countExpr = arena.appendTemporary(type: intType)
                emitNonThrowingCall(
                    callee: interner.intern("__kk_array_size"),
                    arg: packedArray,
                    result: countExpr,
                    into: &instructions
                )
            } else {
                countExpr = arena.appendExpr(.intLiteral(Int64(argIndices.count)), type: intType)
                instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(argIndices.count))))
            }
            return NormalizedCallResult(arguments: [packedArray, countExpr], defaultMask: 0)
        }

        var normalized: [KIRExprID] = []
        normalized.reserveCapacity(parameterCount)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        var mask: Int64 = 0

        for paramIndex in 0 ..< parameterCount {
            if let argIndices = argIndicesByParameter[paramIndex] {
                if isVararg[paramIndex] {
                    boxNonSpreadVarargArguments(
                        argIndices,
                        in: &boxedArguments,
                        elementType: signature.parameterTypes[paramIndex],
                        spreadFlags: spreadFlags,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    let packed = packVarargArguments(
                        argIndices: argIndices,
                        providedArguments: boxedArguments,
                        spreadFlags: spreadFlags,
                        listifyResult: !preserveArrayVarargs,
                        boxPrimitiveElements: !preserveArrayVarargs,
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.anyType,
                        types: sema.types,
                        symbols: sema.symbols,
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

        // `$default` stubs are synthetic calls and therefore do not carry the
        // original function signature into ABILoweringPass. Preserve the erased
        // representation for explicitly supplied primitive arguments here when
        // a generic or Any-typed parameter is forwarded through such a stub.
        // Defaulted parameters remain sentinels and are materialized inside the
        // stub before the ordinary call boundary applies its own boxing rules.
        if mask != 0 {
            for paramIndex in 0 ..< parameterCount {
                let parameterKind = sema.types.kind(of: signature.parameterTypes[paramIndex])
                guard mask & (Int64(1) << paramIndex) == 0,
                      paramIndex < normalized.count,
                      let sourceType = arena.exprType(normalized[paramIndex])
                else {
                    continue
                }
                let isErasedParameter: Bool
                switch parameterKind {
                case .any, .typeParam:
                    isErasedParameter = true
                default:
                    isErasedParameter = false
                }
                guard isErasedParameter else {
                    continue
                }
                normalized[paramIndex] = boxValueForAnySlot(
                    normalized[paramIndex],
                    sourceType: sourceType,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: interner,
                    arena: arena,
                    resultType: signature.parameterTypes[paramIndex],
                    into: &instructions
                )
            }
        }
        return NormalizedCallResult(arguments: normalized, defaultMask: mask)
    }

    /// Boxes non-spread primitive arguments when the vararg's declared element type is Any/reference/type-param — e.g. `printAll(vararg items: Any)` — but not for a concrete-primitive element type like `IntArray`'s `intArrayOf(vararg elements: Int)`, which needs raw storage.
    func boxNonSpreadVarargArguments(
        _ argIndices: [Int],
        in arguments: inout [KIRExprID],
        elementType: TypeID,
        spreadFlags: [Bool],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard varargElementTypeIsBoxingBoundary(sema.types.kind(of: elementType)) else {
            return
        }
        for argIndex in argIndices {
            guard argIndex < arguments.count else { continue }
            let isSpread = argIndex < spreadFlags.count && spreadFlags[argIndex]
            guard !isSpread else { continue }
            arguments[argIndex] = boxVarargElementIfNeeded(
                arguments[argIndex],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
    }

    private func varargElementTypeIsBoxingBoundary(_ elementKind: TypeKind) -> Bool {
        if case .any = elementKind { return true }
        if case .classType = elementKind { return true }
        if case .typeParam = elementKind { return true }
        return false
    }

    private func boxVarargElementIfNeeded(
        _ argID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let argType = arena.exprType(argID) else {
            return argID
        }
        return boxValueForAnySlot(
            argID,
            sourceType: argType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner,
            arena: arena,
            into: &instructions
        )
    }

    private func isStdlibCollectionFactory(
        _ symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        guard symbol.fqName.count == 3,
              interner.resolve(symbol.fqName[0]) == "kotlin",
              interner.resolve(symbol.fqName[1]) == "collections"
        else {
            return false
        }
        switch interner.resolve(symbol.fqName[2]) {
        case "emptyList", "listOf", "mutableListOf", "arrayListOf",
             "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf",
             "emptyMap", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf":
            return true
        default:
            return false
        }
    }

    func packVarargArguments(
        argIndices: [Int],
        providedArguments: [KIRExprID],
        spreadFlags: [Bool],
        listifyResult: Bool = true,
        boxPrimitiveElements: Bool = true,
        resultType: TypeID? = nil,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        types: TypeSystem,
        symbols: SymbolTable? = nil,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let hasAnySpread = argIndices.contains { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }
        let allSpread = !argIndices.isEmpty && argIndices.allSatisfy { idx in
            idx < spreadFlags.count && spreadFlags[idx]
        }
        func typedResult(_ expression: KIRExprID) -> KIRExprID {
            guard !listifyResult, let resultType else {
                return expression
            }
            let typed = arena.appendTemporary(type: resultType)
            instructions.append(.copy(from: expression, to: typed))
            return typed
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
            return typedResult(spreadValue)
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
                let elementValue = (isSpread || !boxPrimitiveElements)
                    ? providedArguments[idx]
                    : boxVarargElementIfNeeded(
                        providedArguments[idx],
                        types: types,
                        symbols: symbols,
                        arena: arena,
                        interner: interner,
                        anyType: anyType,
                        instructions: &instructions
                    )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [pairsArray, valueIdxExpr, elementValue],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            let pairCountExpr = arena.appendExpr(.intLiteral(Int64(pairsCount)), type: intType)
            instructions.append(.constValue(result: pairCountExpr, value: .intLiteral(Int64(pairsCount))))
            let concatResult = arena.appendTemporary(type: anyType)
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
            return typedResult(concatResult)
        }

        let count = argIndices.count
        let arrayID = emitArrayNew(
            count: count,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: anyType,
            resultType: resultType,
            instructions: &instructions
        )
        for (slotIndex, argIndex) in argIndices.enumerated() {
            let indexExpr = arena.appendExpr(.intLiteral(Int64(slotIndex)), type: intType)
            instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(slotIndex))))
            let elementValue = boxPrimitiveElements
                ? boxVarargElementIfNeeded(
                    providedArguments[argIndex],
                    types: types,
                    symbols: symbols,
                    arena: arena,
                    interner: interner,
                    anyType: anyType,
                    instructions: &instructions
                )
                : providedArguments[argIndex]
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayID, indexExpr, elementValue],
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

    // Vararg element type parameters are erased to the array's Any-typed slots,
    // so a primitive argument must be boxed to carry its concrete type — otherwise
    // e.g. a Char is stored as a bare code point and later misread as an Int. Skips
    // spread arguments (already-boxed array/list references, not scalars) and any
    // argument whose current type isn't a known primitive, so callers that already
    // box their elements (listOf/setOf/format) are not double-boxed.
    private func boxVarargElementIfNeeded(
        _ argID: KIRExprID,
        types: TypeSystem,
        symbols: SymbolTable?,
        arena: KIRArena,
        interner: StringInterner,
        anyType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let argType = arena.exprType(argID) else {
            return argID
        }
        return boxValueForAnySlot(
            argID,
            sourceType: argType,
            types: types,
            symbols: symbols,
            interner: interner,
            arena: arena,
            resultType: anyType,
            into: &instructions
        )
    }

    private func emitArrayToList(
        _ arrayID: KIRExprID,
        arena: KIRArena,
        interner: StringInterner,
        anyType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let listID = arena.appendTemporary(type: anyType)
        emitNonThrowingCall(
            callee: interner.intern("__kk_array_toList"),
            arg: arrayID,
            result: listID,
            into: &instructions
        )
        return listID
    }

    func emitArrayNew(
        count: Int,
        arena: KIRArena,
        interner: StringInterner,
        intType: TypeID,
        anyType: TypeID,
        resultType: TypeID? = nil,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let countExpr = arena.appendExpr(.intLiteral(Int64(count)), type: intType)
        instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(count))))
        let arrayID = arena.appendTemporary(type: resultType ?? anyType)
        emitNonThrowingCall(
            callee: interner.intern("kk_array_new"),
            arg: countExpr,
            result: arrayID,
            into: &instructions
        )
        return arrayID
    }
}
