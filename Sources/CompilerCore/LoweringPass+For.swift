import Foundation

final class ForLoweringPass: LoweringImpl {
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

