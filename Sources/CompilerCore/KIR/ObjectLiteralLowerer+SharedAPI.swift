import Foundation

/// Forwarding overload for ObjectLiteralLowerer that accepts KIRLoweringSharedContext
/// and KIRLoweringEmitContext, delegating to the old-API function.
extension ObjectLiteralLowerer {
    func lowerObjectLiteralExpr(
        _ exprID: ExprID,
        superTypes: [TypeRefID],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var old = Array(instructions)
        let result = lowerObjectLiteralExpr(
            exprID,
            superTypes: superTypes,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            instructions: &old
        )
        instructions = KIRLoweringEmitContext(old)
        return result
    }
}
