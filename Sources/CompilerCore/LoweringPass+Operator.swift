import Foundation

final class OperatorLoweringPass: LoweringPass {
    static let name = "OperatorLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .binary(let op, let lhs, let rhs, let result) = instruction else {
                    return instruction
                }
                let callee: InternedString
                switch op {
                case .add:
                    callee = ctx.interner.intern("kk_op_add")
                case .subtract:
                    callee = ctx.interner.intern("kk_op_sub")
                case .multiply:
                    callee = ctx.interner.intern("kk_op_mul")
                case .divide:
                    callee = ctx.interner.intern("kk_op_div")
                case .equal:
                    callee = ctx.interner.intern("kk_op_eq")
                }
                return .call(symbol: nil, callee: callee, arguments: [lhs, rhs], result: result, canThrow: false)
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

