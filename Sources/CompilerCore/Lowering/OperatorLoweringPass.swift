import Foundation

final class OperatorLoweringPass: LoweringPass {
    static let name = "OperatorLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let printlnCallee = ctx.interner.intern("println")
        let kkPrintlnAnyCallee = ctx.interner.intern("kk_println_any")
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                switch instruction {
                case .binary, .unary, .nullAssert:
                    return true
                case let .call(_, callee, _, _, _, _, _):
                    if callee == printlnCallee || callee == kkPrintlnAnyCallee {
                        return true
                    }
                default:
                    break
                }
            }
        }
        return false
    }

    // swiftlint:disable:next function_body_length
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
                case let .binary(op, lhs, rhs, result):
                    let lhsRank = self.primitiveRank(for: lhs, arena: module.arena, types: types)
                    let rhsRank = self.primitiveRank(for: rhs, arena: module.arena, types: types)
                    let rank = max(lhsRank, rhsRank)
                    let prefix = switch rank {
                    case 2: "d"
                    case 1: "f"
                    default: ""
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
                    let callee: InternedString = switch op {
                    case .add:
                        ctx.interner.intern("kk_op_\(prefix)add")
                    case .subtract:
                        ctx.interner.intern("kk_op_\(prefix)sub")
                    case .multiply:
                        ctx.interner.intern("kk_op_\(prefix)mul")
                    case .divide:
                        ctx.interner.intern("kk_op_\(prefix)div")
                    case .modulo:
                        ctx.interner.intern("kk_op_\(prefix)mod")
                    case .equal:
                        ctx.interner.intern("kk_op_\(prefix)eq")
                    case .notEqual:
                        ctx.interner.intern("kk_op_\(prefix)ne")
                    case .lessThan:
                        ctx.interner.intern("kk_op_\(prefix)lt")
                    case .lessOrEqual:
                        ctx.interner.intern("kk_op_\(prefix)le")
                    case .greaterThan:
                        ctx.interner.intern("kk_op_\(prefix)gt")
                    case .greaterOrEqual:
                        ctx.interner.intern("kk_op_\(prefix)ge")
                    case .logicalAnd:
                        ctx.interner.intern("kk_op_and")
                    case .logicalOr:
                        ctx.interner.intern("kk_op_or")
                    }
                    newBody.append(.call(symbol: nil, callee: callee, arguments: [effectiveLhs, effectiveRhs], result: result, canThrow: false, thrownResult: nil))
                case let .unary(op, operand, result):
                    let callee: InternedString = switch op {
                    case .not:
                        ctx.interner.intern("kk_op_not")
                    case .unaryPlus:
                        ctx.interner.intern("kk_op_uplus")
                    case .unaryMinus:
                        ctx.interner.intern("kk_op_uminus")
                    }
                    newBody.append(.call(symbol: nil, callee: callee, arguments: [operand], result: result, canThrow: false, thrownResult: nil))
                case let .nullAssert(operand, result):
                    newBody.append(.call(symbol: nil, callee: ctx.interner.intern("kk_op_notnull"), arguments: [operand], result: result, canThrow: true, thrownResult: nil))
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
                    if callee == printlnCallee || callee == kkPrintlnAnyCallee,
                       arguments.count == 1,
                       let types
                    {
                        let argType = module.arena.exprType(arguments[0])
                        if let argType {
                            switch types.kind(of: argType) {
                            case .primitive(.long, _):
                                appendPrimitivePrintlnCall(
                                    to: &newBody,
                                    symbol: symbol,
                                    callee: ctx.interner.intern("kk_println_long"),
                                    arguments: arguments,
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult,
                                    isSuperCall: isSuperCall
                                )
                                continue
                            case .primitive(.float, _):
                                appendPrimitivePrintlnCall(
                                    to: &newBody,
                                    symbol: symbol,
                                    callee: ctx.interner.intern("kk_println_float"),
                                    arguments: arguments,
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult,
                                    isSuperCall: isSuperCall
                                )
                                continue
                            case .primitive(.double, _):
                                appendPrimitivePrintlnCall(
                                    to: &newBody,
                                    symbol: symbol,
                                    callee: ctx.interner.intern("kk_println_double"),
                                    arguments: arguments,
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult,
                                    isSuperCall: isSuperCall
                                )
                                continue
                            case .primitive(.char, _):
                                appendPrimitivePrintlnCall(
                                    to: &newBody,
                                    symbol: symbol,
                                    callee: ctx.interner.intern("kk_println_char"),
                                    arguments: arguments,
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult,
                                    isSuperCall: isSuperCall
                                )
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

    // swiftlint:disable:next function_parameter_count
    private func appendPrimitivePrintlnCall(
        to body: inout [KIRInstruction],
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        isSuperCall: Bool
    ) {
        // Keep the lowered runtime call side-effect only and synthesize Unit explicitly.
        body.append(
            .call(
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: nil,
                canThrow: canThrow,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall
            )
        )
        if let result {
            body.append(.constValue(result: result, value: .unit))
        }
    }
}
