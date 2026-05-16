import Foundation

extension CallTypeChecker {
    func inferMemberCallImpl(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID {
        let request = MemberCallInferenceRequest(
            id: id,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall
        )

        markDeferredCollectionHOFLambdaIfNeeded(request)

        if let result = tryInferMemberCallWithoutReceiverSpecials(request, locals: &locals) {
            return result
        }

        let receiverType = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        let recoveredReceiverType = recoveredMemberCallReceiverType(
            receiverID: receiverID,
            receiverType: receiverType,
            ctx: ctx,
            locals: locals
        )

        if let result = tryInferMemberCallEarlyReceiverSpecials(
            request,
            receiverType: receiverType,
            recoveredReceiverType: recoveredReceiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallScopeResultAndFileSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallCollectionFlowSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallStringRangeComparatorSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        return inferRegularMemberCall(request, receiverType: receiverType, locals: &locals)
    }
}
