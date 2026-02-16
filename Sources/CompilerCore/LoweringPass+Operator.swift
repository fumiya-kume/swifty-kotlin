import Foundation

final class OperatorLoweringPass: LoweringPass {
    static let name = "OperatorLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        let types = ctx.sema?.types
        let printlnCallee = ctx.interner.intern("println")
        let kkPrintlnAnyCallee = ctx.interner.intern("kk_println_any")

        module.arena.transformFunctions { function in
            var updated = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                switch instruction {
                case .binary(let op, let lhs, let rhs, let result):
                    let lhsRank = self.primitiveRank(for: lhs, arena: module.arena, types: types)
                    let rhsRank = self.primitiveRank(for: rhs, arena: module.arena, types: types)
                    let rank = max(lhsRank, rhsRank)
                    let prefix: String
                    switch rank {
                    case 2: prefix = "d"
                    case 1: prefix = "f"
                    default: prefix = ""
                    }
                    var effectiveLhs = lhs
                    var effectiveRhs = rhs
                    if rank > 0 {
                        if lhsRank < rank {
                            let convCallee = self.conversionCallee(fromRank: lhsRank, toRank: rank, interner: ctx.interner)
                            let converted = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)),
                                type: module.arena.exprType(result)
                            )
                            newBody.append(.call(symbol: nil, callee: convCallee, arguments: [lhs], result: converted, canThrow: false, thrownResult: nil))
                            effectiveLhs = converted
                        }
                        if rhsRank < rank {
                            let convCallee = self.conversionCallee(fromRank: rhsRank, toRank: rank, interner: ctx.interner)
                            let converted = module.arena.appendExpr(
                                .temporary(Int32(module.arena.expressions.count)),
                                type: module.arena.exprType(result)
                            )
                            newBody.append(.call(symbol: nil, callee: convCallee, arguments: [rhs], result: converted, canThrow: false, thrownResult: nil))
                            effectiveRhs = converted
                        }
                    }
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
                    newBody.append(.call(symbol: nil, callee: callee, arguments: [effectiveLhs, effectiveRhs], result: result, canThrow: false, thrownResult: nil))
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
                    newBody.append(.call(symbol: nil, callee: callee, arguments: [operand], result: result, canThrow: false, thrownResult: nil))
                case .nullAssert(let operand, let result):
                    newBody.append(.call(symbol: nil, callee: ctx.interner.intern("kk_op_notnull"), arguments: [operand], result: result, canThrow: true, thrownResult: nil))
                case .call(let symbol, let callee, let arguments, let result, let canThrow, let thrownResult):
                    if (callee == printlnCallee || callee == kkPrintlnAnyCallee),
                       arguments.count == 1,
                       let types {
                        let argType = module.arena.exprType(arguments[0])
                        if let argType {
                            switch types.kind(of: argType) {
                            case .primitive(.float, _):
                                newBody.append(.call(symbol: symbol, callee: ctx.interner.intern("kk_println_float"), arguments: arguments, result: result, canThrow: canThrow, thrownResult: thrownResult))
                                continue
                            case .primitive(.double, _):
                                newBody.append(.call(symbol: symbol, callee: ctx.interner.intern("kk_println_double"), arguments: arguments, result: result, canThrow: canThrow, thrownResult: thrownResult))
                                continue
                            case .primitive(.char, _):
                                newBody.append(.call(symbol: symbol, callee: ctx.interner.intern("kk_println_char"), arguments: arguments, result: result, canThrow: canThrow, thrownResult: thrownResult))
                                continue
                            default:
                                break
                            }
                        }
                    }
                    newBody.append(instruction)
                default:
                    newBody.append(instruction)
                }
            }
            updated.body = newBody
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func primitiveRank(for exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> Int {
        guard let types, let typeID = arena.exprType(exprID) else { return 0 }
        switch types.kind(of: typeID) {
        case .primitive(.double, _): return 2
        case .primitive(.float, _): return 1
        default: return 0
        }
    }

    private func conversionCallee(fromRank: Int, toRank: Int, interner: StringInterner) -> InternedString {
        if toRank == 1 {
            return interner.intern("kk_int_to_float_bits")
        }
        if fromRank == 1 {
            return interner.intern("kk_float_to_double_bits")
        }
        return interner.intern("kk_int_to_double_bits")
    }
}

