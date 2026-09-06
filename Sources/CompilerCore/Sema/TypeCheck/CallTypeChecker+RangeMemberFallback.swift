
import Foundation

extension CallTypeChecker {
    // MARK: - Range member fallback (STDLIB-090/091/092/093)

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

        // An unqualified member call inside an extension body has no receiver
        // expression to bind. Use the extension receiver carried by the type
        // inference context in that case.
        let receiverType = sema.bindings.exprType(for: receiverID) ?? ctx.implicitReceiverType
        let isOpenEndRangeReceiver = receiverType.map {
            driver.helpers.isOpenEndRangeType($0, sema: sema, interner: interner)
        } ?? false
        guard !isClassNameReceiver,
              (sema.bindings.isRangeExpr(receiverID) || isOpenEndRangeReceiver)
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)

        // KSP-453: IntRange/IntProgression HOFs now have bundled Kotlin source
        // implementations; prefer source-backed resolution instead of the legacy
        // hardcoded range-member fallback.
        if let sourceType = bindSourceRangeHOFCall(
            id,
            memberName: memberName,
            calleeName: calleeName,
            receiverID: receiverID,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
        ) {
            return sourceType
        }

        if sema.bindings.isFloatingPointRangeExpr(receiverID),
           let floatingPointResult = tryRangeMembershipFallback(
            memberName: memberName,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
           )
        {
            sema.bindings.bindExprType(id, type: floatingPointResult)
            return floatingPointResult
        }
        if isOpenEndRangeReceiver,
           let sourceType = bindSourceOpenEndRangeContainsCall(
            id,
            receiverID: receiverID,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
           )
        {
            return sourceType
        }
        if isOpenEndRangeReceiver,
           let openEndResult = tryRangeMembershipFallback(
            memberName: memberName,
            args: args,
            safeCall: safeCall,
            ctx: ctx,
            locals: &locals
           )
        {
            sema.bindings.bindExprType(id, type: openEndResult)
            return openEndResult
        }
        guard isSupportedRangeMember(memberName),
              isValidRangeMemberArity(memberName, argCount: args.count)
        else {
            return nil
        }

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
        var mappedElementType: TypeID?
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
            // STDLIB-090: `map`'s declared expected type is `Any` (a permissive
            // upper bound for lambda inference), but the lambda body still infers
            // its own tightest type. Read that back so `(1..n).map { ... }` reports
            // `List<R>` instead of always widening to `List<Any>`.
            if memberName == "map",
               case let .lambdaLiteral(_, bodyExpr, _, _) = ctx.ast.arena.expr(lambdaArgExpr)
            {
                mappedElementType = sema.bindings.exprType(for: bodyExpr)
            }
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
            isULongRange: isULongRange,
            mappedElementType: mappedElementType
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func bindSourceOpenEndRangeContainsCall(
        _ id: ExprID,
        receiverID: ExprID,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        guard args.count == 1 else { return nil }

        let sema = ctx.sema
        let interner = ctx.interner
        guard let receiverType = sema.bindings.exprType(for: receiverID) ?? ctx.implicitReceiverType,
              let receiverElementType = driver.helpers.rangeLikeDeclaredElementType(
                  for: receiverType,
                  sema: sema,
                  interner: interner
              )
        else {
            return nil
        }
        let argumentType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)

        let candidates = sema.symbols.lookupByShortName(interner.intern("contains")).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  signature.parameterTypes.count == 1,
                  signature.parameterTypes[0] == sema.types.makeNonNullable(argumentType),
                  let declaredElementType = driver.helpers.rangeLikeDeclaredElementType(
                      for: declaredReceiver,
                      sema: sema,
                      interner: interner
                  ),
                  declaredElementType == receiverElementType,
                  driver.helpers.isOpenEndRangeType(
                      declaredReceiver,
                      sema: sema,
                      interner: interner
                  )
            else {
                return false
            }

            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }

        guard let chosen = candidates.first,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: signature.parameterTypes[0]
        )
        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: ResolvedCall(
                chosenCallee: chosen,
                substitutedTypeArguments: [:],
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func tryRangeMembershipFallback(
        memberName: String,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        switch memberName {
        case "contains":
            guard args.count == 1 else { return nil }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        case "isEmpty":
            guard args.isEmpty else { return nil }
        default:
            return nil
        }
        let resultType = ctx.sema.types.booleanType
        return safeCall ? ctx.sema.types.makeNullable(resultType) : resultType
    }

    private func isIntRangeSourceBackedHOF(_ memberName: String, argCount: Int) -> Bool {
        if memberName == "first" || memberName == "last" {
            return argCount > 0
        }
        let sourceBacked: Set<String> = [
            "toList", "toIntArray", "average", "sorted",
            "forEach", "map", "mapIndexed", "mapNotNull",
            "filter", "filterIndexed", "filterNot",
            "reduce", "reduceIndexed", "fold", "foldIndexed",
            "find", "findLast",
            "firstOrNull", "lastOrNull",
            "any", "all", "none",
            "chunked", "windowed",
            "take", "drop",
            "random", "randomOrNull",
        ]
        return sourceBacked.contains(memberName)
    }

    private func isCharProgressionSourceBackedHOF(_ memberName: String, argCount: Int) -> Bool {
        guard argCount == 0 else { return false }
        return memberName == "first"
            || memberName == "firstOrNull"
            || memberName == "last"
            || memberName == "lastOrNull"
    }

    private func isUIntRangeSourceBackedHOF(_ memberName: String, argCount: Int) -> Bool {
        if memberName == "first" || memberName == "last"
            || memberName == "firstOrNull" || memberName == "lastOrNull"
        {
            return argCount > 0
        }
        let sourceBacked: Set<String> = [
            "map", "mapIndexed", "mapNotNull",
            "filter", "filterIndexed", "filterNot",
            "forEach",
            "reduce", "reduceIndexed", "fold", "foldIndexed",
            "find", "findLast",
            "firstOrNull", "lastOrNull",
            "any", "all", "none",
        ]
        return sourceBacked.contains(memberName)
    }

    private func isUIntProgressionSourceBackedHOF(_ memberName: String, argCount: Int) -> Bool {
        guard argCount == 1 else { return false }
        return [
            "map", "mapIndexed", "mapNotNull",
            "filter", "filterIndexed", "filterNot",
        ].contains(memberName)
    }

    private func bindSourceRangeHOFCall(
        _ id: ExprID,
        memberName: String,
        calleeName: InternedString,
        receiverID: ExprID,
        args: [CallArgument],
        safeCall: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard let receiverType = sema.bindings.exprType(for: receiverID),
              let rangeKind = MemberRuntimeDispatch.rangeReceiverKind(
                  receiverExpr: receiverID,
                  receiverType: receiverType,
                  sema: sema,
                  interner: interner
              )
        else {
            return nil
        }

        let isSourceBackedRangeCall =
            ((rangeKind == .intRange || rangeKind == .intProgression)
                && isIntRangeSourceBackedHOF(memberName, argCount: args.count))
            || (rangeKind == .uintRange
                && isUIntRangeSourceBackedHOF(memberName, argCount: args.count))
            || (rangeKind == .uintProgression
                && isUIntProgressionSourceBackedHOF(memberName, argCount: args.count))
            || (rangeKind == .charProgression
                && isCharProgressionSourceBackedHOF(memberName, argCount: args.count))
            || ((memberName == "random" || memberName == "randomOrNull")
                && (rangeKind == .longRange || rangeKind == .charRange
                    || rangeKind == .uintRange || rangeKind == .ulongRange))

        guard isSourceBackedRangeCall,
              let sourceSymbol = sourceRangeHOFSymbol(
                  memberName: memberName,
                  rangeKind: rangeKind,
                  argCount: args.count,
                  sema: sema,
                  interner: interner
              ),
              let signature = sema.symbols.functionSignature(for: sourceSymbol)
        else {
            return nil
        }

        let lambdaExpectation = rangeMemberLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
            sema: sema,
            isCharRange: rangeKind.isCharRangeLike,
            isLongRange: rangeKind.isLongRangeLike,
            isUIntRange: rangeKind.isUIntRangeLike,
            isULongRange: rangeKind.isULongRangeLike
        )

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var rConcrete: TypeID?

        for (index, arg) in args.enumerated() {
            let isLambda = ctx.ast.arena.expr(arg.expr)?.isLambdaOrCallableRef == true
            if isLambda {
                let expectedType: TypeID
                if (memberName == "fold" || memberName == "foldIndexed"), index == 1, let rConcrete,
                   let baseExpected = lambdaExpectation?.expectedType,
                   case let .functionType(fnType) = sema.types.kind(of: baseExpected) {
                    let params: [TypeID]
                    if memberName == "fold" {
                        params = [rConcrete] + Array(fnType.params.dropFirst())
                    } else {
                        var mutableParams = fnType.params
                        if mutableParams.count >= 2 {
                            mutableParams[1] = rConcrete
                        }
                        params = mutableParams
                    }
                    expectedType = sema.types.make(.functionType(FunctionType(
                        params: params,
                        returnType: rConcrete
                    )))
                } else if let baseExpected = lambdaExpectation?.expectedType {
                    expectedType = baseExpected
                } else {
                    expectedType = sema.types.anyType
                }

                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: expectedType)
                if ctx.ast.arena.expr(arg.expr)?.isLambdaOrCallableRef == true {
                    sema.bindings.markCollectionHOFLambdaExpr(arg.expr)
                }

                if rConcrete == nil,
                   let lambdaExpr = ctx.ast.arena.expr(arg.expr),
                   case let .lambdaLiteral(_, bodyExpr, _, _) = lambdaExpr {
                    let bodyType = sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                    switch memberName {
                    case "map", "mapIndexed":
                        rConcrete = bodyType
                    case "mapNotNull":
                        rConcrete = sema.types.makeNonNullable(bodyType)
                    default:
                        break
                    }
                }
            } else {
                let expectedType: TypeID?
                if memberName == "fold" || memberName == "foldIndexed" {
                    expectedType = nil
                } else if memberName == "windowed" {
                    expectedType = (index == 1 ? sema.types.intType : (index == 2 ? sema.types.booleanType : nil))
                } else if memberName == "chunked" || memberName == "take" || memberName == "drop" {
                    expectedType = sema.types.intType
                } else {
                    expectedType = nil
                }

                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: expectedType)
                if (memberName == "fold" || memberName == "foldIndexed"), index == 0, rConcrete == nil {
                    rConcrete = sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                }
            }
        }

        let concreteR = rConcrete ?? sema.types.anyType
        var substitutions: [TypeVarID: TypeID] = [:]
        for (_, typeVar) in typeVarBySymbol {
            substitutions[typeVar] = concreteR
        }

        var parameterMapping: [Int: Int] = [:]
        for index in args.indices {
            parameterMapping[index] = index
        }

        let resolved = ResolvedCall(
            chosenCallee: sourceSymbol,
            substitutedTypeArguments: substitutions,
            parameterMapping: parameterMapping,
            diagnostic: nil
        )

        let returnType = bindCallAndResolveReturnType(id, chosen: sourceSymbol, resolved: resolved, sema: sema)
        if isRangeMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func sourceRangeHOFSymbol(
        memberName: String,
        rangeKind: MemberDispatchReceiverKind,
        argCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let expectedReceiverFQ = expectedRangeClassFQ(rangeKind: rangeKind, interner: interner) else {
            return nil
        }

        let candidates = sema.symbols.lookupByShortName(interner.intern(memberName)).filter { candidate in
            guard let symbolInfo = sema.symbols.symbol(candidate),
                  symbolInfo.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }

            guard argCount <= signature.parameterTypes.count else { return false }
            for missingIndex in argCount..<signature.parameterTypes.count {
                guard missingIndex < signature.valueParameterHasDefaultValues.count,
                      signature.valueParameterHasDefaultValues[missingIndex]
                else {
                    return false
                }
            }

            let declaredNonNull = sema.types.makeNonNullable(declaredReceiver)
            guard case let .classType(classType) = sema.types.kind(of: declaredNonNull),
                  let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }

            return receiverSymbol.fqName == expectedReceiverFQ
        }

        func hasLink(_ candidate: SymbolID) -> Bool {
            guard let linkName = sema.symbols.externalLinkName(for: candidate) else { return false }
            return !linkName.isEmpty
        }

        return candidates.first { hasLink($0) } ?? candidates.first
    }

    private func expectedRangeClassFQ(
        rangeKind: MemberDispatchReceiverKind,
        interner: StringInterner
    ) -> [InternedString]? {
        let kotlin = interner.intern("kotlin")
        let ranges = interner.intern("ranges")
        switch rangeKind {
        case .intRange:
            return [kotlin, ranges, interner.intern("IntRange")]
        case .intProgression:
            return [kotlin, ranges, interner.intern("IntProgression")]
        case .charProgression:
            return [kotlin, ranges, interner.intern("CharProgression")]
        case .longRange:
            return [kotlin, ranges, interner.intern("LongRange")]
        case .charRange:
            return [kotlin, ranges, interner.intern("CharRange")]
        case .uintRange:
            return [kotlin, ranges, interner.intern("UIntRange")]
        case .uintProgression:
            return [kotlin, ranges, interner.intern("UIntProgression")]
        case .ulongRange:
            return [kotlin, ranges, interner.intern("ULongRange")]
        default:
            return nil
        }
    }

    private func isSupportedRangeMember(_ memberName: String) -> Bool {
        let rangeMembers: Set = [
            "start", "end", "endInclusive", "endExclusive", "first", "last", "count",
            "toList", "toIntArray", "toLongArray", "toUIntArray", "toULongArray", "forEach", "map", "mapIndexed", "mapNotNull",
            "filter", "filterIndexed", "filterNot",
            "reduce", "reduceIndexed", "fold", "foldIndexed",
            "find", "findLast", "firstOrNull", "lastOrNull", "randomOrNull",
            "any", "all", "none",
            "chunked", "windowed",
            "reversed", "step", "sum",
            "random",
            "take", "drop", "average", "sorted",
        ]
        return rangeMembers.contains(memberName)
    }

    private func isValidRangeMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "count", "start", "end", "endInclusive", "endExclusive", "toList", "toIntArray", "toLongArray", "toUIntArray", "toULongArray", "reversed", "sum", "average", "sorted":
            argCount == 0
        case "random":
            argCount == 0 || argCount == 1
        case "step":
            argCount == 0 || argCount == 1
        case "first", "last":
            argCount == 0 || argCount == 1
        case "forEach", "map", "mapIndexed", "mapNotNull",
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
        isULongRange: Bool = false,
        mappedElementType: TypeID? = nil
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
        case "any", "all", "none":
            return sema.types.booleanType
        case "forEach":
            return sema.types.unitType
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
        case "map":
            return rangeMemberListType(elementType: mappedElementType ?? sema.types.anyType, sema: sema, interner: interner)
        case "mapIndexed", "mapNotNull":
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
