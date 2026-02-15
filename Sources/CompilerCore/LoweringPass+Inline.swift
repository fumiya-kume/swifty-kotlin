import Foundation

struct InlineExpansion {
    let instructions: [KIRInstruction]
    let returnedExpr: KIRExprID?
}

final class InlineLoweringPass: LoweringImpl {
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

