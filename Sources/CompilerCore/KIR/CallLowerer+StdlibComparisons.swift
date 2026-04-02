import Foundation

extension CallLowerer {
    func lowerComparisonSpecialCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let callBinding = sema.bindings.callBindings[exprID]
        guard let chosenCallee = callBinding?.chosenCallee,
              chosenCallee != .invalid,
              let chosenSymbol = sema.symbols.symbol(chosenCallee)
        else {
            return nil
        }

        let isStdlibMaxOfCall = chosenSymbol.fqName.count >= 3
            && chosenSymbol.fqName[0] == interner.intern("kotlin")
            && chosenSymbol.fqName[1] == interner.intern("comparisons")
            && interner.resolve(chosenSymbol.name) == "maxOf"

        guard let specialKind = sema.bindings.stdlibSpecialCallKind(for: exprID) else {
            if isStdlibMaxOfCall {
                return lowerRemainingMaxOfCallExpr(
                    exprID,
                    args: args,
                    callBinding: callBinding,
                    chosenCallee: chosenCallee,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            return nil
        }

        let comparisonOp: KIRBinaryOp
        switch specialKind {
        case .maxOfInt, .maxOfLong, .maxOfDouble, .maxOfFloat:
            guard args.count == 2 else { return nil }
            comparisonOp = .greaterThan
        case .minOfInt, .minOfLong, .minOfDouble, .minOfFloat:
            guard args.count == 2 else { return nil }
            comparisonOp = .lessThan
        case .maxOfInt3, .maxOfLong3, .maxOfDouble3, .maxOfFloat3:
            guard args.count == 3 else { return nil }
            comparisonOp = .greaterThan
        case .minOfInt3, .minOfLong3, .minOfDouble3, .minOfFloat3:
            guard args.count == 3 else { return nil }
            comparisonOp = .lessThan
        default:
            return nil
        }

        let boolType = sema.types.booleanType
        let resultType = sema.bindings.exprType(for: exprID)
            ?? sema.bindings.exprType(for: args[0].expr)
            ?? sema.types.intType

        if args.count == 2 {
            return lowerTwoArgComparison(
                args: args,
                comparisonOp: comparisonOp,
                boolType: boolType,
                resultType: resultType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            return lowerThreeArgComparison(
                args: args,
                comparisonOp: comparisonOp,
                boolType: boolType,
                resultType: resultType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
    }

    private func lowerRemainingMaxOfCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        callBinding: CallBinding?,
        chosenCallee: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let signature = sema.symbols.functionSignature(for: chosenCallee),
              !args.isEmpty
        else {
            return nil
        }

        let resultType = sema.bindings.exprType(for: exprID)
            ?? sema.bindings.exprType(for: args[0].expr)
            ?? sema.types.anyType
        let boolType = sema.types.booleanType
        let intType = sema.types.intType

        let isGenericComparableMaxOf = signature.typeParameterUpperBoundsList.contains(where: { upperBounds in
            upperBounds.contains(where: { bound in
                isComparableUpperBound(bound, sema: sema)
            })
        })
        let isComparatorMaxOf = !isGenericComparableMaxOf
            && signature.parameterTypes.contains(where: { paramType in
                isComparatorType(paramType, sema: sema, interner: interner)
            })
        let isUnsignedMaxOf = !isGenericComparableMaxOf
            && !isComparatorMaxOf
            && signature.typeParameterSymbols.isEmpty
            && signature.parameterTypes.allSatisfy({ isUnsignedType($0, sema: sema) })

        guard isGenericComparableMaxOf || isComparatorMaxOf || isUnsignedMaxOf else {
            return nil
        }

        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        var comparisonArgIndices = Array(args.indices)
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        func selectGreater(lhs: KIRExprID, rhs: KIRExprID, conditionExpr: KIRExprID) -> KIRExprID {
            let useRightLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let resultExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

            instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: useRightLabel))
            instructions.append(.copy(from: lhs, to: resultExpr))
            instructions.append(.jump(endLabel))
            instructions.append(.label(useRightLabel))
            instructions.append(.copy(from: rhs, to: resultExpr))
            instructions.append(.label(endLabel))
            return resultExpr
        }

        enum ComparisonStrategy {
            case unsigned
            case genericComparable
            case comparator(comparatorArgIndex: Int, trampolineCallee: InternedString)
        }

        let comparisonStrategy: ComparisonStrategy
        if isUnsignedMaxOf {
            comparisonStrategy = .unsigned
        } else if isGenericComparableMaxOf {
            comparisonStrategy = .genericComparable
        } else {
            guard let callBinding else {
                return nil
            }
            guard let comparatorParamIndex = signature.parameterTypes.indices.last else {
                return nil
            }
            let comparatorArgIndex = callBinding.parameterMapping.first(where: { $0.value == comparatorParamIndex })?.key
                ?? (args.count - 1)
            guard comparatorArgIndex >= 0, comparatorArgIndex < loweredArgIDs.count else {
                return nil
            }
            guard let trampolineName = comparatorTrampolineName(
                comparatorExprID: args[comparatorArgIndex].expr,
                loweredComparatorID: loweredArgIDs[comparatorArgIndex],
                sema: sema,
                interner: interner,
                instructions: instructions
            ) else {
                return nil
            }
            let trampolineCallee = interner.intern(trampolineName)
            comparisonArgIndices = args.indices.filter { $0 != comparatorArgIndex }
            comparisonStrategy = .comparator(
                comparatorArgIndex: comparatorArgIndex,
                trampolineCallee: trampolineCallee
            )
        }

        guard !comparisonArgIndices.isEmpty else {
            return nil
        }

        var currentExpr = loweredArgIDs[comparisonArgIndices[0]]
        guard comparisonArgIndices.count > 1 else {
            return currentExpr
        }

        for argIndex in comparisonArgIndices.dropFirst() {
            let candidateExpr = loweredArgIDs[argIndex]
            let conditionExpr: KIRExprID
            switch comparisonStrategy {
            case .unsigned:
                conditionExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boolType
                )
                instructions.append(.binary(op: .greaterThan, lhs: candidateExpr, rhs: currentExpr, result: conditionExpr))
            case .genericComparable:
                let compareResultExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: intType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_compare_any"),
                    arguments: [candidateExpr, currentExpr],
                    result: compareResultExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                conditionExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boolType
                )
                instructions.append(.binary(
                    op: .greaterThan,
                    lhs: compareResultExpr,
                    rhs: zeroExpr,
                    result: conditionExpr
                ))
            case let .comparator(comparatorArgIndex, trampolineCallee):
                let compareResultExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: intType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: trampolineCallee,
                    arguments: [loweredArgIDs[comparatorArgIndex], candidateExpr, currentExpr],
                    result: compareResultExpr,
                    canThrow: true,
                    thrownResult: nil
                ))
                conditionExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boolType
                )
                instructions.append(.binary(
                    op: .greaterThan,
                    lhs: compareResultExpr,
                    rhs: zeroExpr,
                    result: conditionExpr
                ))
            }
            currentExpr = selectGreater(lhs: candidateExpr, rhs: currentExpr, conditionExpr: conditionExpr)
        }
        return currentExpr
    }

    private func isComparableUpperBound(
        _ type: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard let comparableSymbol = sema.types.comparableInterfaceSymbol else {
            return false
        }
        switch sema.types.kind(of: type) {
        case let .classType(classType):
            return classType.classSymbol == comparableSymbol
        default:
            return false
        }
    }

    private func isComparatorType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "Comparator"
    }

    private func isUnsignedType(
        _ type: TypeID,
        sema: SemaModule
    ) -> Bool {
        switch sema.types.kind(of: type) {
        case .primitive(.ubyte, .nonNull),
             .primitive(.ushort, .nonNull),
             .primitive(.uint, .nonNull),
             .primitive(.ulong, .nonNull):
            return true
        default:
            return false
        }
    }

    /// Lowers maxOf(a, b) / minOf(a, b) as: if (a > b) a else b
    private func lowerTwoArgComparison(
        args: [CallArgument],
        comparisonOp: KIRBinaryOp,
        boolType: TypeID,
        resultType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let lhsExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsExpr = driver.lowerExpr(
            args[1].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let conditionExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.binary(
            op: comparisonOp,
            lhs: lhsExpr,
            rhs: rhsExpr,
            result: conditionExpr
        ))

        let useRightLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

        instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: useRightLabel))
        instructions.append(.copy(from: lhsExpr, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(useRightLabel))
        instructions.append(.copy(from: rhsExpr, to: result))
        instructions.append(.label(endLabel))
        return result
    }

    /// Lowers maxOf(a, b, c) / minOf(a, b, c) as: val tmp = maxOf(a, b); maxOf(tmp, c)
    private func lowerThreeArgComparison(
        args: [CallArgument],
        comparisonOp: KIRBinaryOp,
        boolType: TypeID,
        resultType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let aExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let bExpr = driver.lowerExpr(
            args[1].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let cExpr = driver.lowerExpr(
            args[2].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // Step 1: tmp = maxOf(a, b) / minOf(a, b)
        let cond1 = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.binary(op: comparisonOp, lhs: aExpr, rhs: bExpr, result: cond1))

        let useBLabel = driver.ctx.makeLoopLabel()
        let afterFirstLabel = driver.ctx.makeLoopLabel()
        let tmp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

        instructions.append(.jumpIfEqual(lhs: cond1, rhs: falseExpr, target: useBLabel))
        instructions.append(.copy(from: aExpr, to: tmp))
        instructions.append(.jump(afterFirstLabel))
        instructions.append(.label(useBLabel))
        instructions.append(.copy(from: bExpr, to: tmp))
        instructions.append(.label(afterFirstLabel))

        // Step 2: result = maxOf(tmp, c) / minOf(tmp, c)
        let cond2 = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.binary(op: comparisonOp, lhs: tmp, rhs: cExpr, result: cond2))

        let useCLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

        instructions.append(.jumpIfEqual(lhs: cond2, rhs: falseExpr, target: useCLabel))
        instructions.append(.copy(from: tmp, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(useCLabel))
        instructions.append(.copy(from: cExpr, to: result))
        instructions.append(.label(endLabel))
        return result
    }
}
