import Foundation

private protocol LoweringImpl: KIRPass {}

private final class NormalizeBlocksPass: LoweringImpl {
    static let name = "NormalizeBlocks"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.filter { instruction in
                switch instruction {
                case .beginBlock, .endBlock:
                    return false
                default:
                    return true
                }
            }
            if let last = updated.body.last {
                switch last {
                case .returnUnit, .returnValue:
                    break
                default:
                    updated.body.append(.returnUnit)
                }
            } else {
                updated.body = [.returnUnit]
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class OperatorLoweringPass: LoweringImpl {
    static let name = "OperatorLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .binary(let op, let lhs, let rhs, let result) = instruction else {
                    return instruction
                }
                let callee: InternedString
                switch op {
                case .add:
                    callee = ctx.interner.intern("kk_op_add")
                case .subtract:
                    callee = ctx.interner.intern("kk_op_sub")
                case .multiply:
                    callee = ctx.interner.intern("kk_op_mul")
                case .divide:
                    callee = ctx.interner.intern("kk_op_div")
                case .equal:
                    callee = ctx.interner.intern("kk_op_eq")
                }
                return .call(symbol: nil, callee: callee, arguments: [lhs, rhs], result: result, outThrown: false)
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class ForLoweringPass: LoweringImpl {
    static let name = "ForLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let markerCallee = ctx.interner.intern("__for_expr__")
        let iteratorCallee = ctx.interner.intern("iterator")
        let loweredCallee = ctx.interner.intern("kk_for_lowered")

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction,
                      callee == markerCallee else {
                    loweredBody.append(instruction)
                    continue
                }

                if let iterable = arguments.first {
                    let iteratorTemp = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    loweredBody.append(
                        .call(
                            symbol: nil,
                            callee: iteratorCallee,
                            arguments: [iterable],
                            result: iteratorTemp,
                            outThrown: outThrown
                        )
                    )
                    var loweredArguments: [KIRExprID] = [iteratorTemp]
                    loweredArguments.append(contentsOf: arguments.dropFirst())
                    loweredBody.append(
                        .call(
                            symbol: symbol,
                            callee: loweredCallee,
                            arguments: loweredArguments,
                            result: result,
                            outThrown: outThrown
                        )
                    )
                } else {
                    loweredBody.append(
                        .call(
                            symbol: symbol,
                            callee: loweredCallee,
                            arguments: [],
                            result: result,
                            outThrown: outThrown
                        )
                    )
                }
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class WhenLoweringPass: LoweringImpl {
    static let name = "WhenLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let markerCallee = ctx.interner.intern("__when_expr__")
        let loweredCallee = ctx.interner.intern("kk_when_select")

        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction,
                      callee == markerCallee else {
                    return instruction
                }
                if arguments.isEmpty {
                    let unitValue = module.arena.appendExpr(.unit)
                    return .call(
                        symbol: symbol,
                        callee: loweredCallee,
                        arguments: [unitValue],
                        result: result,
                        outThrown: outThrown
                    )
                }
                return .call(
                    symbol: symbol,
                    callee: loweredCallee,
                    arguments: arguments,
                    result: result,
                    outThrown: outThrown
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class PropertyLoweringPass: LoweringImpl {
    static let name = "PropertyLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let getterName = ctx.interner.intern("get")
        let setterName = ctx.interner.intern("set")
        let loweredCallee = ctx.interner.intern("kk_property_access")

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }
                guard callee == getterName || callee == setterName else {
                    loweredBody.append(instruction)
                    continue
                }

                let isSetter = callee == setterName
                let accessorKind = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                loweredBody.append(
                    .constValue(
                        result: accessorKind,
                        value: .boolLiteral(isSetter)
                    )
                )
                var loweredArguments: [KIRExprID] = [accessorKind]
                loweredArguments.append(contentsOf: arguments)
                loweredBody.append(
                    .call(
                        symbol: symbol,
                        callee: loweredCallee,
                        arguments: loweredArguments,
                        result: result,
                        outThrown: outThrown
                    )
                )
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class DataEnumSealedSynthesisPass: LoweringImpl {
    static let name = "DataEnumSealedSynthesis"

    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            if updated.body.isEmpty {
                updated.body = [.nop, .returnUnit]
            }
            return updated
        }

        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let existingFunctionSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.symbol
        })
        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case .nominalType(let nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }

        for nominalSymbolID in nominalSymbols {
            guard let nominalSymbol = sema.symbols.symbol(nominalSymbolID) else {
                continue
            }

            if nominalSymbol.kind == .enumClass {
                let entries = enumEntrySymbols(owner: nominalSymbol, symbols: sema.symbols)
                let valuesCount = Int64(entries.count)
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$enumValuesCount")
                appendSyntheticCountFunctionIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    value: valuesCount,
                    returnType: intType,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols
                )
            }

            if nominalSymbol.flags.contains(.sealedType) {
                let subtypeCount = Int64(sema.symbols.directSubtypes(of: nominalSymbol.id).count)
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$sealedSubtypeCount")
                appendSyntheticCountFunctionIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    value: subtypeCount,
                    returnType: intType,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols
                )
            }

            if nominalSymbol.flags.contains(.dataType) {
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$copy")
                appendSyntheticDataCopyIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols,
                    interner: ctx.interner
                )
            }
        }

        module.recordLowering(Self.name)
    }

    private func enumEntrySymbols(owner: SemanticSymbol, symbols: SymbolTable) -> [SemanticSymbol] {
        let prefixLength = owner.fqName.count
        return symbols
            .allSymbols()
            .filter { symbol in
                guard symbol.kind == .field, symbol.fqName.count == prefixLength + 1 else {
                    return false
                }
                return Array(symbol.fqName.prefix(prefixLength)) == owner.fqName
            }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
    }

    private func appendSyntheticCountFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: Int64,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .intLiteral(value)),
            .returnValue(resultExpr)
        ]
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func appendSyntheticDataCopyIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class || owner.kind == .enumClass || owner.kind == .object else {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)
        let resultExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .symbolRef(parameterSymbol)),
            .returnValue(resultExpr)
        ]
        let signature = FunctionSignature(
            parameterTypes: [receiverType],
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: [parameterSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func appendSyntheticFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction],
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let fqName = owner.fqName + [name]
        let nonSyntheticConflict = sema.symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            return symbol.kind == .function && !symbol.flags.contains(.synthetic)
        }
        if nonSyntheticConflict {
            return
        }

        let functionSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: fqName,
            declSite: owner.declSite,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                valueParameterSymbols: params.map(\.symbol),
                valueParameterHasDefaultValues: params.map { _ in false },
                valueParameterIsVararg: params.map { _ in false },
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }
}

