
extension ExprTypeChecker {
    private func bindCompoundAssignmentOperatorCall(
        exprID: ExprID,
        op: CompoundAssignOp,
        receiverType: TypeID,
        valueType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        requireUnitReturn: Bool,
        emitDiagnostics: Bool = true,
        bindCall: Bool = true
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        // Kotlin resolves `a += b` in two phases: first the dedicated in-place
        // operator (e.g. `plusAssign`, which must return Unit), then the
        // corresponding binary operator (e.g. `plus`) rebinding as `a = a.plus(b)`.
        // Each phase must search its own operator name — otherwise a type that
        // defines only `plus` (no `plusAssign`) is never found here, and the
        // caller silently falls back to the builtin numeric/string compound-assign
        // path even though the receiver isn't numeric/string.
        let operatorNames = requireUnitReturn
            ? operatorFunctionNames(for: op, interner: interner)
            : operatorFunctionNames(for: driver.helpers.compoundAssignToBinaryOp(op), interner: interner)
        let operatorCandidates = collectOperatorCandidates(
            names: operatorNames,
            receiverType: receiverType,
            ctx: ctx
        )
        guard !operatorCandidates.isEmpty else {
            return nil
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: operatorCandidates,
            call: CallExpr(
                range: range,
                calleeName: operatorNames[0],
                args: [CallArg(type: valueType)]
            ),
            expectedType: nil,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )

        if let diagnostic = resolved.diagnostic {
            if emitDiagnostics {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            }
            return sema.types.errorType
        }

        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        let returnType: TypeID
        if bindCall {
            returnType = driver.callChecker.bindCallAndResolveReturnType(
                exprID,
                chosen: chosen,
                resolved: resolved,
                sema: sema
            )
        } else if let signature = sema.symbols.functionSignature(for: chosen) {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            returnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        } else {
            returnType = sema.types.anyType
        }

        if requireUnitReturn,
           !sema.types.isSubtype(returnType, sema.types.unitType)
        {
            if emitDiagnostics {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0300",
                    "Operator '\(interner.resolve(operatorNames[0]))' used in compound assignment must return Unit.",
                    range: range
                )
                sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            }
            return sema.types.errorType
        }

