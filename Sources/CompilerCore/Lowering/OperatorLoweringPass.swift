import Foundation

final class OperatorLoweringPass: LoweringPass {
    static let name = "OperatorLowering"

    private struct PrintlnConversionCallees {
        let intToFloat: InternedString
        let intToFloatBits: InternedString
        let floatToDoubleBits: InternedString
        let intToDoubleBits: InternedString
        let rangeCallees: Set<InternedString>
    }

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
        let printlnCallee = ctx.interner.intern("println")
        let kkPrintlnAnyCallee = ctx.interner.intern("kk_println_any")

        let printlnConversionCallees = PrintlnConversionCallees(
            intToFloat: ctx.interner.intern("kk_int_to_float"),
            intToFloatBits: ctx.interner.intern("kk_int_to_float_bits"),
            floatToDoubleBits: ctx.interner.intern("kk_float_to_double_bits"),
            intToDoubleBits: ctx.interner.intern("kk_int_to_double_bits"),
            rangeCallees: [
                ctx.interner.intern("kk_op_rangeTo"),
                ctx.interner.intern("kk_op_rangeUntil"),
                ctx.interner.intern("kk_op_ulong_rangeUntil"),
                ctx.interner.intern("kk_op_downTo"),
                ctx.interner.intern("kk_op_step"),
                ctx.interner.intern("kk_range_reversed"),
            ]
        )

