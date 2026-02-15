import Foundation

final class LambdaClosureConversionPass: LoweringImpl {
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

