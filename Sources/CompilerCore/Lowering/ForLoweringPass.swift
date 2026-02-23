import Foundation

final class ForLoweringPass: LoweringPass {
    static let name = "ForLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let marker = ctx.interner.intern("kk_for_lowered")
        for decl in module.arena.declarations {
            guard case .function(let function) = decl else { continue }
            for instruction in function.body {
                if case .call(_, let callee, _, _, _, _, _) = instruction,
                   callee == marker {
                    return true
                }
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let marker = ctx.interner.intern("kk_for_lowered")
        let hasNext = ctx.interner.intern("hasNext")
        let next = ctx.interner.intern("next")

        module.arena.transformFunctions { function in
            var updated = function
            var rewrittenBody: [KIRInstruction] = []
            var didRewrite = false

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, _, _, _) = instruction,
                      callee == marker,
                      let iteratorValue = arguments.first else {
                    rewrittenBody.append(instruction)
                    continue
                }

                didRewrite = true
                let hasNextResult = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                rewrittenBody.append(.call(
                    symbol: nil,
                    callee: hasNext,
                    arguments: [iteratorValue],
                    result: hasNextResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                rewrittenBody.append(.call(
                    symbol: symbol,
                    callee: next,
                    arguments: [iteratorValue],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }

            if didRewrite {
                updated.body = rewrittenBody
            }
            return updated
        }

        module.recordLowering(Self.name)
    }
}
