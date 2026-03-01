import Foundation

/// Forwarding overloads for ControlFlowLowerer that accept KIRLoweringSharedContext
/// and KIRLoweringEmitContext, delegating to the old-API functions.
extension ControlFlowLowerer {
    func lowerForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString? = nil,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerForExpr(
            exprID,
            iterableExpr: iterableExpr,
            bodyExpr: bodyExpr,
            label: label,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerWhileExpr(
        _ exprID: ExprID,
        conditionExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString? = nil,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerWhileExpr(
            exprID,
            conditionExpr: conditionExpr,
            bodyExpr: bodyExpr,
            label: label,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerDoWhileExpr(
        _ exprID: ExprID,
        bodyExpr: ExprID,
        conditionExpr: ExprID,
        label: InternedString? = nil,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerDoWhileExpr(
            exprID,
            bodyExpr: bodyExpr,
            conditionExpr: conditionExpr,
            label: label,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerIfExpr(
        _ exprID: ExprID,
        condition: ExprID,
        thenExpr: ExprID,
        elseExpr: ExprID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerIfExpr(
            exprID,
            condition: condition,
            thenExpr: thenExpr,
            elseExpr: elseExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerTryExpr(
        _ exprID: ExprID,
        bodyExpr: ExprID,
        catchClauses: [CatchClause],
        finallyExpr: ExprID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerTryExpr(
            exprID,
            bodyExpr: bodyExpr,
            catchClauses: catchClauses,
            finallyExpr: finallyExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }
}
