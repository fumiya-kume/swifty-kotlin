import Foundation

final class WhenLoweringPass: LoweringPass {
    static let name = "WhenLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let loweredCallee = ctx.interner.intern("kk_when_select")

        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                switch instruction {
                case .select(let condition, let thenValue, let elseValue, let result):
                    return .call(
                        symbol: nil,
                        callee: loweredCallee,
                        arguments: [condition, thenValue, elseValue],
                        result: result,
                        canThrow: false
                    )

                default:
                    return instruction
                }
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}
