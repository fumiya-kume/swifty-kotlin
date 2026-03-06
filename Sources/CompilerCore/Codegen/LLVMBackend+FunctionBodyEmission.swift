import Foundation

extension LLVMBackend {
    func emitFunctionBody(
        function: KIRFunction,
        frameMapPlan: FrameMapPlan,
        interner: StringInterner,
        arena: KIRArena,
        functionSymbols: [SymbolID: String],
        globalValueSymbols: [SymbolID: String]
    ) -> [String] {
        var lines: [String] = []
        var declared: Set<Int32> = []
        var callIndex = 0
        let functionID = max(0, Int(function.symbol.rawValue))
        var parameterNameBySymbol: [SymbolID: String] = [:]
        for (index, parameter) in function.params.enumerated() {
            parameterNameBySymbol[parameter.symbol] = "p\(index)"
        }

        if frameMapPlan.rootCount > 0 {
            lines.append("  intptr_t kk_gc_roots[\(frameMapPlan.rootCount)];")
            lines.append("  memset(kk_gc_roots, 0, sizeof(kk_gc_roots));")
            for (index, parameter) in function.params.enumerated() {
                guard let slot = frameMapPlan.parameterSlotBySymbol[parameter.symbol] else {
                    continue
                }
                lines.append("  kk_gc_roots[\(slot)] = p\(index);")
            }
        }
        if frameMapPlan.rootCount > 0 {
            lines.append("  kk_push_frame(\(functionID)u, kk_gc_roots);")
        } else {
            lines.append("  kk_push_frame(\(functionID)u, NULL);")
        }
        lines.append("  if (outThrown) { *outThrown = 0; }")

        func syncRoot(_ id: KIRExprID) {
            guard let slot = frameMapPlan.exprSlotByID[id.rawValue] else {
                return
            }
            lines.append("  kk_gc_roots[\(slot)] = \(varName(id));")
        }

        func ensureDeclaredResolved(_ id: KIRExprID) {
            guard declared.insert(id.rawValue).inserted else {
                return
            }

            if let expression = arena.expr(id) {
                if case let .symbolRef(symbol) = expression,
                   let parameterName = parameterNameBySymbol[symbol]
                {
                    lines.append("  intptr_t \(varName(id)) = \(parameterName);")
                } else {
                    lines.append(
                        "  intptr_t \(varName(id)) = \(valueExpr(expression, interner: interner, functionSymbols: functionSymbols, globalValueSymbols: globalValueSymbols));"
                    )
                }
            } else {
                lines.append("  intptr_t \(varName(id)) = 0;")
            }
            syncRoot(id)
        }

        for instruction in function.body {
            switch instruction {
            case .nop:
                lines.append("  /* nop */")

            case .beginBlock, .endBlock:
                continue

            case let .label(id):
                lines.append("\(labelName(id)):")

            case let .jump(target):
                lines.append("  goto \(labelName(target));")

            case let .jumpIfEqual(lhs, rhs, target):
                ensureDeclaredResolved(lhs)
                ensureDeclaredResolved(rhs)
                lines.append("  if (\(varName(lhs)) == \(varName(rhs))) goto \(labelName(target));")

            case let .constValue(result, value):
                ensureDeclaredResolved(result)
                if case let .symbolRef(symbol) = value,
                   let parameterName = parameterNameBySymbol[symbol]
                {
                    lines.append("  \(varName(result)) = \(parameterName);")
                } else {
                    lines.append(
                        "  \(varName(result)) = \(valueExpr(value, interner: interner, functionSymbols: functionSymbols, globalValueSymbols: globalValueSymbols));"
                    )
                }
                syncRoot(result)

            case let .binary(op, lhs, rhs, result):
                ensureDeclaredResolved(result)
                ensureDeclaredResolved(lhs)
                ensureDeclaredResolved(rhs)
                let opText = switch op {
                case .add:
                    "+"
                case .subtract:
                    "-"
                case .multiply:
                    "*"
                case .divide:
                    "/"
                case .modulo:
                    "%"
                case .equal:
                    "=="
                case .notEqual:
                    "!="
                case .lessThan:
                    "<"
                case .lessOrEqual:
                    "<="
                case .greaterThan:
                    ">"
                case .greaterOrEqual:
                    ">="
                case .logicalAnd:
                    "&&"
                case .logicalOr:
                    "||"
                }
                lines.append("  \(varName(result)) = (\(varName(lhs)) \(opText) \(varName(rhs)));")
                syncRoot(result)

            case let .unary(op, operand, result):
                ensureDeclaredResolved(result)
                ensureDeclaredResolved(operand)
                let unaryOpText = switch op {
                case .not:
                    "!"
                case .unaryPlus:
                    "+"
                case .unaryMinus:
                    "-"
                }
                lines.append("  \(varName(result)) = (\(unaryOpText)\(varName(operand)));")
                syncRoot(result)

            case let .nullAssert(operand, result):
                ensureDeclaredResolved(result)
                ensureDeclaredResolved(operand)
                let thrSlot = "thrown_\(callIndex)"
                callIndex += 1
                lines.append("  intptr_t \(thrSlot) = 0;")
                lines.append("  \(varName(result)) = kk_op_notnull(\(varName(operand)), &\(thrSlot));")
                lines.append("  if (\(thrSlot) != 0) {")
                lines.append("    if (outThrown) { *outThrown = \(thrSlot); }")
                lines.append("    kk_pop_frame();")
                lines.append("    return 0;")
                lines.append("  }")
                syncRoot(result)

            case let .call(symbol, callee, arguments, result, usesThrownChannel, thrownResult, isSuperCall):
                // super calls always use direct dispatch – when virtual dispatch
                // is introduced the isSuperCall flag will bypass vtable lookup.
                _ = isSuperCall
                let calleeName = interner.resolve(callee)
                let argVars = arguments.map { arg -> String in
                    ensureDeclaredResolved(arg)
                    return varName(arg)
                }

                if let result {
                    ensureDeclaredResolved(result)
                }
                if let thrownResult {
                    ensureDeclaredResolved(thrownResult)
                }

                if calleeName == "println" || calleeName == "kk_println_any" {
                    let value = argVars.first ?? "0"
                    lines.append("  kk_println_any((void*)\(value));")
                    if let result {
                        lines.append("  \(varName(result)) = 0;")
                        syncRoot(result)
                    }
                    continue
                }

                if calleeName == "kk_println_float" || calleeName == "kk_println_double" || calleeName == "kk_println_char" {
                    let value = argVars.first ?? "0"
                    lines.append("  \(calleeName)(\(value));")
                    if let result {
                        lines.append("  \(varName(result)) = 0;")
                        syncRoot(result)
                    }
                    continue
                }

                // Unsigned int ops: cast to uintptr_t for correct semantics
                if LLVMBackend.unsignedBuiltinOps.contains(calleeName),
                   let cOp = LLVMBackend.builtinOps[calleeName]
                {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(intptr_t)((uintptr_t)\(lhs) \(cOp) (uintptr_t)\(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if let cOp = LLVMBackend.builtinOps[calleeName] {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(\(lhs) \(cOp) \(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                // Unsigned shift right: (intptr_t)((uintptr_t)a >> b) (P5-103)
                if calleeName == "kk_op_ushr" {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(intptr_t)((uintptr_t)\(lhs) >> \(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                // Unary builtin ops (e.g. bitwise NOT) (P5-103)
                if let cOp = LLVMBackend.unaryBuiltinOps[calleeName] {
                    let operand = argVars.count > 0 ? argVars[0] : "0"
                    let expr = "(\(cOp)\(operand))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if LLVMBackend.floatBuiltinOps.contains(calleeName) {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let cOp = Self.fpOpSymbol(calleeName)
                    let isComparison = calleeName.hasSuffix("eq")
                        || calleeName.hasSuffix("ne") || calleeName.hasSuffix("lt")
                        || calleeName.hasSuffix("le") || calleeName.hasSuffix("gt")
                        || calleeName.hasSuffix("ge")
                    let expr = if calleeName == "kk_op_fmod" {
                        "kk_float_to_bits(fmodf(kk_bits_to_float(\(lhs)), kk_bits_to_float(\(rhs))))"
                    } else if isComparison {
                        "(intptr_t)(kk_bits_to_float(\(lhs)) \(cOp) kk_bits_to_float(\(rhs)))"
                    } else {
                        "kk_float_to_bits(kk_bits_to_float(\(lhs)) \(cOp) kk_bits_to_float(\(rhs)))"
                    }
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if LLVMBackend.doubleBuiltinOps.contains(calleeName) {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let cOp = Self.fpOpSymbol(calleeName)
                    let isComparison = calleeName.hasSuffix("eq")
                        || calleeName.hasSuffix("ne") || calleeName.hasSuffix("lt")
                        || calleeName.hasSuffix("le") || calleeName.hasSuffix("gt")
                        || calleeName.hasSuffix("ge")
                    let expr = if calleeName == "kk_op_dmod" {
                        "kk_double_to_bits(fmod(kk_bits_to_double(\(lhs)), kk_bits_to_double(\(rhs))))"
                    } else if isComparison {
                        "(intptr_t)(kk_bits_to_double(\(lhs)) \(cOp) kk_bits_to_double(\(rhs)))"
                    } else {
                        "kk_double_to_bits(kk_bits_to_double(\(lhs)) \(cOp) kk_bits_to_double(\(rhs)))"
                    }
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_any_to_string" {
                    let arg = argVars.count > 0 ? argVars[0] : "0"
                    let tagArg = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(intptr_t)kk_any_to_string(\(arg), \(tagArg))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_string_concat" {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "(intptr_t)kk_string_concat((void*)\(lhs), (void*)\(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_string_compareTo" {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let expr = "kk_string_compareTo((void*)\(lhs), (void*)\(rhs))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_string_trim" {
                    let value = argVars.count > 0 ? argVars[0] : "0"
                    let expr = "(intptr_t)kk_string_trim(\(value))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_abort_unreachable" {
                    let expr = "kk_abort_unreachable(NULL)"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_string_replace" {
                    let value = argVars.count > 0 ? argVars[0] : "0"
                    let oldValue = argVars.count > 1 ? argVars[1] : "0"
                    let newValue = argVars.count > 2 ? argVars[2] : "0"
                    let expr = "(intptr_t)kk_string_replace(\(value), \(oldValue), \(newValue))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                if calleeName == "kk_int_toString_radix" {
                    let value = argVars.count > 0 ? argVars[0] : "0"
                    let radix = argVars.count > 1 ? argVars[1] : "10"
                    let expr = "(intptr_t)kk_int_toString_radix(\(value), \(radix))"
                    if let result {
                        lines.append("  \(varName(result)) = \(expr);")
                        syncRoot(result)
                    } else {
                        lines.append("  (void)\(expr);")
                    }
                    continue
                }

                let target: String
                let isInternalFunction: Bool
                if let symbol, let resolved = functionSymbols[symbol] {
                    target = resolved
                    isInternalFunction = true
                } else {
                    target = calleeName.isEmpty ? "0" : calleeName
                    isInternalFunction = false
                }
                var callArguments = argVars
                var thrownSlotName: String?
                if usesThrownChannel {
                    let slot = "thrown_\(callIndex)"
                    callIndex += 1
                    lines.append("  intptr_t \(slot) = 0;")
                    thrownSlotName = slot
                    callArguments.append("&\(slot)")
                } else if isInternalFunction {
                    callArguments.append("NULL")
                }

                let callExpr = "\(target)(\(callArguments.joined(separator: ", ")))"
                if let result {
                    lines.append("  \(varName(result)) = \(callExpr);")
                    syncRoot(result)
                } else {
                    lines.append("  (void)\(callExpr);")
                }
                if calleeName == "kk_coroutine_continuation_new", let result {
                    lines.append("  kk_register_coroutine_root((void*)(uintptr_t)\(varName(result)));")
                }
                if calleeName == "kk_coroutine_state_exit", let continuation = argVars.first {
                    lines.append("  kk_unregister_coroutine_root((void*)(uintptr_t)\(continuation));")
                }
                if let thrownSlotName {
                    if let thrownResult {
                        lines.append("  \(varName(thrownResult)) = \(thrownSlotName);")
                    } else {
                        lines.append("  if (\(thrownSlotName) != 0) {")
                        lines.append("    if (outThrown) { *outThrown = \(thrownSlotName); }")
                        lines.append("    kk_pop_frame();")
                        lines.append("    return 0;")
                        lines.append("  }")
                    }
                }

            case let .virtualCall(symbol, callee, receiver, arguments, result, usesThrownChannel, thrownResult, dispatch):
                let calleeName = interner.resolve(callee)
                ensureDeclaredResolved(receiver)
                let argVars = arguments.map { arg -> String in
                    ensureDeclaredResolved(arg)
                    return varName(arg)
                }

                if let result {
                    ensureDeclaredResolved(result)
                }
                if let thrownResult {
                    ensureDeclaredResolved(thrownResult)
                }

                let lookupExpr = switch dispatch {
                case let .vtable(slot):
                    "kk_vtable_lookup(\(varName(receiver)), \(slot))"
                case let .itable(interfaceSlot, methodSlot):
                    "kk_itable_lookup(\(varName(receiver)), \(interfaceSlot), \(methodSlot))"
                }

                let target: String
                let isInternalFunction: Bool
                if let symbol, let resolved = functionSymbols[symbol] {
                    target = resolved
                    isInternalFunction = true
                } else {
                    target = calleeName.isEmpty ? "0" : calleeName
                    isInternalFunction = false
                }

                let fptr = "vfn_\(callIndex)"
                lines.append("  KKVTableEntry \(fptr) = \(lookupExpr);")

                var callArguments = [varName(receiver)] + argVars
                var thrownSlotName: String?
                if usesThrownChannel {
                    let thrSlot = "thrown_\(callIndex)"
                    callIndex += 1
                    lines.append("  intptr_t \(thrSlot) = 0;")
                    thrownSlotName = thrSlot
                    callArguments.append("&\(thrSlot)")
                } else if isInternalFunction {
                    callArguments.append("NULL")
                    callIndex += 1
                } else {
                    callIndex += 1
                }

                let argsJoined = callArguments.joined(separator: ", ")
                let directCallExpr = "\(target)(\(argsJoined))"
                let virtualCallExpr = "((intptr_t(*)())\(fptr))(\(argsJoined))"
                if let result {
                    lines.append("  \(varName(result)) = (\(fptr) ? \(virtualCallExpr) : \(directCallExpr));")
                    syncRoot(result)
                } else {
                    lines.append("  if (\(fptr)) { (void)\(virtualCallExpr); } else { (void)\(directCallExpr); }")
                }
                if let thrownSlotName {
                    if let thrownResult {
                        lines.append("  \(varName(thrownResult)) = \(thrownSlotName);")
                    } else {
                        lines.append("  if (\(thrownSlotName) != 0) {")
                        lines.append("    if (outThrown) { *outThrown = \(thrownSlotName); }")
                        lines.append("    kk_pop_frame();")
                        lines.append("    return 0;")
                        lines.append("  }")
                    }
                }

            case let .jumpIfNotNull(value, target):
                ensureDeclaredResolved(value)
                lines.append("  if (\(varName(value)) != 0) goto \(labelName(target));")

            case let .copy(from, to):
                ensureDeclaredResolved(from)
                // If the copy target is a global symbolRef, write to the global slot
                // instead of the local register so the store persists.
                if let targetExpr = arena.expr(to),
                   case let .symbolRef(targetSymbol) = targetExpr,
                   let globalSlot = globalValueSymbols[targetSymbol]
                {
                    lines.append("  \(globalSlot) = \(varName(from));")
                } else {
                    ensureDeclaredResolved(to)
                    lines.append("  \(varName(to)) = \(varName(from));")
                }

            case let .storeGlobal(value, symbol):
                ensureDeclaredResolved(value)
                if let globalName = globalValueSymbols[symbol] {
                    lines.append("  \(globalName) = \(varName(value));")
                }

            case let .loadGlobal(result, symbol):
                ensureDeclaredResolved(result)
                if let globalName = globalValueSymbols[symbol] {
                    lines.append("  \(varName(result)) = \(globalName);")
                }
                syncRoot(result)

            case let .rethrow(value):
                ensureDeclaredResolved(value)
                lines.append("  if (outThrown) { *outThrown = \(varName(value)); }")
                lines.append("  kk_pop_frame();")
                lines.append("  return 0;")

            case let .returnIfEqual(lhs, rhs):
                ensureDeclaredResolved(lhs)
                ensureDeclaredResolved(rhs)
                lines.append("  if (\(varName(lhs)) == \(varName(rhs))) {")
                lines.append("    kk_pop_frame();")
                lines.append("    return \(varName(lhs));")
                lines.append("  }")

            case .returnUnit:
                lines.append("  kk_pop_frame();")
                lines.append("  return 0;")

            case let .returnValue(value):
                ensureDeclaredResolved(value)
                lines.append("  kk_pop_frame();")
                lines.append("  return \(varName(value));")
            }
        }

        if lines.last?.hasPrefix("  return ") != true {
            lines.append("  kk_pop_frame();")
            lines.append("  return 0;")
        }
        return lines
    }
}
