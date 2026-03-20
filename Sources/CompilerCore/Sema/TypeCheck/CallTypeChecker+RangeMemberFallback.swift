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
        let receiverType = sema.bindings.exprType(for: receiverID)
        let isLongRange = receiverType == sema.types.longType
        // STDLIB-523: UIntRange / ULongRange support
        // Note on lowering: UIntRange/ULongRange do not require separate lowering
        // passes or runtime helpers. All numeric ranges (Int, Long, UInt, ULong)
        // share the same RuntimeRangeBox representation (first/last/step stored as
        // Swift Int, which is platform-sized -- 64-bit on all supported platforms).
        // The existing kk_range_* runtime functions handle unsigned values correctly for the
        // common case because:
        //   - UInt values (0..UInt32.max) fit in the non-negative half of Int64
        //   - rangeTo/rangeUntil always produce non-negative step (+1)
        //   - Signed comparisons (<=, >=) are correct for non-negative values
        //   - Wrapping arithmetic (&+=) works identically for both representations
        // Limitation: ULong values > Int64.max (i.e. > 2^63-1) are stored via
        // bit-pattern reinterpretation and may produce incorrect iteration order
        // or comparison results. This is a known limitation; full ULong support
        // would require unsigned comparison helpers in the runtime.
        // Only CharRange needs separate helpers (kk_char_range_*) due to box/unbox.
        let isUIntRange = receiverType == sema.types.uintType
        let isULongRange = receiverType == sema.types.ulongType

        // Provide contextual function type for range HOF lambda inference.
        if let expectation = rangeMemberLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
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

        let resultType = rangeMemberResultType(memberName: memberName, sema: sema, isCharRange: isCharRange, isLongRange: isLongRange, isUIntRange: isUIntRange, isULongRange: isULongRange)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSupportedRangeMember(_ memberName: String) -> Bool {
        let rangeMembers: Set = [
            "first", "last", "count", "contains",
            "toList", "forEach", "map",
            "reversed", "isEmpty", "sum",
        ]
        return rangeMembers.contains(memberName)
    }

    private func isValidRangeMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "first", "last", "count", "toList", "reversed", "isEmpty", "sum":
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

    private func rangeMemberElementType(
        sema: SemaModule,
        isCharRange: Bool,
        isLongRange: Bool,
        isUIntRange: Bool,
        isULongRange: Bool
    ) -> TypeID {
        if isCharRange {
            return sema.types.charType
        }
        if isLongRange {
            return sema.types.longType
        }
        if isUIntRange {
            return sema.types.uintType
        }
        if isULongRange {
            return sema.types.ulongType
        }
        return sema.types.intType
    }

    private func rangeMemberResultType(memberName: String, sema: SemaModule, isCharRange: Bool = false, isLongRange: Bool = false, isUIntRange: Bool = false, isULongRange: Bool = false) -> TypeID {
        let elementType = rangeMemberElementType(
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        )
        switch memberName {
        case "first", "last":
            return elementType
        case "count":
            return sema.types.intType
        case "sum":
            return elementType
        case "contains", "isEmpty":
            return sema.types.booleanType
        case "forEach":
            return sema.types.unitType
        case "reversed":
            return elementType
        default:
            return sema.types.anyType
        }
    }

    private func rangeMemberLambdaExpectation(
        memberName: String,
        argCount: Int,
        sema: SemaModule,
        isCharRange: Bool = false,
        isLongRange: Bool = false,
        isUIntRange: Bool = false,
        isULongRange: Bool = false
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let oneParamMembers: Set = ["forEach", "map"]
        guard oneParamMembers.contains(memberName), argCount == 1 else {
            return nil
        }
        let lambdaReturnType = memberName == "forEach" ? sema.types.unitType : sema.types.anyType
        let elementType = rangeMemberElementType(
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        )
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: lambdaReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: 0, expectedType: expectedType)
    }
}