private struct InlineExpansion {
    let instructions: [KIRInstruction]
    let returnedExpr: KIRExprID?
}

private final class InlineLoweringPass: LoweringImpl {
    static let name = "InlineLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let inlineFunctionsBySymbol = Dictionary(uniqueKeysWithValues: module.arena.declarations.compactMap { decl -> (SymbolID, KIRFunction)? in
            guard case .function(let function) = decl, function.isInline else {
                return nil
            }
            return (function.symbol, function)
        })
        let inlineFunctionsByName = Dictionary(grouping: inlineFunctionsBySymbol.values, by: \.name)

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)
            var aliases: [KIRExprID: KIRExprID] = [:]

            for originalInstruction in function.body {
                let instruction = rewriteInstruction(originalInstruction, aliases: aliases)
                if let defined = definedResult(in: instruction) {
                    aliases.removeValue(forKey: defined)
                }

                guard case .call(let symbol, let callee, let arguments, let result, _) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                let inlineTarget: KIRFunction?
                if let symbol, let target = inlineFunctionsBySymbol[symbol] {
                    inlineTarget = target
                } else if let byName = inlineFunctionsByName[callee], byName.count == 1 {
                    inlineTarget = byName[0]
                } else {
                    inlineTarget = nil
                }

                guard let inlineTarget, inlineTarget.symbol != function.symbol else {
                    loweredBody.append(instruction)
                    continue
                }
                let expansion = expandInlineCall(
                    inlineTarget: inlineTarget,
                    arguments: arguments,
                    module: module
                )
                guard let expansion else {
                    loweredBody.append(instruction)
                    continue
                }

                loweredBody.append(contentsOf: expansion.instructions)
                if let result {
                    if let returnedExpr = expansion.returnedExpr {
                        aliases[result] = resolveAlias(of: returnedExpr, aliases: aliases)
                    } else {
                        let unitExpr = module.arena.appendExpr(.unit)
                        aliases[result] = unitExpr
                    }
                }
            }

            updated.body = loweredBody
            if updated.body.isEmpty {
                updated.body = [.returnUnit]
            }
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func expandInlineCall(
        inlineTarget: KIRFunction,
        arguments: [KIRExprID],
        module: KIRModule
    ) -> InlineExpansion? {
        guard arguments.count == inlineTarget.params.count else {
            return nil
        }

        let parameterValues = Dictionary(uniqueKeysWithValues: zip(inlineTarget.params.map(\.symbol), arguments))
        var localExprMap: [KIRExprID: KIRExprID] = [:]
        var lowered: [KIRInstruction] = []
        lowered.reserveCapacity(inlineTarget.body.count)
        var returnedExpr: KIRExprID?

        for instruction in inlineTarget.body {
            switch instruction {
            case .beginBlock, .endBlock:
                continue

            case .nop:
                lowered.append(.nop)

            case .label(let id):
                lowered.append(.label(id))

            case .jump(let target):
                lowered.append(.jump(target))

            case .jumpIfEqual(let lhs, let rhs, let target):
                lowered.append(
                    .jumpIfEqual(
                        lhs: resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: resolveAlias(of: rhs, aliases: localExprMap),
                        target: target
                    )
                )

            case .returnUnit:
                returnedExpr = nil

            case .returnValue(let value):
                returnedExpr = resolveAlias(of: value, aliases: localExprMap)

            case .constValue(let result, let value):
                if case .symbolRef(let symbol) = value, let argument = parameterValues[symbol] {
                    localExprMap[result] = argument
                    continue
                }
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(.constValue(result: loweredResult, value: value))

            case .binary(let op, let lhs, let rhs, let result):
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(
                    .binary(
                        op: op,
                        lhs: resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: resolveAlias(of: rhs, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case .call(let symbol, let callee, let args, let result, let outThrown):
                let loweredResult = result.map { expr -> KIRExprID in
                    let cloned = cloneExpr(expr, in: module.arena)
                    localExprMap[expr] = cloned
                    return cloned
                }
                lowered.append(
                    .call(
                        symbol: symbol,
                        callee: callee,
                        arguments: args.map { resolveAlias(of: $0, aliases: localExprMap) },
                        result: loweredResult,
                        outThrown: outThrown
                    )
                )

            case .returnIfEqual(let lhs, let rhs):
                lowered.append(
                    .returnIfEqual(
                        lhs: resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: resolveAlias(of: rhs, aliases: localExprMap)
                    )
                )
            }
        }

        return InlineExpansion(instructions: lowered, returnedExpr: returnedExpr)
    }

    private func rewriteInstruction(_ instruction: KIRInstruction, aliases: [KIRExprID: KIRExprID]) -> KIRInstruction {
        switch instruction {
        case .binary(let op, let lhs, let rhs, let result):
            return .binary(
                op: op,
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases),
                result: result
            )

        case .call(let symbol, let callee, let arguments, let result, let outThrown):
            return .call(
                symbol: symbol,
                callee: callee,
                arguments: arguments.map { resolveAlias(of: $0, aliases: aliases) },
                result: result,
                outThrown: outThrown
            )

        case .returnValue(let value):
            return .returnValue(resolveAlias(of: value, aliases: aliases))

        case .returnIfEqual(let lhs, let rhs):
            return .returnIfEqual(
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases)
            )

        case .jumpIfEqual(let lhs, let rhs, let target):
            return .jumpIfEqual(
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases),
                target: target
            )

        default:
            return instruction
        }
    }

    private func definedResult(in instruction: KIRInstruction) -> KIRExprID? {
        switch instruction {
        case .constValue(let result, _):
            return result
        case .binary(_, _, _, let result):
            return result
        case .call(_, _, _, let result, _):
            return result
        default:
            return nil
        }
    }

    private func resolveAlias(of expr: KIRExprID, aliases: [KIRExprID: KIRExprID]) -> KIRExprID {
        var current = expr
        var visited: Set<KIRExprID> = []
        while let next = aliases[current], visited.insert(current).inserted {
            if next == current {
                break
            }
            current = next
        }
        return current
    }

    private func cloneExpr(_ source: KIRExprID, in arena: KIRArena) -> KIRExprID {
        let fallback = KIRExprKind.temporary(Int32(arena.expressions.count))
        return arena.appendExpr(arena.expr(source) ?? fallback)
    }
}

