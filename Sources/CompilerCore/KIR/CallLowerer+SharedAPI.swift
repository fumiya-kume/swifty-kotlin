import Foundation

extension CallLowerer {
    func lowerMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        var emit = KIRLoweringEmitContext(instructions)
        let result = lowerMemberCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            driver: driver,
            shared: .init(
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            ),
            emit: &emit
        )
        instructions = emit.instructions
        return result
    }

    func lowerCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerCallExpr(
            exprID,
            calleeExpr: calleeExpr,
            args: args,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerMemberCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            driver: driver,
            shared: shared,
            emit: &instructions
        )
    }
}
