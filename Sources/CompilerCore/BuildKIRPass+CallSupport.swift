import Foundation

extension BuildKIRPhase {
    func collectFunctionDefaultArgumentExpressions(
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID: [ExprID?]] {
        var mapping: [SymbolID: [ExprID?]] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                collectFunctionDefaults(declID, ast: ast, sema: sema, mapping: &mapping)
            }
        }
        return mapping
    }

    func collectFunctionDefaults(
        _ declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        mapping: inout [SymbolID: [ExprID?]]
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case .funDecl(let function):
            guard let symbol = sema.bindings.declSymbols[declID] else { return }
            let defaults = function.valueParams.map(\.defaultValue)
            if defaults.contains(where: { $0 != nil }) {
                mapping[symbol] = defaults
            }
        case .classDecl(let classDecl):
            for memberDeclID in classDecl.memberFunctions {
                collectFunctionDefaults(memberDeclID, ast: ast, sema: sema, mapping: &mapping)
            }
            for nestedDeclID in classDecl.nestedClasses + classDecl.nestedObjects {
                collectFunctionDefaults(nestedDeclID, ast: ast, sema: sema, mapping: &mapping)
            }
        case .objectDecl(let objectDecl):
            for memberDeclID in objectDecl.memberFunctions {
                collectFunctionDefaults(memberDeclID, ast: ast, sema: sema, mapping: &mapping)
            }
            for nestedDeclID in objectDecl.nestedClasses + objectDecl.nestedObjects {
                collectFunctionDefaults(nestedDeclID, ast: ast, sema: sema, mapping: &mapping)
            }
        default:
            break
        }
    }

    func normalizedCallArguments(
        providedArguments: [KIRExprID],
        callBinding: CallBinding?,
        chosenCallee: SymbolID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let callBinding,
              let chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosenCallee) else {
            return providedArguments
        }

        let parameterCount = signature.parameterTypes.count
        guard parameterCount > 0 else {
            return providedArguments
        }

        var argIndicesByParameter: [Int: [Int]] = [:]
        for (argIndex, paramIndex) in callBinding.parameterMapping {
            guard argIndex >= 0, argIndex < providedArguments.count else {
                continue
            }
            argIndicesByParameter[paramIndex, default: []].append(argIndex)
        }
        for key in Array(argIndicesByParameter.keys) {
            argIndicesByParameter[key]?.sort()
        }

        let hasOutOfRangeMapping = argIndicesByParameter.keys.contains(where: { $0 < 0 || $0 >= parameterCount })
        let hasMergedParameterMapping = argIndicesByParameter.values.contains(where: { $0.count > 1 })
        if hasOutOfRangeMapping || hasMergedParameterMapping {
            return providedArguments
        }

        let defaultExpressions = functionDefaultArgumentsBySymbol[chosenCallee] ?? []
        var normalized: [KIRExprID] = []
        normalized.reserveCapacity(parameterCount)

        for paramIndex in 0..<parameterCount {
            if let argIndex = argIndicesByParameter[paramIndex]?.first {
                normalized.append(providedArguments[argIndex])
                continue
            }
            guard paramIndex < defaultExpressions.count,
                  let defaultExprID = defaultExpressions[paramIndex] else {
                return providedArguments
            }
            let loweredDefault = lowerExpr(
                defaultExprID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            normalized.append(loweredDefault)
        }
        return normalized
    }

    func syntheticReceiverParameterSymbol(functionSymbol: SymbolID) -> SymbolID {
        SymbolID(rawValue: -10_000 - functionSymbol.rawValue)
    }

    func loweredRuntimeBuiltinCallee(
        for callee: InternedString,
        argumentCount: Int,
        interner: StringInterner
    ) -> InternedString? {
        switch interner.resolve(callee) {
        case "IntArray":
            guard argumentCount == 1 else {
                return nil
            }
            return interner.intern("kk_array_new")
        default:
            return nil
        }
    }

    func builtinBinaryRuntimeCallee(for op: BinaryOp, interner: StringInterner) -> InternedString? {
        switch op {
        case .notEqual:
            return interner.intern("kk_op_ne")
        case .lessThan:
            return interner.intern("kk_op_lt")
        case .lessOrEqual:
            return interner.intern("kk_op_le")
        case .greaterThan:
            return interner.intern("kk_op_gt")
        case .greaterOrEqual:
            return interner.intern("kk_op_ge")
        case .logicalAnd:
            return interner.intern("kk_op_and")
        case .logicalOr:
            return interner.intern("kk_op_or")
        default:
            return nil
        }
    }

    func binaryOperatorFunctionName(for op: BinaryOp, interner: StringInterner) -> InternedString {
        switch op {
        case .add:
            return interner.intern("plus")
        case .subtract:
            return interner.intern("minus")
        case .multiply:
            return interner.intern("times")
        case .divide:
            return interner.intern("div")
        case .modulo:
            return interner.intern("rem")
        case .equal:
            return interner.intern("equals")
        case .notEqual:
            return interner.intern("equals")
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            return interner.intern("compareTo")
        case .logicalAnd:
            return interner.intern("and")
        case .logicalOr:
            return interner.intern("or")
        case .elvis:
            return interner.intern("elvis")
        case .rangeTo:
            return interner.intern("rangeTo")
        }
    }

    func makeLoopLabel() -> Int32 {
        let label = nextLoopLabel
        nextLoopLabel += 1
        return label
    }
}
