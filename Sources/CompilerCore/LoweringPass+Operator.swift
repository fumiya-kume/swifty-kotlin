import Foundation

final class OperatorLoweringPass: LoweringPass {
    static let name = "OperatorLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        let types = ctx.sema?.types
        let printlnCallee = ctx.interner.intern("println")
        let kkPrintlnAnyCallee = ctx.interner.intern("kk_println_any")

        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                switch instruction {
                case .binary(let op, let lhs, let rhs, let result):
                    let prefix = self.operatorPrefix(for: lhs, arena: module.arena, types: types)
                    let callee: InternedString
                    switch op {
                    case .add:
                        callee = ctx.interner.intern("kk_op_\(prefix)add")
                    case .subtract:
                        callee = ctx.interner.intern("kk_op_\(prefix)sub")
                    case .multiply:
                        callee = ctx.interner.intern("kk_op_\(prefix)mul")
                    case .divide:
                        callee = ctx.interner.intern("kk_op_\(prefix)div")
                    case .modulo:
                        callee = ctx.interner.intern("kk_op_\(prefix)mod")
                    case .equal:
                        callee = ctx.interner.intern("kk_op_\(prefix)eq")
                    case .notEqual:
                        callee = ctx.interner.intern("kk_op_\(prefix)ne")
                    case .lessThan:
                        callee = ctx.interner.intern("kk_op_\(prefix)lt")
                    case .lessOrEqual:
                        callee = ctx.interner.intern("kk_op_\(prefix)le")
                    case .greaterThan:
                        callee = ctx.interner.intern("kk_op_\(prefix)gt")
                    case .greaterOrEqual:
                        callee = ctx.interner.intern("kk_op_\(prefix)ge")
                    case .logicalAnd:
                        callee = ctx.interner.intern("kk_op_and")
                    case .logicalOr:
                        callee = ctx.interner.intern("kk_op_or")
                    }
                    return .call(symbol: nil, callee: callee, arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil)
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
                    return .call(symbol: nil, callee: callee, arguments: [operand], result: result, canThrow: false, thrownResult: nil)
                case .nullAssert(let operand, let result):
                    return .call(symbol: nil, callee: ctx.interner.intern("kk_op_notnull"), arguments: [operand], result: result, canThrow: true, thrownResult: nil)
                case .call(let symbol, let callee, let arguments, let result, let canThrow, let thrownResult):
                    if (callee == printlnCallee || callee == kkPrintlnAnyCallee),
                       arguments.count == 1,
                       let types {
                        let argType = module.arena.exprType(arguments[0])
                        if let argType {
                            switch types.kind(of: argType) {
                            case .primitive(.float, _):
                                return .call(symbol: symbol, callee: ctx.interner.intern("kk_println_float"), arguments: arguments, result: result, canThrow: canThrow, thrownResult: thrownResult)
                            case .primitive(.double, _):
                                return .call(symbol: symbol, callee: ctx.interner.intern("kk_println_double"), arguments: arguments, result: result, canThrow: canThrow, thrownResult: thrownResult)
                            case .primitive(.char, _):
                                return .call(symbol: symbol, callee: ctx.interner.intern("kk_println_char"), arguments: arguments, result: result, canThrow: canThrow, thrownResult: thrownResult)
                            default:
                                break
                            }
                        }
                    }
                    return instruction
                default:
                    return instruction
                }
            }
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func operatorPrefix(for exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> String {
        guard let types,
              let typeID = arena.exprType(exprID) else {
            return ""
        }
        switch types.kind(of: typeID) {
        case .primitive(.float, _):
            return "f"
        case .primitive(.double, _):
            return "d"
        default:
            return ""
        }
    }
}