private final class LambdaClosureConversionPass: LoweringImpl {
    static let name = "LambdaClosureConversion"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let markerCallee = ctx.interner.intern("<lambda>")
        let loweredCallee = ctx.interner.intern("kk_lambda_invoke")

        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction,
                      callee == markerCallee else {
                    return instruction
                }
                return .call(
                    symbol: symbol,
                    callee: loweredCallee,
                    arguments: arguments,
                    result: result,
                    outThrown: outThrown
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class CoroutineLoweringPass: LoweringImpl {
    static let name = "CoroutineLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let suspendFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl, function.isSuspend else {
                return nil
            }
            return function
        }
        guard !suspendFunctions.isEmpty else {
            module.recordLowering(Self.name)
            return
        }
        let suspendFunctionSymbols = Set(suspendFunctions.map(\.symbol))
        let suspendFunctionNames = Set(suspendFunctions.map(\.name))

        var existingFunctionNames: Set<InternedString> = Set(module.arena.declarations.compactMap { decl in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.name
        })

        var nextSyntheticSymbol = nextAvailableSyntheticSymbol(module: module, sema: ctx.sema)
        var loweredBySymbol: [SymbolID: (name: InternedString, symbol: SymbolID)] = [:]
        var loweredByNameBuckets: [InternedString: [(name: InternedString, symbol: SymbolID)]] = [:]

