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

        let receiverType = sema.bindings.exprType(for: receiverID)
        let rangeKind = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType ?? sema.types.anyType,
            sema: sema,
            interner: interner
        ) ?? .intRange
        let isCharRange = rangeKind.isCharRangeLike
        let isLongRange = rangeKind.isLongRangeLike
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
        let isUIntRange = rangeKind.isUIntRangeLike
        let isULongRange = rangeKind.isULongRangeLike

        if args.isEmpty,
           ["step", "start", "end", "endExclusive"].contains(memberName),
           let propertyResult = driver.helpers.lookupMemberProperty(
               named: calleeName,
               receiverType: sema.types.makeNonNullable(receiverType ?? sema.types.anyType),
               sema: sema
           )
        {
            sema.bindings.bindIdentifier(id, symbol: propertyResult.symbol)
        }

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

        if memberName == "random",
           args.count == 1
        {
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: rangeMemberRandomType(sema: sema, interner: interner)
            )
        }

        if isRangeMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }
        if memberName == "reversed" || (memberName == "step" && args.count == 1) {
            sema.bindings.markRangeExpr(id)
            // Propagate char range marker through range-preserving transforms.
            if sema.bindings.isCharRangeExpr(receiverID) {
                sema.bindings.markCharRangeExpr(id)
            }
            if sema.bindings.isUIntRangeExpr(receiverID) {
                sema.bindings.markUIntRangeExpr(id)
            }
            // Propagate ULong range marker through range-preserving transforms.
            if sema.bindings.isULongRangeExpr(receiverID) {
                sema.bindings.markULongRangeExpr(id)
            }
        }

        let resultType = rangeMemberResultType(
            memberName: memberName,
            argCount: args.count,
            sema: sema,
            interner: interner,
            receiverType: receiverType,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSupportedRangeMember(_ memberName: String) -> Bool {
        let rangeMembers: Set = [
            "start", "end", "endInclusive", "endExclusive", "first", "last", "count", "contains",
            "iterator",
            "toList", "toIntArray", "toLongArray", "toUIntArray", "toULongArray", "forEach", "map", "mapIndexed", "mapNotNull",
            "filter", "filterIndexed", "filterNot",
            "reduce", "reduceIndexed", "fold", "foldIndexed",
            "find", "findLast", "firstOrNull", "lastOrNull", "randomOrNull",
            "any", "all", "none",
            "chunked", "windowed",
            "reversed", "step", "isEmpty", "sum", "iterator",
            "random",
            "take", "drop", "average", "sorted",
        ]
        return rangeMembers.contains(memberName)
    }

    private func isValidRangeMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "count", "start", "end", "endInclusive", "endExclusive", "iterator", "toList", "toIntArray", "toLongArray", "toUIntArray", "toULongArray", "reversed", "isEmpty", "sum", "average", "sorted":
            argCount == 0
        case "random":
            argCount == 0 || argCount == 1
        case "step":
            argCount == 0 || argCount == 1
        case "first", "last":
            argCount == 0 || argCount == 1
        case "contains", "forEach", "map", "mapIndexed", "mapNotNull",
             "filter", "filterIndexed", "filterNot", "reduce", "reduceIndexed",
             "find", "findLast", "any", "all", "none",
             "take", "drop":
            argCount == 1
        case "firstOrNull", "lastOrNull":
            argCount == 0 || argCount == 1
        case "randomOrNull":
            argCount == 0 || argCount == 1
        case "fold", "foldIndexed":
            argCount == 2
        case "chunked":
            argCount == 1
        case "windowed":
            argCount == 3
        default:
            true
        }
    }

    private func isRangeMemberReturningCollection(_ memberName: String) -> Bool {
        ["toList", "map", "mapIndexed", "mapNotNull", "filter", "filterIndexed", "filterNot", "chunked", "windowed", "take", "drop", "sorted"].contains(memberName)
    }

    /// Returns the element type for a range expression based on its range-kind markers.
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

    private func rangeMemberResultType(
        memberName: String,
        argCount: Int,
        sema: SemaModule,
        interner: StringInterner,
        receiverType: TypeID? = nil,
        isCharRange: Bool = false,
        isLongRange: Bool = false,
        isUIntRange: Bool = false,
        isULongRange: Bool = false
    ) -> TypeID {
        let elementType = rangeMemberElementType(
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        )
        switch memberName {
        case "first", "last", "start", "end", "endInclusive", "endExclusive":
            return elementType
        case "random":
            return elementType
        case "firstOrNull", "lastOrNull", "randomOrNull", "find", "findLast":
            return sema.types.makeNullable(elementType)
        case "count":
            return sema.types.intType
        case "sum":
            return elementType
        case "contains", "isEmpty", "any", "all", "none":
            return sema.types.booleanType
        case "forEach":
            return sema.types.unitType
        case "iterator":
            return rangeMemberIteratorType(elementType: elementType, sema: sema, interner: interner)
        case "toList":
            return rangeMemberListType(elementType: elementType, sema: sema, interner: interner)
        case "toIntArray":
            return rangeMemberIntArrayType(sema: sema, interner: interner)
        case "toLongArray":
            return rangeMemberLongArrayType(sema: sema, interner: interner)
        case "toUIntArray":
            return rangeMemberUIntArrayType(sema: sema, interner: interner)
        case "toULongArray":
            return rangeMemberULongArrayType(sema: sema, interner: interner)
        case "filter", "filterIndexed", "filterNot":
            return rangeMemberListType(elementType: elementType, sema: sema, interner: interner)
        case "map", "mapIndexed", "mapNotNull":
            return rangeMemberListType(elementType: sema.types.anyType, sema: sema, interner: interner)
        case "reduce", "reduceIndexed":
            return elementType
        case "fold", "foldIndexed":
            return sema.types.anyType
        case "chunked", "windowed":
            return rangeMemberListType(
                elementType: rangeMemberListType(elementType: elementType, sema: sema, interner: interner),
                sema: sema,
                interner: interner
            )
        case "take", "drop", "sorted":
            return rangeMemberListType(elementType: elementType, sema: sema, interner: interner)
        case "average":
            return sema.types.doubleType
        case "reversed":
            return rangeMemberRangeType(
                receiverType: receiverType,
                elementType: elementType,
                sema: sema,
                interner: interner,
                isLongRange: isLongRange,
                isUIntRange: isUIntRange,
                isULongRange: isULongRange
            )
        case "step":
            return argCount == 0 ? sema.types.intType : rangeMemberRangeType(
                receiverType: receiverType,
                elementType: elementType,
                sema: sema,
                interner: interner,
                isLongRange: isLongRange,
                isUIntRange: isUIntRange,
                isULongRange: isULongRange
            )
        default:
            return sema.types.anyType
        }
    }

    private func rangeMemberRandomType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let randomFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("random"),
            interner.intern("Random"),
        ]
        guard let randomSymbol = sema.symbols.lookup(fqName: randomFQName) else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func rangeMemberListType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = sema.symbols.lookup(fqName: listFQName) else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func rangeMemberIteratorType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let iteratorSymbol = sema.symbols.lookupByShortName(interner.intern("Iterator")).first else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func rangeMemberIntArrayType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let intArraySymbol = sema.symbols.lookupByShortName(interner.intern("IntArray")).first else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: intArraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func rangeMemberLongArrayType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let longArraySymbol = sema.symbols.lookupByShortName(interner.intern("LongArray")).first else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: longArraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func rangeMemberUIntArrayType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let uintArraySymbol = sema.symbols.lookupByShortName(interner.intern("UIntArray")).first else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: uintArraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func rangeMemberULongArrayType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let ulongArraySymbol = sema.symbols.lookupByShortName(interner.intern("ULongArray")).first else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: ulongArraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func rangeMemberRangeType(
        receiverType: TypeID?,
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        isLongRange: Bool,
        isUIntRange: Bool,
        isULongRange: Bool
    ) -> TypeID {
        if let receiverType,
           case .classType = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        {
            return sema.types.makeNonNullable(receiverType)
        }

        if isULongRange {
            return sema.types.ulongType
        }
        if isUIntRange {
            return sema.types.uintType
        }
        if isLongRange {
            return sema.types.longType
        }
        if elementType == sema.types.charType {
            return sema.types.intType
        }

        guard let intRangeSymbol = sema.symbols.lookupByShortName(interner.intern("IntRange")).first else {
            return sema.types.intType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: intRangeSymbol,
            args: [],
            nullability: .nonNull
        )))
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
        let elementType = rangeMemberElementType(
            sema: sema,
            isCharRange: isCharRange,
            isLongRange: isLongRange,
            isUIntRange: isUIntRange,
            isULongRange: isULongRange
        )
        let expectation: (Int, [TypeID], TypeID)?
        switch memberName {
        case "forEach":
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.unitType)
        case "map":
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.anyType)
        case "mapNotNull":
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.nullableAnyType)
        case "filter", "filterNot", "find", "findLast", "first", "firstOrNull", "last", "lastOrNull", "any", "all", "none":
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType], sema.types.booleanType)
        case "mapIndexed":
            guard argCount == 1 else { return nil }
            expectation = (0, [sema.types.intType, elementType], sema.types.anyType)
        case "filterIndexed":
            guard argCount == 1 else { return nil }
            expectation = (0, [sema.types.intType, elementType], sema.types.booleanType)
        case "reduce":
            guard argCount == 1 else { return nil }
            expectation = (0, [elementType, elementType], elementType)
        case "reduceIndexed":
            guard argCount == 1 else { return nil }
            expectation = (0, [sema.types.intType, elementType, elementType], elementType)
        case "fold":
            guard argCount == 2 else { return nil }
            expectation = (1, [sema.types.anyType, elementType], sema.types.anyType)
        case "foldIndexed":
            guard argCount == 2 else { return nil }
            expectation = (1, [sema.types.intType, sema.types.anyType, elementType], sema.types.anyType)
        default:
            expectation = nil
        }
        guard let expectation else { return nil }
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: expectation.1,
            returnType: expectation.2,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: expectation.0, expectedType: expectedType)
    }
}
