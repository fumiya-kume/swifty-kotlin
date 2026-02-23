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
        lines.append("  kk_register_frame_map(\(functionID)u, &\(frameMapDescriptorSymbol(for: function)));")
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

        for instruction in function.body {
            switch instruction {
            case .nop:
                lines.append("  /* nop */")

            case .beginBlock, .endBlock:
                continue

            case .label(let id):
                lines.append("\(labelName(id)):")

            case .jump(let target):
                lines.append("  goto \(labelName(target));")

            case .jumpIfEqual(let lhs, let rhs, let target):
                ensureDeclared(lhs, declared: &declared, lines: &lines)
                ensureDeclared(rhs, declared: &declared, lines: &lines)
                lines.append("  if (\(varName(lhs)) == \(varName(rhs))) goto \(labelName(target));")

            case .constValue(let result, let value):
                ensureDeclared(result, declared: &declared, lines: &lines)
                if case .symbolRef(let symbol) = value,
                   let parameterName = parameterNameBySymbol[symbol] {
                    lines.append("  \(varName(result)) = \(parameterName);")
                } else {
                    lines.append(
                        "  \(varName(result)) = \(valueExpr(value, interner: interner, functionSymbols: functionSymbols, globalValueSymbols: globalValueSymbols));"
                    )
                }
                syncRoot(result)

            case .binary(let op, let lhs, let rhs, let result):
                ensureDeclared(result, declared: &declared, lines: &lines)
                ensureDeclared(lhs, declared: &declared, lines: &lines)
                ensureDeclared(rhs, declared: &declared, lines: &lines)
                let opText: String
                switch op {
                case .add:
                    opText = "+"
                case .subtract:
                    opText = "-"
                case .multiply:
                    opText = "*"
                case .divide:
                    opText = "/"
                case .modulo:
                    opText = "%"
                case .equal:
                    opText = "=="
                case .notEqual:
                    opText = "!="
                case .lessThan:
                    opText = "<"
                case .lessOrEqual:
                    opText = "<="
                case .greaterThan:
                    opText = ">"
                case .greaterOrEqual:
                    opText = ">="
                case .logicalAnd:
                    opText = "&&"
                case .logicalOr:
                    opText = "||"
                }
                lines.append("  \(varName(result)) = (\(varName(lhs)) \(opText) \(varName(rhs)));")
                syncRoot(result)

            case .unary(let op, let operand, let result):
                ensureDeclared(result, declared: &declared, lines: &lines)
                ensureDeclared(operand, declared: &declared, lines: &lines)
                let unaryOpText: String
                switch op {
                case .not:
                    unaryOpText = "!"
                case .unaryPlus:
                    unaryOpText = "+"
                case .unaryMinus:
                    unaryOpText = "-"
                }
                lines.append("  \(varName(result)) = (\(unaryOpText)\(varName(operand)));")
                syncRoot(result)

            case .nullAssert(let operand, let result):
                ensureDeclared(result, declared: &declared, lines: &lines)
                ensureDeclared(operand, declared: &declared, lines: &lines)
                lines.append("  \(varName(result)) = \(varName(operand));")
                syncRoot(result)

            case .call(let symbol, let callee, let arguments, let result, let usesThrownChannel, let thrownResult):
                let calleeName = interner.resolve(callee)
                let argVars = arguments.map { arg -> String in
                    ensureDeclared(arg, declared: &declared, lines: &lines)
                    return varName(arg)
                }

                if let result {
                    ensureDeclared(result, declared: &declared, lines: &lines)
                }
                if let thrownResult {
                    ensureDeclared(thrownResult, declared: &declared, lines: &lines)
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

                if LLVMBackend.floatBuiltinOps.contains(calleeName) {
                    let lhs = argVars.count > 0 ? argVars[0] : "0"
                    let rhs = argVars.count > 1 ? argVars[1] : "0"
                    let cOp = Self.fpOpSymbol(calleeName)
                    let isComparison = calleeName.hasSuffix("eq") || calleeName.hasSuffix("ne") || calleeName.hasSuffix("lt") || calleeName.hasSuffix("le") || calleeName.hasSuffix("gt") || calleeName.hasSuffix("ge")
                    let expr: String
                    if calleeName == "kk_op_fmod" {
                        expr = "kk_float_to_bits(fmodf(kk_bits_to_float(\(lhs)), kk_bits_to_float(\(rhs))))"
                    } else if isComparison {
                        expr = "(intptr_t)(kk_bits_to_float(\(lhs)) \(cOp) kk_bits_to_float(\(rhs)))"
                    } else {
                        expr = "kk_float_to_bits(kk_bits_to_float(\(lhs)) \(cOp) kk_bits_to_float(\(rhs)))"
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
                    let isComparison = calleeName.hasSuffix("eq") || calleeName.hasSuffix("ne") || calleeName.hasSuffix("lt") || calleeName.hasSuffix("le") || calleeName.hasSuffix("gt") || calleeName.hasSuffix("ge")
                    let expr: String
                    if calleeName == "kk_op_dmod" {
                        expr = "kk_double_to_bits(fmod(kk_bits_to_double(\(lhs)), kk_bits_to_double(\(rhs))))"
                    } else if isComparison {
                        expr = "(intptr_t)(kk_bits_to_double(\(lhs)) \(cOp) kk_bits_to_double(\(rhs)))"
                    } else {
                        expr = "kk_double_to_bits(kk_bits_to_double(\(lhs)) \(cOp) kk_bits_to_double(\(rhs)))"
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
                var thrownSlotName: String? = nil
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

            case .jumpIfNotNull(let value, let target):
                ensureDeclared(value, declared: &declared, lines: &lines)
                lines.append("  if (\(varName(value)) != 0) goto \(labelName(target));")

            case .copy(let from, let to):
                ensureDeclared(from, declared: &declared, lines: &lines)
                ensureDeclared(to, declared: &declared, lines: &lines)
                lines.append("  \(varName(to)) = \(varName(from));")

            case .rethrow(let value):
                ensureDeclared(value, declared: &declared, lines: &lines)
                lines.append("  if (outThrown) { *outThrown = \(varName(value)); }")
                lines.append("  kk_pop_frame();")
                lines.append("  return 0;")

            case .returnIfEqual(let lhs, let rhs):
                ensureDeclared(lhs, declared: &declared, lines: &lines)
                ensureDeclared(rhs, declared: &declared, lines: &lines)
                lines.append("  if (\(varName(lhs)) == \(varName(rhs))) {")
                lines.append("    kk_pop_frame();")
                lines.append("    return \(varName(lhs));")
                lines.append("  }")

            case .returnUnit:
                lines.append("  kk_pop_frame();")
                lines.append("  return 0;")

            case .returnValue(let value):
                ensureDeclared(value, declared: &declared, lines: &lines)
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
