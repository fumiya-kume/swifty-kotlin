import Foundation

final class PropertyLoweringPass: LoweringPass {
    static let name = "PropertyLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let getterName = ctx.interner.intern("get")
        let setterName = ctx.interner.intern("set")
        let loweredCallee = ctx.interner.intern("kk_property_access")
        let boolType = ctx.sema?.types.make(.primitive(.boolean, .nonNull))

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let canThrow) = instruction else {
                    loweredBody.append(instruction)
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
                        canThrow: canThrow
                    )
                )
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}
