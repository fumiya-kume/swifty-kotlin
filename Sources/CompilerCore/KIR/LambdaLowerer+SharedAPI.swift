import Foundation

/// Forwarding overloads for LambdaLowerer that accept KIRLoweringSharedContext
/// and KIRLoweringEmitContext, delegating to the old-API functions.
extension LambdaLowerer {
    func lowerLambdaLiteralExpr(
        _ exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var old = Array(instructions)
        let result = lowerLambdaLiteralExpr(
            exprID,
            params: params,
            bodyExpr: bodyExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &old
        )
        instructions = KIRLoweringEmitContext(old)
        return result
    }

    func lowerCallableRefExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID?,
        memberName: InternedString,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var old = Array(instructions)
        let result = lowerCallableRefExpr(
            exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &old
        )
        instructions = KIRLoweringEmitContext(old)
        return result
    }
}