        for suspendFunction in suspendFunctions {
            let rawLowered = ctx.interner.intern("kk_suspend_" + ctx.interner.resolve(suspendFunction.name))
            let loweredName = uniqueFunctionName(
                preferred: rawLowered,
                existingFunctionNames: &existingFunctionNames,
                interner: ctx.interner
            )
            let loweredSymbol = defineSyntheticCoroutineFunctionSymbol(
                original: suspendFunction,
                loweredName: loweredName,
                nextSyntheticSymbol: &nextSyntheticSymbol,
                sema: ctx.sema
            )
            let continuationType = ctx.sema?.types.nullableAnyType ?? suspendFunction.returnType
            let continuationParameterSymbol = defineSyntheticContinuationParameterSymbol(
                owner: loweredSymbol,
                loweredName: loweredName,
                nextSyntheticSymbol: &nextSyntheticSymbol,
                sema: ctx.sema,
                interner: ctx.interner
            )
            let loweredBody = lowerSuspendBodyToStateMachineSkeleton(
                originalBody: suspendFunction.body,
                continuationParameterSymbol: continuationParameterSymbol,
                loweredSymbol: loweredSymbol,
                module: module,
                interner: ctx.interner,
                suspendFunctionSymbols: suspendFunctionSymbols,
                suspendFunctionNames: suspendFunctionNames
            )
            let loweredFunction = KIRFunction(
                symbol: loweredSymbol,
                name: loweredName,
                params: suspendFunction.params + [
                    KIRParameter(symbol: continuationParameterSymbol, type: continuationType)
                ],
                returnType: continuationType,
                body: loweredBody,
                isSuspend: false,
                isInline: false
            )
            _ = module.arena.appendDecl(.function(loweredFunction))

            let lowered = (name: loweredName, symbol: loweredSymbol)
            loweredBySymbol[suspendFunction.symbol] = lowered
            loweredByNameBuckets[suspendFunction.name, default: []].append(lowered)
            updateLoweredFunctionSignatureIfPossible(
                loweredSymbol: loweredSymbol,
                continuationParameterSymbol: continuationParameterSymbol,
                originalSymbol: suspendFunction.symbol,
                continuationType: continuationType,
                sema: ctx.sema
            )
        }

