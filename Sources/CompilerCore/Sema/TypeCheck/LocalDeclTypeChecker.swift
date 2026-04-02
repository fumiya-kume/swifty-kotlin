import Foundation

final class LocalDeclTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func inferLocalDeclExpr(
        _ id: ExprID,
        name: InternedString,
        isMutable: Bool,
        typeAnnotation: TypeRefID?,
        initializer: ExprID?,
        isDelegated: Bool,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        var declaredType: TypeID?
        if let typeAnnotation {
            declaredType = driver.helpers.resolveTypeRef(
                typeAnnotation,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }

        var initializerType: TypeID?
        if let initializer {
            initializerType = tryInferExpectedTypeDrivenBuilderInferenceInitializer(
                initializer,
                declaredType: declaredType,
                ctx: ctx,
                locals: &locals
            ) ?? driver.inferExpr(initializer, ctx: ctx, locals: &locals, expectedType: declaredType)
        }

        let localType: TypeID
        if let declaredType {
            localType = declaredType
            if let initializerType {
                if isDelegated {
                    // Local delegated properties are currently modeled as local
                    // declarations whose initializer is the delegate factory call.
                    // Preserve the declared property type and skip constraining
                    // the delegate object itself to that property type.
                } else {
                    driver.emitSubtypeConstraint(
                        left: initializerType, right: declaredType,
                        range: range, solver: ConstraintSolver(),
                        sema: sema, diagnostics: ctx.semaCtx.diagnostics
                    )
                }
            }
        } else if let initializerType {
            localType = initializerType
        } else {
            localType = sema.types.errorType
        }

        let localSymbol = sema.symbols.define(
            kind: .local,
            name: name,
            fqName: [
                ctx.interner.intern("__local_\(id.rawValue)"),
                name,
            ],
            declSite: range,
            visibility: .private,
            flags: isMutable ? [.mutable] : []
        )
        sema.symbols.setPropertyType(localType, for: localSymbol)
        locals[name] = (localType, localSymbol, isMutable, initializer != nil)
        sema.bindings.bindIdentifier(id, symbol: localSymbol)
        // Propagate collection marks through local variable declarations
        // so that `val list = listOf(1,2,3); list.size` still recognizes
        // `list` as a collection receiver (P5-84).
        if let initializer, sema.bindings.isCollectionExpr(initializer) {
            sema.bindings.markCollectionExpr(id)
            sema.bindings.markCollectionSymbol(localSymbol)
        }
        if let initializer, sema.bindings.isRangeExpr(initializer) {
            sema.bindings.markRangeExpr(id)
            sema.bindings.markRangeSymbol(localSymbol)
            if sema.bindings.isCharRangeExpr(initializer) {
                sema.bindings.markCharRangeExpr(id)
                sema.bindings.markCharRangeSymbol(localSymbol)
            }
            if sema.bindings.isUIntRangeExpr(initializer) {
                sema.bindings.markUIntRangeExpr(id)
                sema.bindings.markUIntRangeSymbol(localSymbol)
            }
            if sema.bindings.isULongRangeExpr(initializer) {
                sema.bindings.markULongRangeExpr(id)
                sema.bindings.markULongRangeSymbol(localSymbol)
            }
        }
        if let initializer, sema.bindings.isFlowExpr(initializer) {
            sema.bindings.markFlowExpr(id)
            sema.bindings.markFlowSymbol(localSymbol)
            if let flowElementType = sema.bindings.flowElementType(forExpr: initializer) {
                sema.bindings.bindFlowElementType(flowElementType, forExpr: id)
                sema.bindings.bindFlowElementType(flowElementType, forSymbol: localSymbol)
            }
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    private func tryInferExpectedTypeDrivenBuilderInferenceInitializer(
        _ initializer: ExprID,
        declaredType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        guard let declaredType,
              let initializerExpr = ast.arena.expr(initializer),
              case let .call(calleeID, _, args, range) = initializerExpr,
              let calleeExpr = ast.arena.expr(calleeID),
              case let .nameRef(calleeName, _) = calleeExpr
        else {
            return nil
        }

        let candidateIDs = ctx.filterByVisibility(
            ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        ).visible
        guard !candidateIDs.isEmpty else {
            return nil
        }

        var inferredNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral, .callableRef:
                continue
            default:
                inferredNonLambdaArgTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }
        }

        return driver.callChecker.tryResolveExpectedTypeDrivenBuilderInferenceCall(
            initializer,
            candidates: candidateIDs,
            args: args,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: declaredType,
            calleeName: calleeName,
            explicitTypeArgs: []
        ) ?? tryInferTypedReceiverLambdaCallInitializer(
            initializer: initializer,
            candidates: candidateIDs,
            args: args,
            declaredType: declaredType,
            calleeName: calleeName,
            range: range,
            ctx: ctx,
            locals: &locals
        )
    }

    private func tryInferTypedReceiverLambdaCallInitializer(
        initializer: ExprID,
        candidates: [SymbolID],
        args: [CallArgument],
        declaredType: TypeID,
        calleeName: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        guard candidates.count == 1,
              let candidate = candidates.first,
              let signature = sema.symbols.functionSignature(for: candidate),
              let lambdaIndex = args.indices.first(where: { index in
                  guard let argumentExpr = ctx.ast.arena.expr(args[index].expr),
                        case .lambdaLiteral = argumentExpr,
                        index < signature.parameterTypes.count
                  else {
                      return false
                  }
                  let parameterType = sema.types.makeNonNullable(signature.parameterTypes[index])
                  guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                      return false
                  }
                  return functionType.receiver != nil
              })
        else {
            return nil
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let constraints = ctx.resolver.decomposeSubtypeConstraint(
            subtype: signature.returnType,
            supertype: declaredType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: sema.types,
            blameRange: range
        )
        let variables = Array(Set(typeVarBySymbol.values)).sorted(by: { $0.rawValue < $1.rawValue })
        let solution = ConstraintSolver().solve(
            vars: variables,
            constraints: constraints,
            typeSystem: sema.types
        )
        guard solution.isSuccess else {
            return nil
        }

        let substitutedLambdaType = sema.types.substituteTypeParameters(
            in: signature.parameterTypes[lambdaIndex],
            substitution: solution.substitution,
            typeVarBySymbol: typeVarBySymbol
        )
        _ = driver.inferExpr(
            args[lambdaIndex].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: substitutedLambdaType
        )

        let resolvedArgs = args.enumerated().map { index, argument in
            let argType = sema.bindings.exprType(for: argument.expr) ?? sema.types.anyType
            return CallArg(label: argument.label, isSpread: argument.isSpread, type: argType)
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: resolvedArgs,
            explicitTypeArgs: []
        )
        guard let parameterMapping = ctx.resolver.buildParameterMapping(
            signature: signature,
            callArgs: call.args,
            symbols: sema.symbols
        ) else {
            return nil
        }

        _ = driver.callChecker.bindCallAndResolveReturnType(
            initializer,
            chosen: candidate,
            resolved: ResolvedCall(
                chosenCallee: candidate,
                substitutedTypeArguments: solution.substitution,
                parameterMapping: parameterMapping,
                diagnostic: nil
            ),
            sema: sema
        )
        return declaredType
    }

    func inferLocalAssignExpr(
        _ id: ExprID,
        name: InternedString,
        value: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let interner = ctx.interner

        let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
        if let local = locals[name] {
            ctx.sema.bindings.bindIdentifier(id, symbol: local.symbol)
            if !local.isMutable, local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: local.type,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: ctx.sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                locals[name] = (local.type, local.symbol, local.isMutable, true)
                if ctx.sema.bindings.isFlowExpr(value) {
                    ctx.sema.bindings.markFlowSymbol(local.symbol)
                    if let flowElementType = ctx.sema.bindings.flowElementType(forExpr: value) {
                        ctx.sema.bindings.bindFlowElementType(flowElementType, forSymbol: local.symbol)
                    }
                } else {
                    ctx.sema.bindings.unmarkFlowSymbol(local.symbol)
                }
            }
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        if let implicitReceiverType = ctx.implicitReceiverType,
           let member = driver.helpers.lookupMemberProperty(
               named: name,
               receiverType: ctx.sema.types.makeNonNullable(implicitReceiverType),
               sema: ctx.sema
           )
        {
            ctx.sema.bindings.bindIdentifier(id, symbol: member.symbol)
            let propSymbol = ctx.sema.symbols.symbol(member.symbol)
            if let propSymbol,
               !propSymbol.flags.contains(.mutable),
               !ctx.allowsValPropertyInitialization
            {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: member.type,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: ctx.sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        // Fall back to scope-visible property lookup for assignments like
        // `counter = counter + 1` where `counter` is a top-level var or a
        // member property accessed via implicit receiver (inside a
        // class/object member function).
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, _) = ctx.filterByVisibility(dslFilteredIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if let propSymbol = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = ctx.sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = ctx.sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package || (ctx.implicitReceiverType != nil
                && (parentSym.kind == .class || parentSym.kind == .object || parentSym.kind == .interface))
        }) {
            ctx.sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            let propType = ctx.sema.symbols.propertyType(for: propSymbol.id) ?? ctx.sema.types.anyType
            if !propSymbol.flags.contains(.mutable), !ctx.allowsValPropertyInitialization {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                driver.emitSubtypeConstraint(
                    left: valueType,
                    right: propType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: ctx.sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }

        if !dslBlockedIDs.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-DSLMARKER",
                "'@DslMarker' implicit access to '\(interner.resolve(name))' from outer receiver is restricted. Use explicit receiver.",
                range: range
            )
        } else if name == KnownCompilerNames(interner: interner).field {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-FIELD",
                "'field' can only be used inside a property getter or setter body.",
                range: range
            )
        } else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0013",
                "Unresolved local variable '\(interner.resolve(name))'.",
                range: range
            )
        }
        ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
        return ctx.sema.types.errorType
    }
}