        module.arena.transformFunctions { function in
            var updated = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                switch instruction {
                case let .binary(op, lhs, rhs, result):
                    lowerBinaryInstruction(
                        op: op, lhs: lhs, rhs: rhs, result: result,
                        arena: module.arena, interner: ctx.interner,
                        types: ctx.sema?.types, newBody: &newBody
                    )
                case let .unary(op, operand, result):
                    let callee: InternedString = switch op {
                    case .not: ctx.interner.intern("kk_op_not")
                    case .unaryPlus: ctx.interner.intern("kk_op_uplus")
                    case .unaryMinus: ctx.interner.intern("kk_op_uminus")
                    }
                    newBody.append(.call(symbol: nil, callee: callee, arguments: [operand], result: result, canThrow: false, thrownResult: nil))
                case let .nullAssert(operand, result):
                    newBody.append(.call(symbol: nil, callee: ctx.interner.intern("kk_op_notnull"), arguments: [operand], result: result, canThrow: true, thrownResult: nil))
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
                    if callee == printlnCallee || callee == kkPrintlnAnyCallee,
                       arguments.count == 1,
                       tryLowerPrintlnCall(
                           symbol: symbol, callee: callee, arguments: arguments,
                           result: result, canThrow: canThrow, thrownResult: thrownResult,
                           isSuperCall: isSuperCall, arena: module.arena,
                           ctx: ctx, newBody: &newBody,
                           precedingInstructions: newBody,
                           conversionCallees: printlnConversionCallees
                       )
                    {
                        continue
                    }
                    newBody.append(instruction)
                default:
                    newBody.append(instruction)
                }
            }
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func lowerBinaryInstruction(
        op: KIRBinaryOp,
        lhs: KIRExprID,
        rhs: KIRExprID,
        result: KIRExprID,
        arena: KIRArena,
        interner: StringInterner,
        types: TypeSystem?,
        newBody: inout [KIRInstruction]
    ) {
        let lhsRank = primitiveRank(for: lhs, arena: arena, types: types)
        let rhsRank = primitiveRank(for: rhs, arena: arena, types: types)
        let rank = max(lhsRank, rhsRank)
        let isUnsigned = isUnsignedOperand(lhs, arena: arena, types: types)
            || isUnsignedOperand(rhs, arena: arena, types: types)
        let prefix = switch rank {
        case 2: "d"
        case 1: "f"
        default: ""
        }
        var effectiveLhs = lhs
        var effectiveRhs = rhs
        if rank > 0 {
            if lhsRank < rank {
                let convCallee = conversionCallee(fromRank: lhsRank, toRank: rank, interner: interner)
                let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: arena.exprType(result))
                newBody.append(.call(symbol: nil, callee: convCallee, arguments: [lhs], result: converted, canThrow: false, thrownResult: nil))
                effectiveLhs = converted
            }
            if rhsRank < rank {
                let convCallee = conversionCallee(fromRank: rhsRank, toRank: rank, interner: interner)
                let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: arena.exprType(result))
                newBody.append(.call(symbol: nil, callee: convCallee, arguments: [rhs], result: converted, canThrow: false, thrownResult: nil))
                effectiveRhs = converted
            }
        }
        // For unsigned int/long: add/sub/mul/eq/ne use same callees; div/rem/lt/le/gt/ge use u-prefix
        let useUnsignedRank0 = isUnsigned && rank == 0
        let divModCmpPrefix = useUnsignedRank0 ? "u" : prefix
        let divModOp = useUnsignedRank0 ? "rem" : "mod" // unsigned uses urem (LLVM), signed uses mod
        // For == / != on non-primitive reference types, use structural equality
        let needsStructuralEquality = (op == .equal || op == .notEqual) && rank == 0
            && (isReferenceType(lhs, arena: arena, types: types) || isReferenceType(rhs, arena: arena, types: types))
        let callee: InternedString = switch op {
        case .add: interner.intern("kk_op_\(prefix)add")
        case .subtract: interner.intern("kk_op_\(prefix)sub")
        case .multiply: interner.intern("kk_op_\(prefix)mul")
        case .divide: interner.intern("kk_op_\(divModCmpPrefix)div")
        case .modulo: interner.intern("kk_op_\(divModCmpPrefix)\(divModOp)")
        case .equal: interner.intern(needsStructuralEquality ? "kk_structural_eq" : "kk_op_\(prefix)eq")
        case .notEqual: interner.intern(needsStructuralEquality ? "kk_structural_ne" : "kk_op_\(prefix)ne")
        case .lessThan: interner.intern("kk_op_\(divModCmpPrefix)lt")
        case .lessOrEqual: interner.intern("kk_op_\(divModCmpPrefix)le")
        case .greaterThan: interner.intern("kk_op_\(divModCmpPrefix)gt")
        case .greaterOrEqual: interner.intern("kk_op_\(divModCmpPrefix)ge")
        case .logicalAnd: interner.intern("kk_op_and")
        case .logicalOr: interner.intern("kk_op_or")
        }
        newBody.append(.call(symbol: nil, callee: callee, arguments: [effectiveLhs, effectiveRhs], result: result, canThrow: false, thrownResult: nil))
    }

    /// Returns true if the println call was lowered to a primitive-specific variant.
    private func tryLowerPrintlnCall(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        isSuperCall: Bool,
        arena: KIRArena,
        ctx: KIRContext,
        newBody: inout [KIRInstruction],
        precedingInstructions: [KIRInstruction],
        conversionCallees: PrintlnConversionCallees
    ) -> Bool {
        guard let types = ctx.sema?.types else { return false }
        var argType = arena.exprType(arguments[0])
        if argType == nil {
            argType = inferPrintlnArgTypeFromProducingInstruction(
                exprID: arguments[0],
                instructions: precedingInstructions,
                types: types,
                conversionCallees: conversionCallees
            )
        }
        guard let argType else { return false }

        // Range expressions (rangeTo, rangeUntil, downTo, step, reversed) produce
        // opaque runtime object handles typed as Long/Int in sema.  Do NOT lower
        // to kk_println_long — let them fall through to kk_println_any so the
        // runtime can resolve the RuntimeRangeBox and print "first..last".
        if isArgumentProducedByRangeCall(
            exprID: arguments[0],
            instructions: precedingInstructions,
            rangeCallees: conversionCallees.rangeCallees
        ) {
            return false
        }

        let primitiveCallee: String? = switch types.kind(of: argType) {
        case .primitive(.long, .nonNull): "kk_println_long"
        case .primitive(.ulong, .nonNull): "kk_println_ulong"
        case .primitive(.float, .nonNull): "kk_println_float"
        case .primitive(.double, .nonNull): "kk_println_double"
        case .primitive(.char, .nonNull): "kk_println_char"
        case .primitive(.boolean, .nonNull): "kk_println_bool"
        default: nil
        }
        if let name = primitiveCallee {
            appendPrimitivePrintlnCall(
                to: &newBody, symbol: symbol, callee: ctx.interner.intern(name),
                arguments: arguments, result: result, canThrow: canThrow,
                thrownResult: thrownResult, isSuperCall: isSuperCall
            )
            return true
        }
        if let dataObjectString = rewriteDataObjectPrintlnArgument(
            argument: arguments[0], arena: arena, sema: ctx.sema,
            interner: ctx.interner, body: &newBody
        ) {
            newBody.append(.call(
                symbol: symbol, callee: callee, arguments: [dataObjectString],
                result: result, canThrow: canThrow, thrownResult: thrownResult, isSuperCall: isSuperCall
            ))
            return true
        }
        if let dataClassString = rewriteDataClassPrintlnArgument(
            argument: arguments[0], arena: arena, sema: ctx.sema,
            interner: ctx.interner, body: &newBody
        ) {
            newBody.append(.call(
                symbol: symbol, callee: callee, arguments: [dataClassString],
                result: result, canThrow: canThrow, thrownResult: thrownResult, isSuperCall: isSuperCall
            ))
            return true
        }
        if let classToStringResult = rewriteClassToStringPrintlnArgument(
            argument: arguments[0], arena: arena, sema: ctx.sema,
            interner: ctx.interner, body: &newBody
        ) {
            newBody.append(.call(
                symbol: symbol, callee: callee, arguments: [classToStringResult],
                result: result, canThrow: canThrow, thrownResult: thrownResult, isSuperCall: isSuperCall
            ))
            return true
        }
        return false
    }

    /// Infers the semantic type of an expression from the instruction that produces it,
    /// used when arena.exprType is nil (e.g. for kk_int_to_float result passed to println).
    private func inferPrintlnArgTypeFromProducingInstruction(
        exprID: KIRExprID,
        instructions: [KIRInstruction],
        types: TypeSystem,
        conversionCallees: PrintlnConversionCallees
    ) -> TypeID? {
        for instruction in instructions.reversed() {
            switch instruction {
            case let .call(_, callee, _, result, _, _, _):
                if result == exprID {
                    if callee == conversionCallees.intToFloat || callee == conversionCallees.intToFloatBits {
                        return types.make(.primitive(.float, .nonNull))
                    }
                    if callee == conversionCallees.floatToDoubleBits || callee == conversionCallees.intToDoubleBits {
                        return types.make(.primitive(.double, .nonNull))
                    }
                    return nil
                }
            case let .copy(from, to):
                if to == exprID {
                    return inferPrintlnArgTypeFromProducingInstruction(
                        exprID: from,
                        instructions: instructions,
                        types: types,
                        conversionCallees: conversionCallees
                    )
                }
            case let .constValue(result: result, value: .floatLiteral):
                if result == exprID {
                    return types.make(.primitive(.float, .nonNull))
                }
            case let .constValue(result: result, value: .doubleLiteral):
                if result == exprID {
                    return types.make(.primitive(.double, .nonNull))
                }
            default:
                break
            }
        }
        return nil
    }

    /// Returns true when the expression is the result of a range-producing call
    /// (kk_op_rangeTo, kk_op_rangeUntil, kk_op_downTo, kk_op_step, kk_range_reversed).
    /// Follows .copy chains so that intermediate variable assignments are transparent.
    private func isArgumentProducedByRangeCall(
        exprID: KIRExprID,
        instructions: [KIRInstruction],
        rangeCallees: Set<InternedString>
    ) -> Bool {
        for instruction in instructions.reversed() {
            switch instruction {
            case let .call(_, callee, _, result, _, _, _):
                if result == exprID {
                    return rangeCallees.contains(callee)
                }
            case let .copy(from, to):
                if to == exprID {
                    return isArgumentProducedByRangeCall(
                        exprID: from,
                        instructions: instructions,
                        rangeCallees: rangeCallees
                    )
                }
            default:
                break
            }
        }
        return false
    }

    /// Returns true when the expression is a reference type that requires structural
    /// equality (e.g. List, Set, Map, String, Any, class instances).
    /// String is classified as a primitive in the type system but is represented as a
    /// heap-allocated RuntimeStringBox at runtime, so pointer comparison is insufficient.
    private func isReferenceType(_ exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> Bool {
        guard let types, let typeID = arena.exprType(exprID) else { return false }
        switch types.kind(of: typeID) {
        case .primitive(.string, _):
            return true
        case .primitive:
            return false
        case .classType, .any:
            return true
        default:
            return false
        }
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
        symbol _: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        isSuperCall: Bool
    ) {
        // Use symbol: nil so ABILoweringPass does not apply println's Any? signature
        // and box the argument. Primitive println variants expect raw bits (Int), not boxed values.
        body.append(
            .call(
                symbol: nil,
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

    /// Rewrites `println(dataObject)` to `println("ObjectName")` so that data
    /// object singletons print their name instead of the raw integer representation.
    private func rewriteDataObjectPrintlnArgument(
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
              classSymbol.kind == .object,
              classSymbol.flags.contains(.dataType)
        else {
            return nil
        }

        let stringType = sema.types.stringType
        let objectName = interner.intern(interner.resolve(classSymbol.name))
        let resultExpr = arena.appendExpr(.stringLiteral(objectName), type: stringType)
        body.append(.constValue(result: resultExpr, value: .stringLiteral(objectName)))
        return resultExpr
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

    /// Rewrites `println(classInstance)` for non-data class types that have a
    /// `toString()` method override.  Emits a direct call to the class's
    /// `toString()` implementation and returns the resulting string expression
    /// so the caller can pass it to `kk_println_any`.
    private func rewriteClassToStringPrintlnArgument(
        argument: KIRExprID,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner,
        body: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let sema,
              let argumentType = arena.exprType(argument)
        else {
            return nil
        }

        // Resolve the class symbol from the argument type.
        let classSymbolID: SymbolID
        switch sema.types.kind(of: argumentType) {
        case let .classType(classType):
            classSymbolID = classType.classSymbol
        default:
            return nil
        }

        guard let classSymbol = sema.symbols.symbol(classSymbolID),
              (classSymbol.kind == .class || classSymbol.kind == .object || classSymbol.kind == .enumClass)
        else {
            return nil
        }

        // Skip data classes/objects — they are handled by dedicated rewrites.
        if classSymbol.flags.contains(.dataType) {
            return nil
        }

        // Find the toString() method symbol for this class.
        let toStringName = interner.intern("toString")
        let toStringFQName = classSymbol.fqName + [toStringName]
        let toStringSymbol: SymbolID? = sema.symbols.lookupAll(fqName: toStringFQName).first(where: { id in
            guard let sym = sema.symbols.symbol(id),
                  sym.kind == .function else {
                return false
            }
            // Skip synthetic stubs (e.g., kotlin.text.StringBuilder.toString),
            // which are already lowered via normal member-call pathways.
            guard !sym.flags.contains(.synthetic) else {
                return false
            }
            let sig = sema.symbols.functionSignature(for: id)
            // toString() takes no value parameters.
            return sig?.parameterTypes.isEmpty ?? true
        })

        guard let toStringSym = toStringSymbol else {
            return nil
        }

        let stringType = sema.types.stringType
        let toStringResult = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: stringType
        )
        // Emit a direct call to the toString() method with the object as receiver.
        body.append(.call(
            symbol: toStringSym,
            callee: toStringName,
            arguments: [argument],
            result: toStringResult,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        ))
        return toStringResult
    }
}
