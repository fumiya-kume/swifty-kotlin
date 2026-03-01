import Foundation

extension CallLowerer {
    // MARK: - Binary Operations

    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerBinaryExpr(
            exprID,
            op: op,
            lhs: lhs,
            rhs: rhs,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }
}