        if !requireUnitReturn,
           !sema.types.isSubtype(returnType, receiverType)
        {
            if emitDiagnostics {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0301",
                    "Operator '\(interner.resolve(operatorNames[0]))' result type must be assignable to the left-hand side.",
                    range: range
                )
                sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            }
            return sema.types.errorType
        }

        if bindCall {
            sema.bindings.bindExprType(exprID, type: sema.types.unitType)
        }
        return sema.types.unitType
    }

    /// Result type of an arithmetic compound assignment whose operator function could
    /// not be resolved: numeric targets keep their own type, everything else falls back
    /// to `Int` (BUG-015).
    private func numericCompoundAssignResultType(_ targetType: TypeID, ctx: TypeInferenceContext) -> TypeID {
        guard case let .primitive(primitive, .nonNull) = ctx.sema.types.kind(of: targetType) else {
            return ctx.sema.types.intType
        }
        switch primitive {
        case .boolean, .char:
            return ctx.sema.types.intType
        case .byte, .short, .int, .long, .float, .double, .uint, .ulong, .ubyte, .ushort:
            return targetType
        }
    }

    func inferCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        name: InternedString,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let intType = sema.types.intType
        let charType = sema.types.charType
        let stringType = sema.types.stringType

        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
        if let local = locals[name] {
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: range
                )
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: local.type,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: true
            ) {
                if local.isMutable,
                   let binaryFallback = bindCompoundAssignmentOperatorCall(
                       exprID: id,
                       op: op,
                       receiverType: local.type,
                       valueType: valueType,
                       range: range,
                       ctx: ctx,
                       requireUnitReturn: false,
                       emitDiagnostics: false,
                       bindCall: false
                   ),
                   binaryFallback != sema.types.errorType
                {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0302",
                        "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                return resolvedType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: local.type,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: false
            ) {
                if resolvedType == sema.types.errorType || !local.isMutable {
                    if !local.isMutable, resolvedType != sema.types.errorType {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0014",
                            "Val cannot be reassigned.",
                            range: range
                        )
                    }
                    return resolvedType == sema.types.errorType ? resolvedType : sema.types.errorType
                }
                locals[name] = (local.type, local.symbol, local.isMutable, local.isInitialized)
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
            if !local.isMutable {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            }
            let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
            // Arithmetic compound assignment keeps the target's own numeric type
            // (BUG-015): demoting `Long`/`Double`/unsigned locals to `Int` here broke
            // later member resolution such as `longVar and 0xFFL`.
            let arithmeticResultType = numericCompoundAssignResultType(local.type, ctx: ctx)
            let resultType: TypeID = switch underlyingOp {
            case .add:
                if local.type == stringType || valueType == stringType {
                    stringType
                } else if local.type == charType, valueType == intType {
                    charType
                } else {
                    arithmeticResultType
                }
            case .subtract:
                if local.type == charType, valueType == intType {
                    charType
                } else {
                    arithmeticResultType
                }
            case .multiply, .divide, .modulo:
                arithmeticResultType
            default:
                local.type
            }
            locals[name] = (resultType, local.symbol, local.isMutable, local.isInitialized)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // Members declared on a supertype are never found by
        // `cachedScopeLookup`: a `ClassMemberScope`'s parent is the
        // enclosing *lexical* scope (file/package), not the superclass's
        // scope, so scope lookup never walks the inheritance chain. Plain
        // reads and simple `=` reassignment already resolve inherited
        // properties through the inheritance-aware `lookupMemberProperty`
        // (see resolveImplicitReceiverMember above); reuse it here so that
        // `inheritedField += 1` resolves the same member, taking priority
        // over lexically scope-visible candidates just like
        // inferNameRefExpr does for plain reads.
        var implicitReceiverMember: (symbol: SemanticSymbol, type: TypeID)?
        if let receiverType = ctx.implicitReceiverType,
           let member = driver.helpers.lookupMemberProperty(
               named: name,
               receiverType: sema.types.makeNonNullable(receiverType),
               sema: sema
           ),
           let memberSymbol = ctx.cachedSymbol(member.symbol)
        {
            implicitReceiverMember = (memberSymbol, member.type)
        }

        // Fall back to scope-visible property lookup for compound assignments
        // like `counter += 1` where `counter` is a top-level var or a member
        // property accessed via implicit receiver (inside a class/object
        // member function).
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, _) = ctx.filterByVisibility(dslFilteredIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        let scopeVisibleProperty = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package || (ctx.implicitReceiverType != nil
                && (parentSym.kind == .class || parentSym.kind == .object || parentSym.kind == .interface))
        })
        if let propSymbol = implicitReceiverMember?.symbol ?? scopeVisibleProperty {
            sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            if implicitReceiverMember != nil {
                sema.bindings.markImplicitReceiverMember(id, name: name)
            }
            let propType = implicitReceiverMember?.type ?? sema.symbols.propertyType(for: propSymbol.id) ?? sema.types.errorType
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: propType,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: true
            ) {
                if propSymbol.flags.contains(.mutable),
                   let binaryFallback = bindCompoundAssignmentOperatorCall(
                       exprID: id,
                       op: op,
                       receiverType: propType,
                       valueType: valueType,
                       range: range,
                       ctx: ctx,
                       requireUnitReturn: false,
                       emitDiagnostics: false,
                       bindCall: false
                   ),
                   binaryFallback != sema.types.errorType
                {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0302",
                        "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                return resolvedType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: propType,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: false
            ) {
                if resolvedType == sema.types.errorType || !propSymbol.flags.contains(.mutable) {
                    if !propSymbol.flags.contains(.mutable), resolvedType != sema.types.errorType {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0014",
                            "Val cannot be reassigned.",
                            range: range
                        )
                    }
                    return resolvedType == sema.types.errorType ? resolvedType : sema.types.errorType
                }
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
            if !propSymbol.flags.contains(.mutable) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            }
            let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
            let resultType: TypeID = switch underlyingOp {
            case .add:
                if propType == stringType || valueType == stringType {
                    stringType
                } else if propType == charType, valueType == intType {
                    charType
                } else {
                    intType
                }
            case .subtract:
                if propType == charType, valueType == intType {
                    charType
                } else {
                    intType
                }
            case .multiply, .divide, .modulo:
                intType
            default:
                propType
            }
            _ = resultType // top-level property type not updated in locals
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
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
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    /// Compound assignment through an explicit receiver, e.g. `obj.field += value`
    /// or `this.box.n += value`. Mirrors `inferCompoundAssignExpr`'s operator-overload
    /// resolution (`plusAssign` then binary-operator fallback) but resolves the
    /// left-hand side as a member property on `receiverExpr` instead of a bare name.
    func inferMemberCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        calleeName: InternedString,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)

        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        guard let propResult = driver.helpers.lookupMemberProperty(
            named: calleeName,
            receiverType: nonNullReceiver,
            sema: sema
        ) else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(interner.resolve(calleeName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
        let propType = propResult.type
        let propSymbol = sema.symbols.symbol(propResult.symbol)

        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: propType,
            valueType: valueType,
            range: range,
            ctx: ctx,
            requireUnitReturn: true
        ) {
            if propSymbol?.flags.contains(.mutable) == true,
               let binaryFallback = bindCompoundAssignmentOperatorCall(
                   exprID: id,
                   op: op,
                   receiverType: propType,
                   valueType: valueType,
                   range: range,
                   ctx: ctx,
                   requireUnitReturn: false,
                   emitDiagnostics: false,
                   bindCall: false
               ),
               binaryFallback != sema.types.errorType
            {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0302",
                    "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            return resolvedType
        }

        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: propType,
            valueType: valueType,
            range: range,
            ctx: ctx,
            requireUnitReturn: false
        ) {
            if resolvedType == sema.types.errorType || propSymbol?.flags.contains(.mutable) != true {
                if propSymbol?.flags.contains(.mutable) != true, resolvedType != sema.types.errorType {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0014",
                        "Val cannot be reassigned.",
                        range: range
                    )
                }
                return resolvedType == sema.types.errorType ? resolvedType : sema.types.errorType
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // Primitive/builtin fallback (Int/Char/String arithmetic via `kk_op_*` or
        // string concat at KIR-lowering time). Unlike a bare local, a property's
        // declared type doesn't get narrowed per-assignment, so there is nothing
        // to propagate back into `locals` here.
        if propSymbol?.flags.contains(.mutable) != true {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0014",
                "Val cannot be reassigned.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferNameRefExpr(
        _ id: ExprID,
        name: InternedString,
        nameRange: SourceRange?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if name == knownNames.null {
            sema.bindings.bindExprType(id, type: sema.types.nullableNothingType)
            return sema.types.nullableNothingType
        }
        if name == knownNames.thisName,
           let receiverType = ctx.implicitReceiverType
        {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        if let local = locals[name] {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: nameRange
                )
            }
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            // Propagate collection marks through variable references (P5-84).
            if sema.bindings.isCollectionSymbol(local.symbol) {
                sema.bindings.markCollectionExpr(id)
            }
            if sema.bindings.isRangeSymbol(local.symbol) {
                sema.bindings.markRangeExpr(id)
            }
            if sema.bindings.isCharRangeSymbol(local.symbol) {
                sema.bindings.markCharRangeExpr(id)
            }
            if sema.bindings.isUIntRangeSymbol(local.symbol) {
                sema.bindings.markUIntRangeExpr(id)
            }
            if sema.bindings.isULongRangeSymbol(local.symbol) {
                sema.bindings.markULongRangeExpr(id)
            }
            if sema.bindings.isFloatingPointRangeSymbol(local.symbol) {
                sema.bindings.markFloatingPointRangeExpr(id)
                if let elementType = sema.bindings.floatingPointRangeElementType(forSymbol: local.symbol) {
                    sema.bindings.bindFloatingPointRangeElementType(elementType, forExpr: id)
                }
            }
            if sema.bindings.isFlowSymbol(local.symbol) {
                sema.bindings.markFlowExpr(id)
                if let flowElementType = sema.bindings.flowElementType(forSymbol: local.symbol) {
                    sema.bindings.bindFlowElementType(flowElementType, forExpr: id)
                }
            }
            sema.bindings.bindExprType(id, type: local.type)
            return local.type
        }
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        // @DslMarker restriction: filter out candidates from outer receivers
        // that share a DslMarker annotation with the current implicit receiver.
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, initialInvisibleSyms) = ctx.filterByVisibility(dslFilteredIDs)
        var invisibleSyms = initialInvisibleSyms
        var candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if candidates.isEmpty {
            let nominalFallbackIDs = sema.symbols.lookupByShortName(name).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                switch symbol.kind {
                case .object, .class, .interface, .enumClass, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            let (visibleFallbackIDs, invisibleFallbackSyms) = ctx.filterByVisibility(nominalFallbackIDs)
            if !visibleFallbackIDs.isEmpty {
                candidates = visibleFallbackIDs.compactMap { ctx.cachedSymbol($0) }
            } else if invisibleSyms.isEmpty, !invisibleFallbackSyms.isEmpty {
                invisibleSyms = invisibleFallbackSyms
            }
        }
        if let receiverType = ctx.implicitReceiverType {
            let memberType = resolveImplicitReceiverMember(
                id: id,
                name: name,
                receiverType: receiverType,
                ctx: ctx,
                sema: sema,
                interner: interner,
                nameRange: nameRange,
                emitDiagnosticOnFailure: candidates.isEmpty && invisibleSyms.isEmpty && dslBlockedIDs.isEmpty
            )
            if let memberType, memberType != sema.types.errorType {
                return memberType
            }
            if candidates.isEmpty, memberType == sema.types.errorType {
                return sema.types.errorType
            }
        }
        if candidates.isEmpty, !dslBlockedIDs.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-DSLMARKER",
                "'@DslMarker' implicit access to '\(interner.resolve(name))' from outer receiver is restricted. Use explicit receiver.",
                range: nameRange
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if candidates.isEmpty {
            if let receiverType = ctx.implicitReceiverType,
               let result = driver.helpers.lookupMemberProperty(
                   named: name,
                   receiverType: sema.types.makeNonNullable(receiverType),
                   sema: sema
               )
            {
                sema.bindings.markImplicitReceiverMember(id, name: name)
                sema.bindings.bindIdentifier(id, symbol: result.symbol)
                driver.helpers.checkDeprecation(
                    for: result.symbol,
                    sema: sema,
                    interner: interner,
                    range: nameRange,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                driver.helpers.checkOptIn(
                    for: result.symbol,
                    ctx: ctx,
                    range: nameRange,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: result.type)
                return result.type
            } else if let firstInvisible = invisibleSyms.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(name), range: nameRange, diagnostics: ctx.semaCtx.diagnostics)
            } else if name == knownNames.field {
                // Kotlin's `field` identifier is only valid inside property
                // getter/setter bodies where it refers to the backing field.
                // Emit a targeted diagnostic instead of the generic
                // "Unresolved reference" error.
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-FIELD",
                    "'field' can only be used inside a property getter or setter body.",
                    range: nameRange
                )
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0022",
                    "Unresolved reference '\(interner.resolve(name))'.",
                    range: nameRange
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let preferredCandidate = candidates.first(where: { symbol in
            switch symbol.kind {
            case .property, .field, .backingField, .object, .class, .interface, .enumClass:
                true
            default:
                false
            }
        }) ?? candidates.first
        if let preferredCandidate {
            sema.bindings.bindIdentifier(id, symbol: preferredCandidate.id)
            // ANNO-001: Check for @Deprecated annotation on the resolved symbol.
            driver.helpers.checkDeprecation(
                for: preferredCandidate.id,
                sema: sema,
                interner: interner,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: preferredCandidate.id,
                ctx: ctx,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            // DEBT-SEMA-003: a property's initializer referencing the property's
            // own symbol reads it before it has ever been assigned a value.
            if let initializingPropertySymbol = ctx.initializingPropertySymbol,
               preferredCandidate.id == initializingPropertySymbol
            {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: nameRange
                )
            }
        }
        let resolvedType = preferredCandidate.flatMap {
            resolveTypeForCandidate($0, sema: sema)
        } ?? sema.types.anyType
        // Propagate compile-time constant value for `const val` references
        // so downstream passes can fold without re-querying the symbol table.
        if let preferredCandidate, preferredCandidate.flags.contains(.constValue),
           let constKind = sema.symbols.constValueExprKind(for: preferredCandidate.id)
        {
            sema.bindings.bindConstExprValue(id, value: constKind)
        }
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    private func resolveImplicitReceiverMember(
        id: ExprID,
        name: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner,
        nameRange: SourceRange?,
        emitDiagnosticOnFailure: Bool = true
    ) -> TypeID? {
        // STDLIB-004: Inside receiver lambdas (run/apply/with), bare name
        // references resolve as properties on the implicit receiver (this).
        let knownNames = KnownCompilerNames(interner: interner)
        let resolvedName = interner.resolve(name)
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        var implicitMemberType: TypeID?
        if sema.types.isSubtype(nonNullReceiver, sema.types.stringType), resolvedName == "length" {
            implicitMemberType = sema.types.intType
        }
        if implicitMemberType == nil, name == knownNames.size || name == knownNames.isEmpty,
           let (_, symbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema),
           knownNames.collectionKind(of: symbol) != nil
        {
            implicitMemberType = name == knownNames.size
                ? sema.types.intType
                : sema.types.make(.primitive(.boolean, .nonNull))
        }
        if implicitMemberType == nil,
           let result = driver.helpers.lookupMemberProperty(named: name, receiverType: nonNullReceiver, sema: sema)
        {
            sema.bindings.markImplicitReceiverMember(id, name: name)
            sema.bindings.bindIdentifier(id, symbol: result.symbol)
            driver.helpers.checkDeprecation(
                for: result.symbol, sema: sema, interner: interner,
                range: nameRange, diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: result.symbol,
                ctx: ctx,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindExprType(id, type: result.type)
            return result.type
        }
        if let memberType = implicitMemberType {
            sema.bindings.markImplicitReceiverMember(id, name: name)
            sema.bindings.bindExprType(id, type: memberType)
            return memberType
        }
        if emitDiagnosticOnFailure {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(resolvedName)'.",
                range: nameRange
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        return nil
    }

    private func resolveTypeForCandidate(_ symbol: SemanticSymbol, sema: SemaModule) -> TypeID? {
        if let signature = sema.symbols.functionSignature(for: symbol.id) {
            return signature.returnType
        }
        if symbol.kind == .property || symbol.kind == .field {
            return sema.symbols.propertyType(for: symbol.id)
        }
        // Objects are singletons – always resolve to their nominal type so
        // that `ObjectName.member()` works.
        if symbol.kind == .object {
            // Unit keeps its builtin value representation while retaining a
            // source-backed object symbol for member dispatch.
            if symbol.id == sema.types.unitClassSymbol {
                return sema.types.unitType
            }
            if let objectType = sema.symbols.propertyType(for: symbol.id) {
                return objectType
            }
            return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
        }
        // For class/interface/enum symbols, only resolve to nominal type when
        // they have a companion object so that `ClassName.companionMember()`
        // can resolve.  Without a companion, keep the previous anyType
        // fallback so that `ClassName.instanceMethod()` correctly errors.
        if symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass,
           sema.symbols.companionObjectSymbol(for: symbol.id) != nil
        {
            return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
        }
        return nil
    }

    private func describe(_ type: TypeID, ctx: TypeInferenceContext) -> String {
        ctx.sema.types.displayName(of: type, symbols: ctx.sema.symbols, interner: ctx.interner)
    }

    /// Whether an explicit lambda parameter annotation agrees with the parameter
    /// type the expected type declares. Type parameters the expected type leaves
    /// unsubstituted carry no information, so annotations always win there.
    /// Otherwise only widening is allowed (function types are contravariant in
    /// their parameters): `(String) -> Int = { s: Any -> ... }` is fine, while
    /// `(Any) -> Int = { s: String -> ... }` is a mismatch.
    ///
    /// `expectedTypeIsSourceDeclared` tells the two kinds of `Any` apart: an
    /// `Any` written in source constrains the annotation, while an `Any` the
    /// compiler synthesized for a call whose type variable stayed unsolved
    /// (`Grouping<K, E>`'s accumulator) carries no information.
    func lambdaAnnotationIsCompatible(
        annotated: TypeID,
        declared: TypeID,
        expectedTypeIsSourceDeclared: Bool,
        sema: SemaModule
    ) -> Bool {
        if annotated == declared || declared == sema.types.errorType || annotated == sema.types.errorType {
            return true
        }
        if typeMentionsTypeParameter(declared, sema: sema) {
            return true
        }
        if !expectedTypeIsSourceDeclared, case .any = sema.types.kind(of: declared) {
            return true
        }
        return sema.types.isSubtype(declared, annotated)
    }

    private func typeMentionsTypeParameter(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .typeParam:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return typeMentionsTypeParameter(inner, sema: sema)
                case .star:
                    return false
                }
            }
        case let .functionType(functionType):
            return functionType.params.contains { typeMentionsTypeParameter($0, sema: sema) }
                || typeMentionsTypeParameter(functionType.returnType, sema: sema)
                || (functionType.receiver.map { typeMentionsTypeParameter($0, sema: sema) } ?? false)
        case let .intersection(members):
            return members.contains { typeMentionsTypeParameter($0, sema: sema) }
        default:
            return false
        }
    }

    private func typeParameterSymbols(in type: TypeID, sema: SemaModule) -> Set<SymbolID> {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case let .typeParam(typeParam):
            return [typeParam.symbol]
        case let .classType(classType):
            return classType.args.reduce(into: Set<SymbolID>()) { symbols, argument in
                switch argument {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    symbols.formUnion(typeParameterSymbols(in: inner, sema: sema))
                case .star:
                    break
                }
            }
        case let .functionType(functionType):
            var symbols = Set<SymbolID>()
            for receiver in functionType.contextReceivers {
                symbols.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            if let receiver = functionType.receiver {
                symbols.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            for parameter in functionType.params {
                symbols.formUnion(typeParameterSymbols(in: parameter, sema: sema))
            }
            symbols.formUnion(typeParameterSymbols(in: functionType.returnType, sema: sema))
            return symbols
        case let .kClassType(kClassType):
            return typeParameterSymbols(in: kClassType.argument, sema: sema)
        case let .intersection(members):
            return members.reduce(into: Set<SymbolID>()) { symbols, member in
                symbols.formUnion(typeParameterSymbols(in: member, sema: sema))
            }
        default:
            return []
        }
    }

    /// Resolves the explicit parameter type annotations recorded for a lambda
    /// literal (`{ a: Int, b: String -> ... }`). Returns nil when the lambda has
    /// no annotations or the recorded arity does not match the parameter list.
    func resolveLambdaParamAnnotations(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        paramCount: Int
    ) -> [TypeID?]? {
        let sema = ctx.sema
        guard let typeRefs = ctx.ast.arena.lambdaParamTypeRefs(for: id),
              typeRefs.count == paramCount
        else {
            return nil
        }
        var resolved: [TypeID?] = []
        resolved.reserveCapacity(typeRefs.count)
        for typeRef in typeRefs {
            guard let typeRef else {
                resolved.append(nil)
                continue
            }
            let type = driver.helpers.resolveTypeRef(
                typeRef,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope,
                inferenceContext: ctx
            )
            resolved.append(type == sema.types.errorType ? nil : type)
        }
        return resolved.contains(where: { $0 != nil }) ? resolved : nil
    }

    func inferLambdaLiteralExpr(
        _ id: ExprID,
        params: [InternedString],
        body: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema

        let label: InternedString? = if case let .lambdaLiteral(_, _, lbl, _) = ast.arena.expr(id) { lbl } else { nil }
        // SAM conversion: when the expected type is a functional interface,
        // extract the SAM method's function type so the lambda's parameters
        // and return type can be inferred from it.
        let samConversion: Bool
        let expectedFunctionType: FunctionType?
        if let expectedType, case let .functionType(functionType) = sema.types.kind(of: expectedType) {
            expectedFunctionType = functionType
            samConversion = false
        } else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
            expectedFunctionType = samFT
            samConversion = true
        } else {
            expectedFunctionType = nil
            samConversion = false
        }

        var lambdaLocals = locals
        let outerSymbols = Set(locals.values.map(\.symbol))
        let inferredImplicitItType = params.isEmpty
            ? inferItParameterType(ctx: ctx, id: id, sema: sema)
            : nil

        // Implicit `it` parameter for no-arrow lambdas with single expected param.
        // Enhanced to support complex type inference contexts and generic types.
        let effectiveParams: [InternedString] = if params.isEmpty {
            // Check for expected function type first
            if let expectedFunctionType, expectedFunctionType.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            // Check for SAM conversion with single parameter method
            else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
                    samFT.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            // Check for common HOF patterns (map, filter, etc.) through context
            else if inferredImplicitItType != nil {
                [ctx.interner.intern("it")]
            } else {
                params
            }
        } else {
            params
        }

        // Parameter types the expected type actually declares, as opposed to the
        // `Any` fallback below; only these can contradict an explicit annotation.
        let declaredParameterTypes: [TypeID]? = {
            if let expectedFunctionType, expectedFunctionType.params.count == effectiveParams.count {
                return expectedFunctionType.params
            }
            if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
               samFT.params.count == effectiveParams.count
            {
                return samFT.params
            }
            return nil
        }()
        let expectedParameterTypes: [TypeID] = if let declaredParameterTypes {
            declaredParameterTypes
        } else if effectiveParams.count == 1 && effectiveParams.contains(ctx.interner.intern("it")) {
            // For implicit `it` parameter, try to infer type from context
            inferredImplicitItType.map { [$0] }
                ?? Array(repeating: sema.types.anyType, count: effectiveParams.count)
        } else {
            Array(repeating: sema.types.anyType, count: effectiveParams.count)
        }
        // Explicit `{ a: Int -> ... }` annotations win over the expected type's
        // parameter types, which may be unsubstituted type parameters when the
        // expected type is a raw functional interface (BUG-046). An annotation
        // that contradicts a concrete expected parameter type is an error.
        let annotatedParameterTypes = resolveLambdaParamAnnotations(id, ctx: ctx, paramCount: effectiveParams.count)
        let expectedTypeIsSourceDeclared = sema.bindings.hasSourceDeclaredExpectedType(id)
        let parameterTypes: [TypeID] = effectiveParams.indices.map { offset in
            let fallback = offset < expectedParameterTypes.count ? expectedParameterTypes[offset] : sema.types.anyType
            guard let annotated = annotatedParameterTypes?[offset] else {
                return fallback
            }
            guard let declared = declaredParameterTypes?[offset] else {
                return annotated
            }
            if lambdaAnnotationIsCompatible(
                annotated: annotated,
                declared: declared,
                expectedTypeIsSourceDeclared: expectedTypeIsSourceDeclared,
                sema: sema
            ) {
                return annotated
            }
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0025",
                "Lambda parameter '\(ctx.interner.resolve(effectiveParams[offset]))' is declared as "
                    + "'\(describe(annotated, ctx: ctx))' but '\(describe(declared, ctx: ctx))' is expected.",
                range: ast.arena.exprRange(id)
            )
            return declared
        }
        for (offset, param) in effectiveParams.enumerated() {
            let syntheticSymbol = SymbolID(rawValue: Int32(clamping: Int64(-1_000_000) - Int64(id.rawValue) * 256 - Int64(offset)))
            let parameterType = parameterTypes[offset]
            lambdaLocals[param] = (
                type: parameterType,
                symbol: syntheticSymbol,
                isMutable: false,
                isInitialized: true
            )
        }

        var bodyCtx: TypeInferenceContext = if let label {
            ctx.withLambdaLabel(label)
        } else {
            ctx
        }
        bodyCtx = bodyCtx.enteringLambdaBody()
        // When the expected function type has a receiver (e.g. StringBuilder.() -> Unit),
        // set the implicit receiver so that unqualified member calls resolve correctly.
        if let receiverType = expectedFunctionType?.receiver {
            bodyCtx = bodyCtx.with(implicitReceiverType: receiverType)
        }
        if let expectedFunctionType, !expectedFunctionType.contextReceivers.isEmpty {
            bodyCtx = bodyCtx.with(
                contextReceiverTypes: ctx.contextReceiverTypes + expectedFunctionType.contextReceivers
            )
        }
        let expectedReturnHasUnresolvedOutputTypeParameter: Bool = {
            guard let expectedFunctionType else {
                return false
            }
            let returnTypeParameters = typeParameterSymbols(in: expectedFunctionType.returnType, sema: sema)
            guard !returnTypeParameters.isEmpty else {
                return false
            }
            var inputTypeParameters = Set<SymbolID>()
            for receiver in expectedFunctionType.contextReceivers {
                inputTypeParameters.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            if let receiver = expectedFunctionType.receiver {
                inputTypeParameters.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            for parameter in expectedFunctionType.params {
                inputTypeParameters.formUnion(typeParameterSymbols(in: parameter, sema: sema))
            }
            return !returnTypeParameters.subtracting(inputTypeParameters).isEmpty
        }()
        // Kotlin discards a Unit-expected lambda body's value rather than requiring
        // it to actually type as Unit (e.g. `repeat(3) { i -> someIntCall(i) }`).
        // Passing Unit down as the body's expectedType would incorrectly propagate
        // into the body's own call resolution -- e.g. rejecting `addOne(i): Int` as
        // "no viable overload" because Int isn't a subtype of the pushed-down Unit.
        // Only push the expected return type down when it isn't Unit. An unresolved
        // type parameter (the `T` of `fun <T> f(action: () -> T): T`) is treated the
        // same way: it cannot constrain the body's own resolution, and pushing it
        // down makes a Unit-valued body (e.g. `{ println() }`) fail to type-check.
        // The same applies when the unresolved output parameter is nested inside
        // a contextual return type such as `List<R>`. It is free at this call site
        // when it does not occur in the lambda's receiver or input parameters;
        // the concrete body result must infer it instead of being checked against
        // an outer placeholder.
        // Leaving it out lets the body infer its natural type so the caller can solve
        // the type variable from it.
        let bodyExpectedType: TypeID? = {
            guard let expectedReturnType = expectedFunctionType?.returnType,
                  expectedReturnType != sema.types.unitType else {
                return nil
            }
            if case .typeParam = sema.types.kind(of: expectedReturnType) {
                return nil
            }
            if expectedReturnHasUnresolvedOutputTypeParameter {
                return nil
            }
            return expectedReturnType
        }()
        let inferredBodyType = driver.inferExpr(
            body,
            ctx: bodyCtx,
            locals: &lambdaLocals,
            expectedType: bodyExpectedType
        )
        let captures = driver.captureAnalyzer.collectCapturedOuterSymbols(
            in: body,
            ast: ast,
            sema: sema,
            outerSymbols: outerSymbols
        )
        sema.bindings.bindCaptureSymbols(id, symbols: captures)

        // SAM conversion: bind the lambda to the interface type, but also
        // store the underlying function type so KIR lowering can generate
        // the correct callable.
        if samConversion, let expectedType, let expectedFunctionType {
            driver.emitSubtypeConstraint(
                left: inferredBodyType,
                right: expectedFunctionType.returnType,
                range: ast.arena.exprRange(body),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.markSamConversion(id)
            let underlyingFuncType = sema.types.make(.functionType(expectedFunctionType))
            sema.bindings.bindSamUnderlyingFunctionType(id, type: underlyingFuncType)
            sema.bindings.bindExprType(id, type: expectedType)
            return expectedType
        }

        if let expectedType, let expectedFunctionType {
            // Enhanced return type inference with Unit optimization
            let optimizedReturnType = inferOptimizedReturnType(
                inferredBodyType: inferredBodyType,
                expectedReturnType: expectedFunctionType.returnType,
                bodyExpr: body,
                ast: ast,
                sema: sema
            )

            // Skip the local subtype constraint when the expected return is Unit
            // (Kotlin allows any body type) or when it is a generic type variable.
            // For Unit there is nothing to constrain. For a type variable the
            // local solver cannot bind it; the concrete inferred function type
            // returned below lets the call resolver infer it instead.
            let expectedReturnIsTypeParam: Bool = {
                guard case .typeParam = sema.types.kind(of: expectedFunctionType.returnType) else {
                    return false
                }
                return true
            }()
            // A bounded type parameter (`fun <R : Any> f(g: () -> R)`) cannot be
            // constrained locally either — `Int <: R` is never satisfiable while
            // `R` is still a placeholder, and the upper bound is verified by the
            // overload resolver once `R` is inferred (`checkTypeParameterBounds`).
            let shouldSkipSubtypeConstraint =
                expectedFunctionType.returnType == sema.types.unitType
                || expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
            if !shouldSkipSubtypeConstraint {
                driver.emitSubtypeConstraint(
                    left: optimizedReturnType,
                    right: expectedFunctionType.returnType,
                    range: ast.arena.exprRange(body),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            // When the expected return type is an unresolved type parameter,
            // returning `expectedType` verbatim leaks that type variable back
            // out as the lambda's own type. The overload resolver then
            // decomposes it against the same signature's parameter type and
            // produces a self-referential `T <: T` bound instead of a real
            // constraint derived from the body's actual type (e.g. `lazy { 1 }`
            // or `box.run2 { myValue }` fails to infer `R`). Substitute the
            // concrete, inferred return type in those cases so the caller can
            // solve the type parameter from it.
            let shouldReturnResolvedFunctionType = expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
            let resultType: TypeID = if shouldReturnResolvedFunctionType {
                sema.types.make(.functionType(FunctionType(
                    contextReceivers: expectedFunctionType.contextReceivers,
                    receiver: expectedFunctionType.receiver,
                    params: parameterTypes,
                    returnType: optimizedReturnType,
                    isSuspend: expectedFunctionType.isSuspend,
                    nullability: expectedFunctionType.nullability,
                    throws: expectedFunctionType.throws
                )))
            } else {
                expectedType
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        let inferredFunctionType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: inferredBodyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        sema.bindings.bindExprType(id, type: inferredFunctionType)
        return inferredFunctionType
    }

    func inferCallableRefExpr(
        _ id: ExprID,
        receiver: ExprID?,
        member: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let outerSymbols = Set(locals.values.map(\.symbol))

        // ── T::class  — reified type-parameter class reference ──────────
        if member == KnownCompilerNames(interner: interner).className,
           let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver)
        {
            if let result = inferClassRefExpr(
                id, receiver: receiver, receiverName: receiverName,
                range: range, ctx: ctx, locals: &locals
            ) {
                return result
            }
        }

        // ── this::class — instance class reference on implicit receiver ──
        // REFL-002: When the receiver is `this`, infer `this` first, then
        // bind the classRefTargetType from the receiver's resolved type so
        // KIR lowering can emit `__kk_kclass_create` with the correct token.
        if member == KnownCompilerNames(interner: interner).className,
           let receiver,
           case .thisRef = ast.arena.expr(receiver)
        {
            if let result = inferExprReceiverClassRef(
                id, receiver: receiver, ctx: ctx, locals: &locals
            ) {
                return result
            }
        }

        // ── REFL-003: Type::member — unbound callable reference ─────────
        // When the receiver is a name that refers to a class/interface/enum
        // (not an instance variable), treat it as an unbound member reference.
        // The resulting function type includes the receiver type as the
        // first parameter: `Type::method` becomes `(Type) -> ReturnType`.
        var unboundClassType: TypeID?
        if let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver)
        {
            // Check locals first — if there's a local variable with this
            // name, it's a bound reference, not an unbound type reference.
            if locals[receiverName] == nil {
                let allCandidateIDs = ctx.cachedScopeLookup(receiverName)
                for candidateID in allCandidateIDs {
                    guard let sym = ctx.cachedSymbol(candidateID),
                          sym.kind == .class || sym.kind == .interface
                          || sym.kind == .enumClass
                    else { continue }
                    unboundClassType = sema.types.make(
                        .classType(ClassType(classSymbol: sym.id, args: [], nullability: .nonNull))
                    )
                    break
                }
            }
        }

        let receiverType: TypeID? = if let receiver {
            driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        } else {
            nil
        }

        // For unbound type references, use the resolved class type for
        // member lookup instead of the expression-inferred type (which
        // may degrade to Any for classes without companion objects).
        let effectiveReceiverType = unboundClassType ?? receiverType

        var candidates: [SymbolID] = []
        if let effectiveReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(effectiveReceiverType)
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: member,
                receiverType: nonNullReceiver,
                sema: sema,
                interner: interner
            )
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
            } else {
                if let (_, owner) = resolveClassTypeSymbol(nonNullReceiver, sema: sema)
                {
                    let propertyCandidates = sema.symbols.lookupAll(
                        fqName: owner.fqName + [member]
                    ).filter { symbolID in
                        guard let symbol = ctx.cachedSymbol(symbolID) else {
                            return false
                        }
                        return symbol.kind == .property || symbol.kind == .field
                    }
                    if let propertySymbol = propertyCandidates.first {
                        let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.errorType
                        let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
                        let ownerTypeForReference = unboundClassType != nil ? nonNullReceiver : nil
                        let inferredType = kPropertyReferenceType(
                            ownerType: ownerTypeForReference,
                            valueType: propertyType,
                            isMutable: isMutable,
                            sema: sema,
                            interner: interner
                        ) ?? propertyType
                        let resultType = resolvedPropertyReferenceResultType(
                            expectedType: expectedType,
                            inferredType: inferredType,
                            sema: sema,
                            interner: interner
                        )
                        sema.bindings.bindIdentifier(id, symbol: propertySymbol)
                        sema.bindings.bindCallableTarget(id, target: .symbol(propertySymbol))
                        sema.bindings.bindCallableRefKind(id, kind: .propertyRef)
                        if unboundClassType != nil {
                            sema.bindings.markUnboundCallableRef(id)
                        }
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
                candidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    guard let symbol = ctx.cachedSymbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let declaredReceiver = signature.receiverType
                    else {
                        return false
                    }
                    return sema.types.isSubtype(nonNullReceiver, declaredReceiver)
                }
            }
        } else {
            let propertyCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else {
                    return false
                }
                return symbol.kind == .property
            }
            if let propertySymbol = propertyCandidates.first {
                let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.errorType
                let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
                // KSP-496/KSP-505: a bare `::member` reference to a member
                // property of the enclosing class or singleton is implicitly
                // bound to `this`. For `.class` owners the receiver is a
                // genuine instance captured by KIR lowering
                // (LambdaLowerer.isCaptureEligibleInstanceContainerSymbol).
                // For `.object` owners (companion objects, plain `object`s)
                // there is exactly one instance ever, stored in a
                // module-level global slot rather than a captured
                // per-instance field — so KIR lowering (see
                // LambdaLowerer+PropertyReferenceLowering.swift's
                // `ensurePropertyReferenceAccessor`) reads/writes that slot
                // directly and never needs a captured receiver at all.
                //
                // `.enumClass` stays excluded (kept on the pre-existing, safe
                // fallback), even though an *enum entry* is also a singleton:
                // a property declared directly in the enum class's own body
                // (e.g. a constructor-promoted `val`) is a genuine per-entry
                // *instance* field — each entry has its own value — not
                // shared global storage the way `.object` is. Confirmed by
                // testing: treating `.enumClass` the same as `.object` here
                // made `enum class E(val v: Int) { A(1), B(2) }`'s `::v`
                // read back `0` for every entry instead of each entry's own
                // value. A property declared inside one specific *entry's*
                // own body (`A { val x = 5 }`) might be a distinct, safely
                // includable case — its owner could plausibly be that
                // entry's own synthesized subclass rather than `.enumClass`
                // itself — but this could not be verified: referencing an
                // entry with a body at all (`EnumClass.ENTRY`) hits a
                // separate, pre-existing, unrelated bug (see
                // docs/diff-skip-inventory.md's `enum_edge_cases.kt` entry).
                // `.interface` stays excluded here too: interface-owned
                // properties have no storage of their own (always dispatched
                // through whichever class implements them), which this
                // bare-reference path does not handle yet.
                let ownerKind = sema.symbols.parentSymbol(for: propertySymbol)
                    .flatMap { sema.symbols.symbol($0)?.kind }
                let resultType: TypeID
                if let ownerKind, ownerKind != .class, ownerKind != .object {
                    resultType = propertyType
                } else {
                    let inferredType = kPropertyReferenceType(
                        ownerType: nil,
                        valueType: propertyType,
                        isMutable: isMutable,
                        sema: sema,
                        interner: interner
                    ) ?? propertyType
                    resultType = resolvedPropertyReferenceResultType(
                        expectedType: expectedType,
                        inferredType: inferredType,
                        sema: sema,
                        interner: interner
                    )
                }
                sema.bindings.bindIdentifier(id, symbol: propertySymbol)
                sema.bindings.bindCallableRefKind(id, kind: .propertyRef)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            candidates = ctx.cachedScopeLookup(member).filter { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            if candidates.isEmpty,
               let local = locals[member],
               let localSymbol = ctx.cachedSymbol(local.symbol),
               localSymbol.kind == .function
            {
                candidates = [local.symbol]
            }
        }

        // For unbound type references (Type::member), the receiver is not
        // bound — it becomes a parameter of the function type.  For bound
        // references (obj::member), the receiver is captured.
        let isBoundReceiver = receiver != nil && unboundClassType == nil

        // BUG-164: callable references must also support SAM-conversion to a
        // functional interface expected type, the same way lambda literals do.
        let expectedFunctionType: TypeID?
        let expectedSamInterfaceType: TypeID?
        if let expectedType {
            if case .functionType = sema.types.kind(of: expectedType) {
                expectedFunctionType = expectedType
                expectedSamInterfaceType = nil
            } else if let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
                expectedFunctionType = sema.types.make(.functionType(samFT))
                expectedSamInterfaceType = expectedType
            } else {
                expectedFunctionType = nil
                expectedSamInterfaceType = nil
            }
        } else {
            expectedFunctionType = nil
            expectedSamInterfaceType = nil
        }

        let chosen = driver.helpers.chooseCallableReferenceTarget(
            from: candidates,
            expectedType: expectedFunctionType,
            bindReceiver: isBoundReceiver,
            sema: sema
        )

        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen)
        {
            let inferredType = driver.helpers.callableFunctionType(
                for: signature,
                bindReceiver: isBoundReceiver,
                sema: sema
            )
            let resultType: TypeID
            // An expected type that still mentions type parameters belongs to a
            // generic signature whose type arguments are inferred from this very
            // argument (`fun <T> runCatching(block: () -> T)`). Checking against
            // it would fail, and adopting it would hide the concrete type the
            // caller needs for inference, so report the reference's own type.
            if let expectedFunctionType {
                let concreteResult = expectedSamInterfaceType ?? expectedFunctionType
                if !sema.types.typeContainsAnyTypeParam(concreteResult) {
                    driver.emitSubtypeConstraint(
                        left: inferredType,
                        right: expectedFunctionType,
                        range: range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    resultType = concreteResult
                } else {
                    resultType = inferredType
                }

            } else {
                resultType = inferredType
            }
            // BUG-164: A callable reference passed to a fun-interface parameter
            // must be SAM-converted and bound to the interface type, not left as a
            // bare function type.  `lowerCallableRefExpr` checks `isSamConversion`
            // and emits the wrapper object that makes interface dispatch work.
            // Only perform the conversion when the resolved result is the concrete
            // interface type; if the expected type still contains type parameters,
            // leave the reference as a function value so generic inference can
            // substitute a concrete instantiation later.
            if let expectedSamInterfaceType,
               resultType == expectedSamInterfaceType
            {
                sema.bindings.markSamConversion(id)
                sema.bindings.bindSamInterfaceType(id, type: expectedSamInterfaceType)
                sema.bindings.bindSamUnderlyingFunctionType(id, type: expectedFunctionType ?? inferredType)
            }
            sema.bindings.bindIdentifier(id, symbol: chosen)
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            // REFL-003: Tag the callable reference as KFunction so KIR
            // lowering can emit type identity metadata.
            sema.bindings.bindCallableRefKind(id, kind: .functionRef)
            if unboundClassType != nil {
                sema.bindings.markUnboundCallableRef(id)
            }
            let captures = receiver.map { recv in
                driver.captureAnalyzer.collectCapturedOuterSymbols(
                    in: recv,
                    ast: ast,
                    sema: sema,
                    outerSymbols: outerSymbols
                )
            } ?? []
            sema.bindings.bindCaptureSymbols(id, symbols: captures)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        if candidates.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '::\(interner.resolve(member))'.",
                range: range
            )
        }
        let fallbackType: TypeID = if let expectedType,
                                      case .functionType = sema.types.kind(of: expectedType)
        {
            expectedType
        } else if candidates.isEmpty {
            sema.types.errorType
        } else {
            sema.types.anyType
        }
        let fallbackCaptures = receiver.map { recv in
            driver.captureAnalyzer.collectCapturedOuterSymbols(
                in: recv,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols
            )
        } ?? []
        sema.bindings.bindCaptureSymbols(id, symbols: fallbackCaptures)
        sema.bindings.bindExprType(id, type: fallbackType)
        return fallbackType
    }

    /// Builds the concrete `KProperty0<V>` / `KMutableProperty0<V>` /
    /// `KProperty1<Owner, V>` / `KMutableProperty1<Owner, V>` type for a plain
    /// property callable reference (`Type::property`, `instance::property`, or
    /// bare `::property`), so a reference used without an expected type (e.g.
    /// `val ref = C::v`, or as an argument whose parameter type is itself
    /// inferred, like `listOf(C::v)`) still gets a real KProperty-conforming
    /// type instead of degrading to the property's own value type.
    ///
    /// `ownerType` is `nil` for a bound (`instance::property`) or top-level
    /// (bare `::property`) reference (arity 0: `KProperty0`/`KMutableProperty0`),
    /// and the receiver's class type for an unbound (`Type::property`)
    /// reference (arity 1: `KProperty1`/`KMutableProperty1`).
    ///
    /// Returns `nil` when the interface symbol isn't registered (e.g.
    /// `kotlin.reflect` wasn't injected), in which case callers should keep
    /// their previous fallback behavior.
    private func kPropertyReferenceType(
        ownerType: TypeID?,
        valueType: TypeID,
        isMutable: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        let interfaceName: String
        let typeArgs: [TypeArg]
        if let ownerType {
            interfaceName = isMutable ? "KMutableProperty1" : "KProperty1"
            typeArgs = [.invariant(ownerType), .invariant(valueType)]
        } else {
            interfaceName = isMutable ? "KMutableProperty0" : "KProperty0"
            typeArgs = [.invariant(valueType)]
        }
        guard let interfaceSymbol = sema.symbols.lookup(fqName: reflectPkg + [interner.intern(interfaceName)]) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: typeArgs,
            nullability: .nonNull
        )))
    }

    /// Decides the expression type for a property callable reference.
    ///
    /// A property reference is also a valid function value — Kotlin allows
    /// `list.map(Person::name)` or `val f: (Person) -> String = Person::name`
    /// — so an `expectedType` that is a function type (or SAM-convertible
    /// interface) is always trusted as-is, exactly like before this fix and
    /// exactly like the sibling function-reference branch above.
    ///
    /// Otherwise, `expectedType` is only trusted when it is itself one of the
    /// four concrete KProperty shapes (`KProperty0`/`KMutableProperty0`/
    /// `KProperty1`/`KMutableProperty1`) — the same set
    /// `propertyReferenceShape` in `LambdaLowerer+PropertyReferenceLowering.swift`
    /// recognizes to build the real KIR wrapper object. A broader or unrelated
    /// expected type (`Any`, `KProperty<*>`, `KCallable<*>`, ...) would
    /// silently defeat that wrapper and fall back to a non-conforming legacy
    /// value, so `inferredType` (the correct concrete shape this reference
    /// actually has) is used instead in that case.
    private func resolvedPropertyReferenceResultType(
        expectedType: TypeID?,
        inferredType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let expectedType else {
            return inferredType
        }
        if case .functionType = sema.types.kind(of: expectedType) {
            return expectedType
        }
        if driver.helpers.samFunctionType(for: expectedType, sema: sema) != nil {
            return expectedType
        }
        guard isConcreteKPropertyReferenceShape(expectedType, sema: sema, interner: interner) else {
            return inferredType
        }
        return expectedType
    }

    private func isConcreteKPropertyReferenceShape(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        switch interner.resolve(symbol.name) {
        case "KProperty0", "KMutableProperty0", "KProperty1", "KMutableProperty1":
            return true
        default:
            return false
        }
    }

    private func inferClassRefExpr(
        _ id: ExprID,
        receiver: ExprID,
        receiverName: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let allCandidateIDs = ctx.cachedScopeLookup(receiverName)
        for candidateID in allCandidateIDs {
            guard let sym = ctx.cachedSymbol(candidateID),
                  sym.kind == .typeParameter else { continue }
            if !sym.flags.contains(.reifiedTypeParameter) {
                let name = interner.resolve(sym.name)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-REIFIED",
                    "Cannot use 'T::class' on non-reified type parameter '\(name)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let resolved = sema.types.make(.typeParam(TypeParamType(symbol: sym.id)))
            sema.bindings.bindClassRefTargetType(id, type: resolved)
            let kClassType = sema.types.makeKClassType(argument: resolved)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        for candidateID in allCandidateIDs {
            guard let sym = ctx.cachedSymbol(candidateID),
                  sym.kind == .class || sym.kind == .interface
                  || sym.kind == .object || sym.kind == .enumClass
            else { continue }
            let classType = sema.types.make(.classType(ClassType(classSymbol: sym.id)))
            sema.bindings.bindClassRefTargetType(id, type: classType)
            let kClassType = sema.types.makeKClassType(argument: classType)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        // REFL-002: Handle builtin/primitive type names (Int, String, Boolean, etc.)
        // These are not class symbols in the symbol table but still support ::class.
        let builtinNames = driver.builtinTypeNamesCache
        if let builtinType = builtinNames.resolveBuiltinType(receiverName, types: sema.types) {
            sema.bindings.bindClassRefTargetType(id, type: builtinType)
            let kClassType = sema.types.makeKClassType(argument: builtinType)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        return nil
    }

    /// REFL-002: Infers `::class` when the receiver is an expression (e.g. `this::class`).
    /// Infers the receiver first, then derives the `classRefTargetType` from the
    /// receiver's resolved type so KIR lowering emits the correct type token.
    private func inferExprReceiverClassRef(
        _ id: ExprID,
        receiver: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let receiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)

        // Skip error types — don't bind a classRef for unresolvable receivers.
        if nonNullReceiverType == sema.types.errorType {
            return nil
        }

        // Resolve the nominal type from the receiver.  For class/interface
        // types we use the type directly; for primitives we also accept them.
        let targetType: TypeID
        switch sema.types.kind(of: nonNullReceiverType) {
        case .classType, .primitive, .any:
            targetType = nonNullReceiverType
        default:
            return nil
        }

        sema.bindings.bindClassRefTargetType(id, type: targetType)
        let kClassType = sema.types.makeKClassType(argument: targetType)
        sema.bindings.bindExprType(id, type: kClassType)
        return kClassType
    }

    func inferSuperRefExpr(
        _ id: ExprID,
        interfaceQualifier: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0050",
                "'super' is not allowed outside of a class body.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let classSymbol = driver.helpers.nominalSymbol(of: receiverType, types: sema.types) else {
            return emitNoSuperclass(id: id, range: range, ctx: ctx)
        }
        if let qualifier = interfaceQualifier {
            return resolveQualifiedSuper(
                id: id, qualifier: qualifier, classSymbol: classSymbol, range: range, ctx: ctx
            )
        }
        return resolveUnqualifiedSuper(
            id: id, classSymbol: classSymbol, receiverType: receiverType, range: range, ctx: ctx
        )
    }

    /// Resolves `super<T>` — only direct supertypes (interfaces and classes) are valid per Kotlin spec.
    private func resolveQualifiedSuper(
        id: ExprID,
        qualifier: InternedString,
        classSymbol: SymbolID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let supertypes = sema.symbols.directSupertypes(for: classSymbol)
        for superID in supertypes {
            guard let superSym = ctx.cachedSymbol(superID) else { continue }
            let isValidKind = superSym.kind == .interface || superSym.kind == .class || superSym.kind == .enumClass
            if isValidKind, superSym.name == qualifier {
                let ifaceType = sema.types.make(.classType(ClassType(classSymbol: superID)))
                sema.bindings.bindExprType(id, type: ifaceType)
                return ifaceType
            }
        }
        let qualifierStr = ctx.interner.resolve(qualifier)
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0054",
            "No type '\(qualifierStr)' found in direct supertypes for qualified 'super'.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    private func resolveUnqualifiedSuper(
        id: ExprID,
        classSymbol: SymbolID,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let supertypes = sema.symbols.directSupertypes(for: classSymbol)
        let classSupertypes = supertypes.filter {
            let kind = ctx.cachedSymbol($0)?.kind
            return kind == .class || kind == .enumClass
        }
        if let superclass = classSupertypes.first {
            let superType = sema.types.make(.classType(ClassType(classSymbol: superclass)))
            sema.bindings.bindExprType(id, type: superType)
            return superType
        }
        let hasInterfaces = supertypes.contains { ctx.cachedSymbol($0)?.kind == .interface }
        if hasInterfaces {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        return emitNoSuperclass(id: id, range: range, ctx: ctx)
    }

    private func emitNoSuperclass(id: ExprID, range: SourceRange, ctx: TypeInferenceContext) -> TypeID {
        let sema = ctx.sema
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0052",
            "Class has no superclass.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func inferThisRefExpr(
        _ id: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0051",
                "'this' is not allowed in this context.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let label {
            if let qualifiedType = ctx.resolveQualifiedThis(label: label) {
                sema.bindings.bindExprType(id, type: qualifiedType)
                return qualifiedType
            }
            let labelStr = ctx.interner.resolve(label)
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0053",
                "Unresolved label '\(labelStr)' for qualified 'this'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let thisLocal = locals[ctx.interner.intern("this")] {
            sema.bindings.bindExprType(id, type: thisLocal.type)
            return thisLocal.type
        }
        sema.bindings.bindExprType(id, type: receiverType)
        return receiverType
    }

    private enum ParentLambdaCallContext {
        case topLevel(calleeName: InternedString, argIndex: Int, typeArgs: [TypeRefID])
        case member(receiverType: TypeID?, calleeName: InternedString, argIndex: Int, typeArgs: [TypeRefID])
    }

    /// Finds the parent call context for a lambda expression by scanning the arena.
    private func findParentCallContext(for lambdaId: ExprID, ctx: TypeInferenceContext, sema _: SemaModule) -> ParentLambdaCallContext? {
        let ast = ctx.ast
        for expr in ast.arena.exprs {
            switch expr {
            case let .call(callee, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }),
                      let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    continue
                }
                return .topLevel(calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            case let .memberCall(receiver, calleeName, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            case let .safeMemberCall(receiver, calleeName, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            default:
                continue
            }
        }
        return nil
    }

    /// Infers the type for an implicit `it` parameter based on context
    private func inferItParameterType(ctx: TypeInferenceContext, id: ExprID, sema: SemaModule) -> TypeID? {
        if let parentCall = findParentCallContext(for: id, ctx: ctx, sema: sema) {
            return inferTypeFromHOFContext(parentCall, ctx: ctx, sema: sema)
        }

        if let assignmentType = inferFromAssignmentContext() {
            return assignmentType
        }

        return nil
    }

    /// Infers lambda parameter type from HOF call context
    private func inferTypeFromHOFContext(
        _ callContext: ParentLambdaCallContext,
        ctx: TypeInferenceContext,
        sema: SemaModule
    ) -> TypeID? {
        let candidateSymbols: [SymbolID]
        let argIndex: Int
        let explicitTypeArgRefs: [TypeRefID]

        switch callContext {
        case let .topLevel(calleeName, index, typeArgs):
            argIndex = index
            explicitTypeArgRefs = typeArgs
            candidateSymbols = ctx.filterByVisibility(
                ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .function || symbol.kind == .constructor
                }
            ).visible

        case let .member(receiverType, calleeName, index, typeArgs):
            guard let receiverType else {
                return nil
            }
            argIndex = index
            explicitTypeArgRefs = typeArgs
            candidateSymbols = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            )
        }

        let explicitTypeArgs = explicitTypeArgRefs.map { typeArgRef in
            driver.helpers.resolveTypeRef(
                typeArgRef,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope,
                inferenceContext: ctx
            )
        }

        var inferredParameterTypes: [TypeID] = []
        for candidate in candidateSymbols {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  argIndex < signature.parameterTypes.count
            else {
                continue
            }
            let parameterType = signature.parameterTypes[argIndex]
            if case let .functionType(functionType) = sema.types.kind(of: parameterType),
               functionType.params.count == 1
            {
                inferredParameterTypes.append(substituteExplicitTypeArgument(
                    functionType.params[0],
                    signature: signature,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                ))
                continue
            }
            if let samFunctionType = driver.helpers.samFunctionType(for: parameterType, sema: sema),
               samFunctionType.params.count == 1
            {
                inferredParameterTypes.append(substituteExplicitTypeArgument(
                    samFunctionType.params[0],
                    signature: signature,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                ))
            }
        }

        guard let firstType = inferredParameterTypes.first else {
            return nil
        }
        let allSame = inferredParameterTypes.dropFirst().allSatisfy { $0 == firstType }
        return allSame ? firstType : nil
    }

    /// Replaces a candidate's own type parameter with the explicit type argument
    /// written at the call site. Overloads of the same generic function declare
    /// distinct type parameter symbols, so without this substitution the candidate
    /// parameter types never agree and the implicit `it` type stays unresolved for
    /// every argument of a call such as `compareBy<Row>({ it.a }, { it.b })`.
    private func substituteExplicitTypeArgument(
        _ type: TypeID,
        signature: FunctionSignature,
        explicitTypeArgs: [TypeID],
        sema: SemaModule
    ) -> TypeID {
        guard !explicitTypeArgs.isEmpty,
              case let .typeParam(typeParam) = sema.types.kind(of: type)
        else {
            return type
        }
        let ownTypeParameters = signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
        guard let offset = ownTypeParameters.firstIndex(of: typeParam.symbol) else {
            return type
        }
        let argOffset = offset - ownTypeParameters.startIndex
        guard argOffset < explicitTypeArgs.count else {
            return type
        }
        let explicitType = explicitTypeArgs[argOffset]
        guard explicitType != sema.types.errorType else {
            return type
        }
        return typeParam.nullability == .nullable
            ? sema.types.makeNullable(explicitType)
            : explicitType
    }

    /// Infers lambda parameter type from assignment context
    private func inferFromAssignmentContext() -> TypeID? {
        // This would analyze assignments like `val x: (Int) -> String = { it.toString() }`
        return nil
    }

    /// Optimizes return type inference for lambda expressions
    private func inferOptimizedReturnType(
        inferredBodyType: TypeID,
        expectedReturnType: TypeID,
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID {
        // Unit optimization: if expected type is Unit, always return Unit
        if expectedReturnType == sema.types.unitType {
            return sema.types.unitType
        }

        // If the body is a block expression with no trailing expression, infer Unit
        if let bodyExprNode = ast.arena.expr(bodyExpr),
           case let .blockExpr(_, trailingExpr, _) = bodyExprNode,
           trailingExpr == nil {
            return sema.types.unitType
        }

        // If the body is already compatible with expected type, use it
        if sema.types.isSubtype(inferredBodyType, expectedReturnType) {
            return inferredBodyType
        }

        // Fall back to inferred type
        return inferredBodyType
    }
}
