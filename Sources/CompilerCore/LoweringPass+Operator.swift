import Foundation

final class OperatorLoweringPass: LoweringPass {
    static let name = "OperatorLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                switch instruction {
                case .binary(let op, let lhs, let rhs, let result):
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
                    case .modulo:
                        callee = ctx.interner.intern("kk_op_mod")
                    case .equal:
                        callee = ctx.interner.intern("kk_op_eq")
                    case .notEqual:
                        callee = ctx.interner.intern("kk_op_ne")
                    case .lessThan:
                        callee = ctx.interner.intern("kk_op_lt")
                    case .lessOrEqual:
                        callee = ctx.interner.intern("kk_op_le")
                    case .greaterThan:
                        callee = ctx.interner.intern("kk_op_gt")
                    case .greaterOrEqual:
                        callee = ctx.interner.intern("kk_op_ge")
                    case .logicalAnd:
                        callee = ctx.interner.intern("kk_op_and")
                    case .logicalOr:
                        callee = ctx.interner.intern("kk_op_or")
                    }
                    return .call(symbol: nil, callee: callee, arguments: [lhs, rhs], result: result, canThrow: false)
                case .unary(let op, let operand, let result):
                    let callee: InternedString
                    switch op {
                    case .not:
                        callee = ctx.interner.intern("kk_op_not")
                    case .unaryPlus:
                        callee = ctx.interner.intern("kk_op_uplus")
                    case .unaryMinus:
                        callee = ctx.interner.intern("kk_op_uminus")
                    }
                    return .call(symbol: nil, callee: callee, arguments: [operand], result: result, canThrow: false)
                case .nullAssert(let operand, let result):
                    return .call(symbol: nil, callee: ctx.interner.intern("kk_op_notnull"), arguments: [operand], result: result, canThrow: true)
                default:
                    return instruction
                }
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

