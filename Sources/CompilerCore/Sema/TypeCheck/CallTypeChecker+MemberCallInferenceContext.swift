import Foundation

extension CallTypeChecker {
    struct MemberCallInferenceRequest {
        let id: ExprID
        let receiverID: ExprID
        let calleeName: InternedString
        let args: [CallArgument]
        let range: SourceRange
        let ctx: TypeInferenceContext
        let expectedType: TypeID?
        let explicitTypeArgs: [TypeID]
        let safeCall: Bool
    }

    func markDeferredCollectionHOFLambdaIfNeeded(_ request: MemberCallInferenceRequest) {
        let ast = request.ctx.ast
        let sema = request.ctx.sema
        let interner = request.ctx.interner
        let calleeName = request.calleeName
        let args = request.args

        if ["firstNotNullOf", "firstNotNullOfOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceRightOrNull", "sumBy", "sumByDouble"]
            .contains(interner.resolve(calleeName)),
            args.count == 1,
            let lambdaExpr = ast.arena.expr(args[0].expr),
            lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        }
    }

    func tryInferMemberCallWithoutReceiverSpecials(
        _ request: MemberCallInferenceRequest,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let explicitTypeArgs = request.explicitTypeArgs

        if let result = tryInferLateinitIsInitializedCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferClassRefMemberCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            explicitTypeArgs: explicitTypeArgs, range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferNumericCompanionMemberCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            ctx: ctx, locals: &locals
        ) {
            return result
        }

        return nil
    }

    func recoveredMemberCallReceiverType(
        receiverID: ExprID,
        receiverType: TypeID,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        if case .any = sema.types.kind(of: sema.types.makeNonNullable(receiverType)) {
            if let symbol = sema.bindings.identifierSymbol(for: receiverID),
               let propertyType = sema.symbols.propertyType(for: symbol)
            {
                return propertyType
            } else if case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
                      let local = locals[receiverName]
            {
                return sema.symbols.propertyType(for: local.symbol) ?? local.type
            }
        }
        return nil
    }
}
