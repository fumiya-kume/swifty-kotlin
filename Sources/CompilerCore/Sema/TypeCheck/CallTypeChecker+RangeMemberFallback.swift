import Foundation

extension CallTypeChecker {
    // MARK: - IntRange member fallback (STDLIB-090/091/092/093)

    func tryRangeMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard !isClassNameReceiver,
              sema.bindings.isRangeExpr(receiverID)
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        guard isSupportedRangeMember(memberName),
              isValidRangeMemberArity(memberName, argCount: args.count)
        else {
            return nil
        }

        let isCharRange = sema.bindings.isCharRangeExpr(receiverID)

        // Provide contextual function type for range HOF lambda inference.
        if let expectation = rangeMemberLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
            sema: sema,
            isCharRange: isCharRange
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), case .lambdaLiteral = lambdaExpr {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }

        if isRangeMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }
        if memberName == "reversed" {
            sema.bindings.markRangeExpr(id)
            // Propagate char range marker through reversed() (STDLIB-290)
            if sema.bindings.isCharRangeExpr(receiverID) {
                sema.bindings.markCharRangeExpr(id)
            }
        }

        let resultType = rangeMemberResultType(memberName: memberName, sema: sema)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSupportedRangeMember(_ memberName: String) -> Bool {
        let rangeMembers: Set = [
            "first", "last", "count", "contains",
            "toList", "forEach", "map",
            "reversed",
        ]
        return rangeMembers.contains(memberName)
    }

    private func isValidRangeMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "first", "last", "count", "toList", "reversed":
            argCount == 0
        case "contains", "forEach", "map":
            argCount == 1
        default:
            true
        }
    }

    private func isRangeMemberReturningCollection(_ memberName: String) -> Bool {
        ["toList", "map"].contains(memberName)
    }

    private func rangeMemberResultType(memberName: String, sema: SemaModule) -> TypeID {
        switch memberName {
        case "first", "last", "count":
            sema.types.intType
        case "contains":
            sema.types.booleanType
        case "forEach":
            sema.types.unitType
        case "reversed":
            sema.types.intType
        default:
            sema.types.anyType
        }
    }

    private func rangeMemberLambdaExpectation(
        memberName: String,
        argCount: Int,
        sema: SemaModule,
        isCharRange: Bool = false
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let oneParamMembers: Set = ["forEach", "map"]
        guard oneParamMembers.contains(memberName), argCount == 1 else {
            return nil
        }
        let lambdaReturnType = memberName == "forEach" ? sema.types.unitType : sema.types.anyType
        let elementType = isCharRange ? sema.types.charType : sema.types.intType
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: lambdaReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: 0, expectedType: expectedType)
    }
}
