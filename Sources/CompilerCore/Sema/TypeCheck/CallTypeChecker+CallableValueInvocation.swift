
extension CallTypeChecker {
    func markRangeCallBindings(
        _ id: ExprID,
        chosen: SymbolID,
        returnType: TypeID,
        sema: SemaModule
    ) {
        let interner = driver.interner
        let isRangeConstructor: Bool
        let externalLinkName = sema.symbols.externalLinkName(for: chosen)
        if let externalLinkName, !CallLowerer.isSourceBackedLinkName(externalLinkName) {
            isRangeConstructor = [
                "kk_op_rangeTo",
                "__kk_op_rangeUntil",
                "__kk_op_ulong_rangeUntil",
                "__kk_uint_rangeTo",
                "kk_char_rangeTo",
                "__kk_int_progression_fromClosedRange",
                "__kk_long_progression_fromClosedRange",
                "__kk_uint_progression_fromClosedRange",
                "__kk_ulong_progression_fromClosedRange",
                "__kk_char_progression_fromClosedRange",
            ].contains(externalLinkName)
        } else if let symbol = sema.symbols.symbol(chosen) {
            let name = interner.resolve(symbol.name)
            isRangeConstructor = ["rangeTo", "until", "rangeUntil", "downTo", "step", "fromClosedRange"].contains(name)
                && driver.helpers.isRangeLikeType(returnType, sema: sema, interner: interner)
        } else {
            isRangeConstructor = false
        }

        guard isRangeConstructor else { return }

        sema.bindings.markRangeExpr(id)

        // Classify the concrete range/progression kind for UInt/ULong/Char dispatch.
        if let (_, symbol) = resolveClassTypeSymbol(returnType, sema: sema) {
            let className = interner.resolve(symbol.name)
            switch className {
            case "UIntRange", "UIntProgression":
                sema.bindings.markUIntRangeExpr(id)
            case "ULongRange", "ULongProgression":
                sema.bindings.markULongRangeExpr(id)
            case "CharRange", "CharProgression":
                sema.bindings.markCharRangeExpr(id)
            default:
                break
            }
        }

        // Preserve the legacy external-link-name fast paths for the residual
        // synthetic/runtime-backed operators (rangeTo, old signed rangeUntil,
        // etc.) whose return type may still be the scalar handle.
        if let externalLinkName = sema.symbols.externalLinkName(for: chosen) {
            if externalLinkName == "__kk_uint_rangeTo"
                || externalLinkName == "__kk_uint_progression_fromClosedRange"
                || (externalLinkName == "__kk_op_rangeUntil" && returnType == sema.types.uintType)
            {
                sema.bindings.markUIntRangeExpr(id)
            }
            if externalLinkName == "kk_char_rangeTo" {
                sema.bindings.markCharRangeExpr(id)
            }
            if externalLinkName == "__kk_ulong_progression_fromClosedRange"
                || externalLinkName == "__kk_op_ulong_rangeUntil"
            {
                sema.bindings.markULongRangeExpr(id)
            }
        }
    }

    func bindCallAndResolveReturnType(
        _ id: ExprID,
        chosen: SymbolID,
        resolved: ResolvedCall,
        sema: SemaModule
    ) -> TypeID {
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        if sema.symbols.externalLinkName(for: chosen) == "__kk_string_split" {
            sema.bindings.markCollectionExpr(id)
        }
        let returnType: TypeID
        if let signature = sema.symbols.functionSignature(for: chosen) {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            returnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        } else {
            returnType = sema.types.anyType
        }
        markRangeCallBindings(id, chosen: chosen, returnType: returnType, sema: sema)
        return returnType
    }

    func inferCallableValueInvocation(
        _ id: ExprID,
        calleeType: TypeID,
        callableTarget: CallableTarget?,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let nonNullCalleeType = sema.types.makeNonNullable(calleeType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCalleeType) else {
            return nil
        }
        guard !args.contains(where: { $0.label != nil || $0.isSpread }),
              functionType.params.count == argTypes.count
        else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        var parameterMapping: [Int: Int] = [:]
        for index in argTypes.indices {
            parameterMapping[index] = index
            driver.emitSubtypeConstraint(
                left: argTypes[index],
                right: functionType.params[index],
                range: ast.arena.exprRange(args[index].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        if let expectedType {
            driver.emitSubtypeConstraint(
                left: functionType.returnType,
                right: expectedType,
                range: range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        sema.bindings.bindCallableValueCall(
            id,
            binding: CallableValueCallBinding(
                target: callableTarget,
                functionType: nonNullCalleeType,
                parameterMapping: parameterMapping
            )
        )
        if let callableTarget {
            sema.bindings.bindCallableTarget(id, target: callableTarget)
        }
        sema.bindings.bindExprType(id, type: functionType.returnType)
        return functionType.returnType
    }

    func inferFunctionTypeOrError(from type: TypeID, sema: SemaModule) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(type)
        guard case .functionType = sema.types.kind(of: nonNullType) else {
            return nil
        }
        return nonNullType
    }
}