        let loweredByUniqueName = loweredByNameBuckets.reduce(into: [InternedString: (name: InternedString, symbol: SymbolID)]()) { partial, entry in
            guard entry.value.count == 1, let value = entry.value.first else {
                return
            }
            partial[entry.key] = value
        }
        let continuationProvider = ctx.interner.intern("kk_coroutine_suspended")

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                let loweredTarget: (name: InternedString, symbol: SymbolID)?
                if let symbol, let bySymbol = loweredBySymbol[symbol] {
                    loweredTarget = bySymbol
                } else if let byName = loweredByUniqueName[callee] {
                    loweredTarget = byName
                } else {
                    loweredTarget = nil
                }

                guard let loweredTarget else {
                    loweredBody.append(instruction)
                    continue
                }

                let continuationTemp = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                loweredBody.append(
                    .call(
                        symbol: nil,
                        callee: continuationProvider,
                        arguments: [],
                        result: continuationTemp,
                        outThrown: false
                    )
                )
                var loweredArguments = arguments
                loweredArguments.append(continuationTemp)
                loweredBody.append(
                    .call(
                        symbol: loweredTarget.symbol,
                        callee: loweredTarget.name,
                        arguments: loweredArguments,
                        result: result,
                        outThrown: outThrown
                    )
                )
            }
            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func nextAvailableSyntheticSymbol(module: KIRModule, sema: SemaModule?) -> Int32 {
        var maxRaw: Int32 = 0
        for decl in module.arena.declarations {
            switch decl {
            case .function(let function):
                maxRaw = max(maxRaw, function.symbol.rawValue + 1)
            case .global(let global):
                maxRaw = max(maxRaw, global.symbol.rawValue + 1)
            case .nominalType(let nominal):
                maxRaw = max(maxRaw, nominal.symbol.rawValue + 1)
            }
        }
        if let sema {
            maxRaw = max(maxRaw, Int32(sema.symbols.count))
        }
        return maxRaw
    }

    private func allocateSyntheticSymbol(_ nextSyntheticSymbol: inout Int32) -> SymbolID {
        let id = SymbolID(rawValue: nextSyntheticSymbol)
        nextSyntheticSymbol += 1
        return id
    }

    private func uniqueFunctionName(
        preferred: InternedString,
        existingFunctionNames: inout Set<InternedString>,
        interner: StringInterner
    ) -> InternedString {
        if existingFunctionNames.insert(preferred).inserted {
            return preferred
        }
        let base = interner.resolve(preferred)
        var suffix = 1
        while true {
            let candidate = interner.intern("\(base)$\(suffix)")
            if existingFunctionNames.insert(candidate).inserted {
                return candidate
            }
            suffix += 1
        }
    }

    private func defineSyntheticCoroutineFunctionSymbol(
        original: KIRFunction,
        loweredName: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?
    ) -> SymbolID {
        guard let sema, let originalSymbol = sema.symbols.symbol(original.symbol) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let loweredFQName = Array(originalSymbol.fqName.dropLast()) + [loweredName]
        return sema.symbols.define(
            kind: .function,
            name: loweredName,
            fqName: loweredFQName,
            declSite: originalSymbol.declSite,
            visibility: originalSymbol.visibility,
            flags: [.synthetic, .static]
        )
    }

    private func defineSyntheticContinuationParameterSymbol(
        owner: SymbolID,
        loweredName: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?,
        interner: StringInterner
    ) -> SymbolID {
        guard let sema, let loweredSymbol = sema.symbols.symbol(owner) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let parameterName = interner.intern("$continuation")
        return sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: loweredSymbol.fqName + [parameterName],
            declSite: loweredSymbol.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
    }

    private func updateLoweredFunctionSignatureIfPossible(
        loweredSymbol: SymbolID,
        continuationParameterSymbol: SymbolID,
        originalSymbol: SymbolID,
        continuationType: TypeID,
        sema: SemaModule?
    ) {
        guard let sema else {
            return
        }
        let originalSignature = sema.symbols.functionSignature(for: originalSymbol)
        let loweredParameterTypes = (originalSignature?.parameterTypes ?? []) + [continuationType]
        let loweredValueSymbols = (originalSignature?.valueParameterSymbols ?? []) + [continuationParameterSymbol]
        let loweredDefaults = (originalSignature?.valueParameterHasDefaultValues ?? []) + [false]
        let loweredVararg = (originalSignature?.valueParameterIsVararg ?? []) + [false]
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: originalSignature?.receiverType,
                parameterTypes: loweredParameterTypes,
                returnType: continuationType,
                isSuspend: false,
                valueParameterSymbols: loweredValueSymbols,
                valueParameterHasDefaultValues: loweredDefaults,
                valueParameterIsVararg: loweredVararg,
                typeParameterSymbols: originalSignature?.typeParameterSymbols ?? []
            ),
            for: loweredSymbol
        )
    }

    private func lowerSuspendBodyToStateMachineSkeleton(
        originalBody: [KIRInstruction],
        continuationParameterSymbol: SymbolID,
        loweredSymbol: SymbolID,
        module: KIRModule,
        interner: StringInterner,
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>
    ) -> [KIRInstruction] {
        let enterCallee = interner.intern("kk_coroutine_state_enter")
        let setLabelCallee = interner.intern("kk_coroutine_state_set_label")
        let exitCallee = interner.intern("kk_coroutine_state_exit")
        let suspendedProvider = interner.intern("kk_coroutine_suspended")

        let stateBlocks = buildSuspendStateBlocks(
            originalBody: originalBody,
            suspendFunctionSymbols: suspendFunctionSymbols,
            suspendFunctionNames: suspendFunctionNames
        )

        var lowered: [KIRInstruction] = []
        lowered.reserveCapacity(originalBody.count * 3 + 16)

        let continuationExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(.constValue(result: continuationExpr, value: .symbolRef(continuationParameterSymbol)))

        let functionIDExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(.constValue(result: functionIDExpr, value: .intLiteral(Int64(loweredSymbol.rawValue))))

        let resumeLabelExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(
            .call(
                symbol: nil,
                callee: enterCallee,
                arguments: [continuationExpr, functionIDExpr],
                result: resumeLabelExpr,
                outThrown: false
            )
        )

        for block in stateBlocks {
            let expectedResumeExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
            lowered.append(.constValue(result: expectedResumeExpr, value: .intLiteral(block.resumeLabel)))
            lowered.append(
                .jumpIfEqual(
                    lhs: resumeLabelExpr,
                    rhs: expectedResumeExpr,
                    target: stateDispatchLabel(for: block.resumeLabel)
                )
            )
        }
        lowered.append(.jump(stateDispatchLabel(for: stateBlocks.first?.resumeLabel ?? 0)))

        for (index, block) in stateBlocks.enumerated() {
            lowered.append(.label(stateDispatchLabel(for: block.resumeLabel)))
            let nextResumeLabel = stateBlocks.indices.contains(index + 1)
                ? stateBlocks[index + 1].resumeLabel
                : nil

            for instruction in block.instructions {
                if case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction,
                   isSuspendCall(
                    symbol: symbol,
                    callee: callee,
                    suspendFunctionSymbols: suspendFunctionSymbols,
                    suspendFunctionNames: suspendFunctionNames
                   ),
                   let nextResumeLabel {
                    let resumeLabelExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    lowered.append(.constValue(result: resumeLabelExpr, value: .intLiteral(nextResumeLabel)))

                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: setLabelCallee,
                            arguments: [continuationExpr, resumeLabelExpr],
                            result: nil,
                            outThrown: false
                        )
                    )

                    let suspensionResult = result ?? module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    lowered.append(
                        .call(
                            symbol: symbol,
                            callee: callee,
                            arguments: arguments,
                            result: suspensionResult,
                            outThrown: outThrown
                        )
                    )

                    let suspendedExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: suspendedProvider,
                            arguments: [],
                            result: suspendedExpr,
                            outThrown: false
                        )
                    )
                    lowered.append(.returnIfEqual(lhs: suspensionResult, rhs: suspendedExpr))
                    continue
                }

                switch instruction {
                case .returnValue(let value):
                    let exitValueExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: exitCallee,
                            arguments: [continuationExpr, value],
                            result: exitValueExpr,
                            outThrown: false
                        )
                    )
                    lowered.append(.returnValue(exitValueExpr))

                case .returnUnit:
                    let unitExpr = module.arena.appendExpr(.unit)
                    let exitValueExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    lowered.append(
                        .call(
                            symbol: nil,
                            callee: exitCallee,
                            arguments: [continuationExpr, unitExpr],
                            result: exitValueExpr,
                            outThrown: false
                        )
                    )
                    lowered.append(.returnValue(exitValueExpr))

                default:
                    lowered.append(instruction)
                }
            }
        }

        return lowered
    }

    private func stateDispatchLabel(for resumeLabel: Int64) -> Int32 {
        Int32(1000 + resumeLabel)
    }

    private struct SuspendStateBlock {
        let resumeLabel: Int64
        let instructions: [KIRInstruction]
    }

    private struct CFGBlock {
        let id: Int
        let instructions: [KIRInstruction]
        let successors: [Int]
    }

    private func buildSuspendStateBlocks(
        originalBody: [KIRInstruction],
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>
    ) -> [SuspendStateBlock] {
        let cfgBlocks = buildControlFlowBlocks(originalBody)
        guard !cfgBlocks.isEmpty else {
            return [SuspendStateBlock(resumeLabel: 0, instructions: [])]
        }

        let reachableOrder = reachableBlockOrder(cfgBlocks: cfgBlocks)

        var blocks: [SuspendStateBlock] = []
        var currentResumeLabel: Int64 = 0
        var nextResumeLabel: Int64 = 1

        for blockID in reachableOrder {
            let cfgBlock = cfgBlocks[blockID]
            var chunk: [KIRInstruction] = []
            chunk.reserveCapacity(cfgBlock.instructions.count)

            for instruction in cfgBlock.instructions {
                chunk.append(instruction)

                guard case .call(let symbol, let callee, _, _, _) = instruction else {
                    continue
                }
                guard isSuspendCall(
                    symbol: symbol,
                    callee: callee,
                    suspendFunctionSymbols: suspendFunctionSymbols,
                    suspendFunctionNames: suspendFunctionNames
                ) else {
                    continue
                }

                blocks.append(
                    SuspendStateBlock(
                        resumeLabel: currentResumeLabel,
                        instructions: chunk
                    )
                )
                chunk = []
                currentResumeLabel = nextResumeLabel
                nextResumeLabel += 1
            }

            if !chunk.isEmpty {
                blocks.append(
                    SuspendStateBlock(
                        resumeLabel: currentResumeLabel,
                        instructions: chunk
                    )
                )
                currentResumeLabel = nextResumeLabel
                nextResumeLabel += 1
            }
        }

        if blocks.isEmpty {
            return [SuspendStateBlock(resumeLabel: 0, instructions: [])]
        }
        return blocks
    }

    private func buildControlFlowBlocks(_ instructions: [KIRInstruction]) -> [CFGBlock] {
        guard !instructions.isEmpty else {
            return []
        }

        var labelToInstructionIndex: [Int32: Int] = [:]
        for (index, instruction) in instructions.enumerated() {
            if case .label(let labelID) = instruction {
                labelToInstructionIndex[labelID] = index
            }
        }

        var leaders: Set<Int> = [0]
        for (index, instruction) in instructions.enumerated() {
            switch instruction {
            case .label:
                leaders.insert(index)
            case .jump(let target):
                if let targetIndex = labelToInstructionIndex[target] {
                    leaders.insert(targetIndex)
                }
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            case .jumpIfEqual(_, _, let target):
                if let targetIndex = labelToInstructionIndex[target] {
                    leaders.insert(targetIndex)
                }
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            case .returnUnit, .returnValue, .returnIfEqual:
                if index + 1 < instructions.count {
                    leaders.insert(index + 1)
                }
            default:
                continue
            }
        }

        let sortedLeaders = leaders.sorted()
        var ranges: [(start: Int, end: Int)] = []
        ranges.reserveCapacity(sortedLeaders.count)
        for (index, start) in sortedLeaders.enumerated() {
            let end = index + 1 < sortedLeaders.count ? sortedLeaders[index + 1] : instructions.count
            if start < end {
                ranges.append((start: start, end: end))
            }
        }
        guard !ranges.isEmpty else {
            return []
        }

        var instructionToBlock: [Int: Int] = [:]
        for (blockID, range) in ranges.enumerated() {
            for instructionIndex in range.start..<range.end {
                instructionToBlock[instructionIndex] = blockID
            }
        }

        var blocks: [CFGBlock] = []
        blocks.reserveCapacity(ranges.count)

        for (blockID, range) in ranges.enumerated() {
            let blockInstructions = Array(instructions[range.start..<range.end])
            let terminator = blockInstructions.last

            var successors: [Int] = []
            switch terminator {
            case .some(.jump(let target)):
                if let targetInstruction = labelToInstructionIndex[target],
                   let targetBlock = instructionToBlock[targetInstruction] {
                    successors.append(targetBlock)
                }

            case .some(.jumpIfEqual(_, _, let target)):
                if let targetInstruction = labelToInstructionIndex[target],
                   let targetBlock = instructionToBlock[targetInstruction] {
                    successors.append(targetBlock)
                }
                if blockID + 1 < ranges.count {
                    successors.append(blockID + 1)
                }

            case .some(.returnUnit), .some(.returnValue), .some(.returnIfEqual):
                break

            default:
                if blockID + 1 < ranges.count {
                    successors.append(blockID + 1)
                }
            }

            var dedupedSuccessors: [Int] = []
            dedupedSuccessors.reserveCapacity(successors.count)
            for successor in successors where !dedupedSuccessors.contains(successor) {
                dedupedSuccessors.append(successor)
            }
            blocks.append(
                CFGBlock(
                    id: blockID,
                    instructions: blockInstructions,
                    successors: dedupedSuccessors
                )
            )
        }

        return blocks
    }

    private func reachableBlockOrder(cfgBlocks: [CFGBlock]) -> [Int] {
        guard !cfgBlocks.isEmpty else {
            return []
        }
        var order: [Int] = []
        var stack: [Int] = [0]
        var visited: Set<Int> = []

        while let blockID = stack.popLast() {
            guard visited.insert(blockID).inserted else {
                continue
            }
            order.append(blockID)
            let successors = cfgBlocks[blockID].successors
            for successor in successors.reversed() {
                stack.append(successor)
            }
        }
        return order
    }

    private func isSuspendCall(
        symbol: SymbolID?,
        callee: InternedString,
        suspendFunctionSymbols: Set<SymbolID>,
        suspendFunctionNames: Set<InternedString>
    ) -> Bool {
        if let symbol, suspendFunctionSymbols.contains(symbol) {
            return true
        }
        return suspendFunctionNames.contains(callee)
    }
}

