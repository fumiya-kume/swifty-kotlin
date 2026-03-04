import Foundation

struct InlineExpansion {
    let instructions: [KIRInstruction]
    let returnedExpr: KIRExprID?
}

final class InlineLoweringPass: LoweringPass {
    static let name = "InlineLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        for decl in module.arena.declarations {
            if case let .function(function) = decl, function.isInline {
                return true
            }
        }
        if let imported = ctx.sema?.importedInlineFunctions, !imported.isEmpty {
            return true
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let unitType = ctx.sema?.types.unitType
        var inlineFunctionsBySymbol = Dictionary(uniqueKeysWithValues: module.arena.declarations.compactMap { decl -> (SymbolID, KIRFunction)? in
            guard case let .function(function) = decl, function.isInline else {
                return nil
            }
            return (function.symbol, function)
        })
        if let imported = ctx.sema?.importedInlineFunctions {
            for (symbol, function) in imported where inlineFunctionsBySymbol[symbol] == nil {
                inlineFunctionsBySymbol[symbol] = function
            }
        }
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

                guard case let .call(symbol, callee, arguments, result, _, _, _) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                let inlineTarget: KIRFunction? = if let symbol, let target = inlineFunctionsBySymbol[symbol] {
                    target
                } else if let byName = inlineFunctionsByName[callee], byName.count == 1 {
                    byName[0]
                } else {
                    nil
                }

                guard let inlineTarget, inlineTarget.symbol != function.symbol else {
                    loweredBody.append(instruction)
                    continue
                }
                let expansion = expandInlineCall(
                    inlineTarget: inlineTarget,
                    arguments: arguments,
                    module: module,
                    ctx: ctx
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
                        let unitExpr = module.arena.appendExpr(.unit, type: unitType)
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
        module: KIRModule,
        ctx: KIRContext
    ) -> InlineExpansion? {
        guard arguments.count == inlineTarget.params.count else {
            return nil
        }

        let parameterValues = Dictionary(uniqueKeysWithValues: zip(inlineTarget.params.map(\.symbol), arguments))

        var typeParamTokenValues: [SymbolID: KIRExprID] = [:]
        if let sema = ctx.sema,
           let sig = sema.symbols.functionSignature(for: inlineTarget.symbol),
           !sig.reifiedTypeParameterIndices.isEmpty {
            for index in sig.reifiedTypeParameterIndices.sorted() {
                guard index < sig.typeParameterSymbols.count else { continue }
                let typeParamSymbol = sig.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                if let tokenArg = parameterValues[tokenSymbol] {
                    typeParamTokenValues[typeParamSymbol] = tokenArg
                }
            }
        }

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

            case let .label(id):
                lowered.append(.label(id))

            case let .jump(target):
                lowered.append(.jump(target))

            case let .jumpIfEqual(lhs, rhs, target):
                lowered.append(
                    .jumpIfEqual(
                        lhs: resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: resolveAlias(of: rhs, aliases: localExprMap),
                        target: target
                    )
                )

            case .returnUnit:
                returnedExpr = nil

            case let .returnValue(value):
                returnedExpr = resolveAlias(of: value, aliases: localExprMap)

            case let .constValue(result, value):
                if case let .symbolRef(symbol) = value, let argument = parameterValues[symbol] {
                    localExprMap[result] = argument
                    continue
                }
                if case let .symbolRef(symbol) = value, let tokenArg = typeParamTokenValues[symbol] {
                    localExprMap[result] = tokenArg
                    continue
                }
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(.constValue(result: loweredResult, value: value))

            case let .binary(op, lhs, rhs, result):
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

            case let .call(symbol, callee, args, result, canThrow, thrownResult, isSuperCall):
                let loweredResult = result.map { expr -> KIRExprID in
                    let cloned = cloneExpr(expr, in: module.arena)
                    localExprMap[expr] = cloned
                    return cloned
                }
                let loweredThrownResult = thrownResult.map { expr -> KIRExprID in
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
                        canThrow: canThrow,
                        thrownResult: loweredThrownResult,
                        isSuperCall: isSuperCall
                    )
                )

            case let .virtualCall(symbol, callee, receiver, args, result, canThrow, thrownResult, dispatch):
                let loweredResult = result.map { expr -> KIRExprID in
                    let cloned = cloneExpr(expr, in: module.arena)
                    localExprMap[expr] = cloned
                    return cloned
                }
                let loweredThrownResult = thrownResult.map { expr -> KIRExprID in
                    let cloned = cloneExpr(expr, in: module.arena)
                    localExprMap[expr] = cloned
                    return cloned
                }
                lowered.append(
                    .virtualCall(
                        symbol: symbol,
                        callee: callee,
                        receiver: resolveAlias(of: receiver, aliases: localExprMap),
                        arguments: args.map { resolveAlias(of: $0, aliases: localExprMap) },
                        result: loweredResult,
                        canThrow: canThrow,
                        thrownResult: loweredThrownResult,
                        dispatch: dispatch
                    )
                )

            case let .returnIfEqual(lhs, rhs):
                lowered.append(
                    .returnIfEqual(
                        lhs: resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: resolveAlias(of: rhs, aliases: localExprMap)
                    )
                )

            case let .jumpIfNotNull(value, target):
                lowered.append(
                    .jumpIfNotNull(
                        value: resolveAlias(of: value, aliases: localExprMap),
                        target: target
                    )
                )

            case let .copy(from, to):
                lowered.append(
                    .copy(
                        from: resolveAlias(of: from, aliases: localExprMap),
                        to: resolveAlias(of: to, aliases: localExprMap)
                    )
                )

            case let .storeGlobal(value, symbol):
                lowered.append(
                    .storeGlobal(
                        value: resolveAlias(of: value, aliases: localExprMap),
                        symbol: symbol
                    )
                )

            case let .loadGlobal(result, symbol):
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(.loadGlobal(result: loweredResult, symbol: symbol))

            case let .rethrow(value):
                lowered.append(
                    .rethrow(value: resolveAlias(of: value, aliases: localExprMap))
                )

            case let .unary(op, operand, result):
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(
                    .unary(
                        op: op,
                        operand: resolveAlias(of: operand, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case let .nullAssert(operand, result):
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(
                    .nullAssert(
                        operand: resolveAlias(of: operand, aliases: localExprMap),
                        result: loweredResult
                    )
                )
            }
        }

        return InlineExpansion(instructions: lowered, returnedExpr: returnedExpr)
    }

    private func rewriteInstruction(_ instruction: KIRInstruction, aliases: [KIRExprID: KIRExprID]) -> KIRInstruction {
        switch instruction {
        case let .binary(op, lhs, rhs, result):
            .binary(
                op: op,
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases),
                result: result
            )

        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
            .call(
                symbol: symbol,
                callee: callee,
                arguments: arguments.map { resolveAlias(of: $0, aliases: aliases) },
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall
            )

        case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
            .virtualCall(
                symbol: symbol,
                callee: callee,
                receiver: resolveAlias(of: receiver, aliases: aliases),
                arguments: arguments.map { resolveAlias(of: $0, aliases: aliases) },
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                dispatch: dispatch
            )

        case let .returnValue(value):
            .returnValue(resolveAlias(of: value, aliases: aliases))

        case let .returnIfEqual(lhs, rhs):
            .returnIfEqual(
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases)
            )

        case let .jumpIfEqual(lhs, rhs, target):
            .jumpIfEqual(
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases),
                target: target
            )

        case let .jumpIfNotNull(value, target):
            .jumpIfNotNull(
                value: resolveAlias(of: value, aliases: aliases),
                target: target
            )

        case let .copy(from, to):
            .copy(
                from: resolveAlias(of: from, aliases: aliases),
                to: resolveAlias(of: to, aliases: aliases)
            )

        case let .rethrow(value):
            .rethrow(value: resolveAlias(of: value, aliases: aliases))

        case let .unary(op, operand, result):
            .unary(
                op: op,
                operand: resolveAlias(of: operand, aliases: aliases),
                result: result
            )

        case let .nullAssert(operand, result):
            .nullAssert(
                operand: resolveAlias(of: operand, aliases: aliases),
                result: result
            )

        case let .storeGlobal(value, symbol):
            .storeGlobal(
                value: resolveAlias(of: value, aliases: aliases),
                symbol: symbol
            )

        case .loadGlobal:
            instruction

        default:
            instruction
        }
    }

    private func definedResult(in instruction: KIRInstruction) -> KIRExprID? {
        switch instruction {
        case let .constValue(result, _):
            result
        case let .binary(_, _, _, result):
            result
        case let .call(_, _, _, result, _, _, _):
            result
        case let .virtualCall(_, _, _, _, result, _, _, _):
            result
        case let .unary(_, _, result):
            result
        case let .nullAssert(_, result):
            result
        case let .loadGlobal(result, _):
            result
        default:
            nil
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
        return arena.appendExpr(
            arena.expr(source) ?? fallback,
            type: arena.exprType(source)
        )
    }
}
