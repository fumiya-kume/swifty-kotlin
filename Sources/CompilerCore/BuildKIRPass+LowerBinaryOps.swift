import Foundation

extension BuildKIRPhase {
    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let lhsID = lowerExpr(
            lhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsID = lowerExpr(
            rhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        if let callBinding = sema.bindings.callBindings[exprID],
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
           signature.receiverType != nil {
            let normalizedResult = normalizedCallArguments(
                providedArguments: [rhsID],
                callBinding: callBinding,
                chosenCallee: callBinding.chosenCallee,
                spreadFlags: [false],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            var finalArguments = normalizedResult.arguments
            finalArguments.insert(lhsID, at: 0)
            if !signature.reifiedTypeParameterIndices.isEmpty {
                for index in signature.reifiedTypeParameterIndices.sorted() {
                    let concreteType = index < callBinding.substitutedTypeArguments.count
                        ? callBinding.substitutedTypeArguments[index]
                        : sema.types.anyType
                    let tokenExpr = arena.appendExpr(
                        .intLiteral(Int64(concreteType.rawValue)),
                        type: intType
                    )
                    instructions.append(.constValue(result: tokenExpr, value: .intLiteral(Int64(concreteType.rawValue))))
                    finalArguments.append(tokenExpr)
                }
            }
            if normalizedResult.defaultMask != 0 {
                let maskExpr = arena.appendExpr(.intLiteral(Int64(normalizedResult.defaultMask)), type: intType)
                instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(normalizedResult.defaultMask))))
                finalArguments.append(maskExpr)
                let stubName = interner.intern(
                    (sema.symbols.symbol(callBinding.chosenCallee).map { interner.resolve($0.name) } ?? "unknown") + "$default"
                )
                let stubSym = defaultStubSymbol(for: callBinding.chosenCallee)
                instructions.append(.call(
                    symbol: stubSym,
                    callee: stubName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let loweredCalleeName: InternedString
                if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                   !externalLinkName.isEmpty {
                    loweredCalleeName = interner.intern(externalLinkName)
                } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                    loweredCalleeName = symbol.name
                } else {
                    loweredCalleeName = binaryOperatorFunctionName(for: op, interner: interner)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return result
        }
        if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        if let runtimeCallee = builtinBinaryRuntimeCallee(for: op, interner: interner) {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        let kirOp: KIRBinaryOp
        switch op {
        case .add:
            kirOp = .add
        case .subtract:
            kirOp = .subtract
        case .multiply:
            kirOp = .multiply
        case .divide:
            kirOp = .divide
        case .modulo:
            kirOp = .modulo
        case .equal:
            kirOp = .equal
        case .notEqual:
            kirOp = .notEqual
        case .lessThan:
            kirOp = .lessThan
        case .lessOrEqual:
            kirOp = .lessOrEqual
        case .greaterThan:
            kirOp = .greaterThan
        case .greaterOrEqual:
            kirOp = .greaterOrEqual
        case .logicalAnd:
            kirOp = .logicalAnd
        case .logicalOr:
            kirOp = .logicalOr
        case .elvis:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_elvis"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeTo:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeTo"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeUntil:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_rangeUntil"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
        return result
    }
}
