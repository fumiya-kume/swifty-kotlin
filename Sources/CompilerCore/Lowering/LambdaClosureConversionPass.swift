import Foundation

final class LambdaClosureConversionPass: LoweringPass {
    static let name = "LambdaClosureConversion"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let marker = ctx.interner.intern("<lambda>")
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                if case let .call(_, callee, _, _, _, _, _) = instruction,
                   callee == marker
                {
                    return true
                }
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let markerCallee = ctx.interner.intern("<lambda>")
        let loweredCallee = ctx.interner.intern("kk_lambda_invoke")

        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall) = instruction,
                      callee == markerCallee
                else {
                    return instruction
                }
                return .call(
                    symbol: symbol,
                    callee: loweredCallee,
                    arguments: arguments,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}
