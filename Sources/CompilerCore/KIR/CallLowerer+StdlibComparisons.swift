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
        guard let specialKind = sema.bindings.stdlibSpecialCallKind(for: exprID),
              args.count == 2
        else {
            return nil
        }
        let comparisonOp: KIRBinaryOp
        switch specialKind {
        case .maxOfInt:
            comparisonOp = .greaterThan
        case .minOfInt:
            comparisonOp = .lessThan
        default:
            return nil
        }

        let intType = sema.types.intType
        let boolType = sema.types.booleanType
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
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)

        instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: useRightLabel))
        instructions.append(.copy(from: lhsExpr, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(useRightLabel))
        instructions.append(.copy(from: rhsExpr, to: result))
        instructions.append(.label(endLabel))
        return result
    }
}
