import Foundation

final class PropertyLoweringPass: LoweringPass {
    static let name = "PropertyLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let getterName = ctx.interner.intern("get")
        let setterName = ctx.interner.intern("set")
        let getValueName = ctx.interner.intern("getValue")
        let setValueName = ctx.interner.intern("setValue")
        let loweredCallee = ctx.interner.intern("kk_property_access")
        let boolType = ctx.sema?.types.make(.primitive(.boolean, .nonNull))

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let canThrow, let thrownResult) = instruction else {
                    // Rewrite backing field copy instructions to
                    // kk_property_access when the target is a backing field symbol.
                    if case .copy(let from, let to) = instruction,
                       let sema = ctx.sema {
                        let toExpr = module.arena.expr(to)
                        if case .symbolRef(let targetSym) = toExpr,
                           sema.symbols.symbol(targetSym)?.kind == .backingField {
                            // Emit as a setter-style kk_property_access call.
                            let isSetter = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)),
                                type: boolType
                            )
                            loweredBody.append(
                                .constValue(result: isSetter, value: .boolLiteral(true))
                            )
                            loweredBody.append(
                                .call(
                                    symbol: targetSym,
                                    callee: loweredCallee,
                                    arguments: [isSetter, from],
                                    result: nil,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                    }
                    loweredBody.append(instruction)
                    continue
                }

                // Lower delegated property getValue/setValue calls to
                // kk_property_access with the delegate-aware signature.
                if callee == getValueName || callee == setValueName {
                    let isSetter = callee == setValueName
                    let accessorKind = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: boolType
                    )
                    loweredBody.append(
                        .constValue(result: accessorKind, value: .boolLiteral(isSetter))
                    )
                    var loweredArguments: [KIRExprID] = [accessorKind]
                    loweredArguments.append(contentsOf: arguments)
                    loweredBody.append(
                        .call(
                            symbol: symbol,
                            callee: loweredCallee,
                            arguments: loweredArguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult
                        )
                    )
                    continue
                }

                guard callee == getterName || callee == setterName else {
                    loweredBody.append(instruction)
                    continue
                }

                let isSetter = callee == setterName
                let accessorKind = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: boolType
                )
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
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    )
                )
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}
