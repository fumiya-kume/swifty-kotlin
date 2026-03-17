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
        guard let specialKind = sema.bindings.stdlibSpecialCallKind(for: exprID) else {
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