private final class ABILoweringPass: LoweringImpl {
    static let name = "ABILowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_add"),
            ctx.interner.intern("kk_op_sub"),
            ctx.interner.intern("kk_op_mul"),
            ctx.interner.intern("kk_op_div"),
            ctx.interner.intern("kk_op_eq"),
            ctx.interner.intern("kk_when_select"),
            ctx.interner.intern("kk_for_lowered"),
            ctx.interner.intern("iterator"),
            ctx.interner.intern("kk_property_access"),
            ctx.interner.intern("kk_lambda_invoke"),
            ctx.interner.intern("kk_coroutine_suspended"),
            ctx.interner.intern("kk_coroutine_state_enter"),
            ctx.interner.intern("kk_coroutine_state_set_label"),
            ctx.interner.intern("kk_coroutine_state_exit")
        ]
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, _) = instruction else {
                    return instruction
                }
                return .call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    outThrown: !nonThrowingCallees.contains(callee)
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

public final class LoweringPhase: CompilerPhase {
    public static let name = "Lowerings"

    private let passes: [any LoweringImpl] = [
        NormalizeBlocksPass(),
        OperatorLoweringPass(),
        ForLoweringPass(),
        WhenLoweringPass(),
        PropertyLoweringPass(),
        DataEnumSealedSynthesisPass(),
        LambdaClosureConversionPass(),
        InlineLoweringPass(),
        CoroutineLoweringPass(),
        ABILoweringPass()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let module = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for lowering.")
        }
        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: ctx.interner,
            sema: ctx.sema
        )
        for pass in passes {
            try pass.run(module: module, ctx: kirCtx)
        }
    }
}

