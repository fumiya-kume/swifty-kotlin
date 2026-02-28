import Foundation


extension CallLowerer {
    func lowerIndexedAccessExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        return lowerIndexedAccessExpr(
            exprID,
            receiverExpr: receiverExpr,
            indices: indices,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerIndexedAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        return lowerIndexedAssignExpr(
            exprID,
            receiverExpr: receiverExpr,
            indices: indices,
            valueExpr: valueExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerIndexedCompoundAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        return lowerIndexedCompoundAssignExpr(
            exprID,
            receiverExpr: receiverExpr,
            indices: indices,
            valueExpr: valueExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }
}
