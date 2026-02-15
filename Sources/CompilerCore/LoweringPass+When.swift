import Foundation

final class WhenLoweringPass: LoweringImpl {
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

