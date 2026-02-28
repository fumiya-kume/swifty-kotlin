import Foundation

/// Forwarding overloads for CallLowerer that accept KIRLoweringSharedContext
/// and KIRLoweringEmitContext, delegating to the old-API functions.
extension CallLowerer {
    func lowerCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var old = Array(instructions)
        let result = lowerCallExpr(
            exprID,
            calleeExpr: calleeExpr,
            args: args,
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

    func lowerMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var old = Array(instructions)
        let result = lowerMemberCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
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
