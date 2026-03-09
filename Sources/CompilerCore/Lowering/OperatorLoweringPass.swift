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
                    let isUnsigned = self.isUnsignedOperand(lhs, arena: module.arena, types: types)
                        || self.isUnsignedOperand(rhs, arena: module.arena, types: types)
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
                    // For unsigned int/long: add/sub/mul/eq/ne use same callees; div/rem/lt/le/gt/ge use u-prefix
                    let useUnsignedRank0 = isUnsigned && rank == 0
                    let divModCmpPrefix = useUnsignedRank0 ? "u" : prefix
                    let divModOp = useUnsignedRank0 ? "rem" : "mod" // unsigned uses urem (LLVM), signed uses mod
                    let callee: InternedString = switch op {
                    case .add:
                        ctx.interner.intern("kk_op_\(prefix)add")
                    case .subtract:
                        ctx.interner.intern("kk_op_\(prefix)sub")
                    case .multiply:
                        ctx.interner.intern("kk_op_\(prefix)mul")
                    case .divide:
                        ctx.interner.intern("kk_op_\(divModCmpPrefix)div")
                    case .modulo:
                        ctx.interner.intern("kk_op_\(divModCmpPrefix)\(divModOp)")
                    case .equal:
                        ctx.interner.intern("kk_op_\(prefix)eq")
                    case .notEqual:
                        ctx.interner.intern("kk_op_\(prefix)ne")
                    case .lessThan:
                        ctx.interner.intern("kk_op_\(divModCmpPrefix)lt")
                    case .lessOrEqual:
                        ctx.interner.intern("kk_op_\(divModCmpPrefix)le")
                    case .greaterThan:
                        ctx.interner.intern("kk_op_\(divModCmpPrefix)gt")
                    case .greaterOrEqual:
                        ctx.interner.intern("kk_op_\(divModCmpPrefix)ge")
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
                            case .primitive(.long, .nonNull):
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
                            case .primitive(.float, .nonNull):
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
                            case .primitive(.double, .nonNull):
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
                            case .primitive(.char, .nonNull):
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
                            case .primitive(.boolean, _):
                                appendPrimitivePrintlnCall(
                                    to: &newBody,
                                    symbol: symbol,
                                    callee: ctx.interner.intern("kk_println_bool"),
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
                            if let dataClassString = rewriteDataClassPrintlnArgument(
                                argument: arguments[0],
                                arena: module.arena,
                                sema: ctx.sema,
                                interner: ctx.interner,
                                body: &newBody
                            ) {
                                newBody.append(.call(
                                    symbol: symbol,
                                    callee: callee,
                                    arguments: [dataClassString],
                                    result: result,
                                    canThrow: canThrow,
                                    thrownResult: thrownResult,
                                    isSuperCall: isSuperCall
                                ))
                                continue
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

    private func isUnsignedOperand(_ exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> Bool {
        guard let types, let typeID = arena.exprType(exprID) else { return false }
        switch types.kind(of: typeID) {
        case .primitive(.uint, _), .primitive(.ulong, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return true
        default:
            return false
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

    private func rewriteDataClassPrintlnArgument(
        argument: KIRExprID,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        body: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let sema,
              let argumentType = arena.exprType(argument),
              case let .classType(classType) = sema.types.kind(of: argumentType),
              let classSymbol = sema.symbols.symbol(classType.classSymbol),
              classSymbol.kind == .class,
              classSymbol.flags.contains(.dataType),
              let layout = sema.symbols.nominalLayout(for: classSymbol.id)
        else {
            return nil
        }

        let stringType = sema.types.stringType
        let intType = sema.types.intType
        let properties = sema.symbols.children(ofFQName: classSymbol.fqName)
            .compactMap { symbolID -> (SymbolID, SemanticSymbol)? in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .property
                else {
                    return nil
                }
                return (symbolID, symbol)
            }
            .sorted { $0.0.rawValue < $1.0.rawValue }

        func appendStringLiteral(_ value: String) -> KIRExprID {
            let interned = interner.intern(value)
            let expr = arena.appendExpr(.stringLiteral(interned), type: stringType)
            body.append(.constValue(result: expr, value: .stringLiteral(interned)))
            return expr
        }

        func appendConcat(_ lhs: KIRExprID, _ rhs: KIRExprID) -> KIRExprID {
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_concat"),
                arguments: [lhs, rhs],
                result: result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
            return result
        }

        func appendStringConversion(_ valueExpr: KIRExprID, type: TypeID) -> KIRExprID {
            if sema.types.isSubtype(type, stringType) {
                return valueExpr
            }
            let tag: Int64 = switch sema.types.kind(of: type) {
            case .primitive(.boolean, _):
                2
            case .primitive(.string, _):
                3
            default:
                1
            }
            let tagExpr = arena.appendExpr(.intLiteral(tag), type: intType)
            body.append(.constValue(result: tagExpr, value: .intLiteral(tag)))
            let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [valueExpr, tagExpr],
                result: converted,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
            return converted
        }

        var rendered = appendStringLiteral("\(interner.resolve(classSymbol.name))(")
        for (index, property) in properties.enumerated() {
            let separator = index == 0 ? "" : ", "
            rendered = appendConcat(
                rendered,
                appendStringLiteral("\(separator)\(interner.resolve(property.1.name))=")
            )

            let storageSymbol = sema.symbols.backingFieldSymbol(for: property.0) ?? property.0
            guard let fieldOffset = layout.fieldOffsets[storageSymbol] else {
                return nil
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

            let propertyType = sema.symbols.propertyType(for: property.0) ?? sema.types.anyType
            let loaded = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: propertyType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [argument, offsetExpr],
                result: loaded,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
            rendered = appendConcat(rendered, appendStringConversion(loaded, type: propertyType))
        }
        return appendConcat(rendered, appendStringLiteral(")"))
    }
}
