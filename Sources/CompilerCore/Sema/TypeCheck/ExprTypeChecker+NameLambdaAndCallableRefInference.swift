import Foundation

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
        let operatorNames = operatorFunctionNames(for: op, interner: interner)
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
            let resultType: TypeID = switch underlyingOp {
            case .add:
                if local.type == stringType || valueType == stringType {
                    stringType
                } else if local.type == charType, valueType == intType {
                    charType
                } else {
                    intType
                }
            case .subtract:
                if local.type == charType, valueType == intType {
                    charType
                } else {
                    intType
                }
            case .multiply, .divide, .modulo:
                intType
            default:
                local.type
            }
            locals[name] = (resultType, local.symbol, local.isMutable, local.isInitialized)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
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
        if let propSymbol = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package || (ctx.implicitReceiverType != nil
                && (parentSym.kind == .class || parentSym.kind == .object || parentSym.kind == .interface))
        }) {
            sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            let propType = sema.symbols.propertyType(for: propSymbol.id) ?? sema.types.errorType
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
           case let .classType(classInfo) = sema.types.kind(of: nonNullReceiver)
        {
            if let symbol = sema.symbols.symbol(classInfo.classSymbol),
               knownNames.collectionKind(of: symbol) != nil
            {
                implicitMemberType = name == knownNames.size
                    ? sema.types.intType
                    : sema.types.make(.primitive(.boolean, .nonNull))
            }
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
            }
            else {
                params
            }
        } else {
            params
        }

        let parameterTypes: [TypeID] = if let expectedFunctionType,
                                          expectedFunctionType.params.count == effectiveParams.count
        {
            expectedFunctionType.params
        } else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
                  samFT.params.count == effectiveParams.count {
            // Use SAM conversion parameter types
            samFT.params
        } else if effectiveParams.count == 1 && effectiveParams.contains(ctx.interner.intern("it")) {
            // For implicit `it` parameter, try to infer type from context
            inferredImplicitItType.map { [$0] }
                ?? Array(repeating: sema.types.anyType, count: effectiveParams.count)
        } else {
            Array(repeating: sema.types.anyType, count: effectiveParams.count)
        }
        for (offset, param) in effectiveParams.enumerated() {
            let syntheticSymbol = SymbolID(rawValue: Int32(clamping: Int64(-1_000_000) - Int64(id.rawValue) * 256 - Int64(offset)))
            let parameterType = offset < parameterTypes.count ? parameterTypes[offset] : sema.types.anyType
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
        // When the expected function type has a receiver (e.g. StringBuilder.() -> Unit),
        // set the implicit receiver so that unqualified member calls resolve correctly.
        if let receiverType = expectedFunctionType?.receiver {
            bodyCtx = bodyCtx.with(implicitReceiverType: receiverType)
        }
        let inferredBodyType = driver.inferExpr(
            body,
            ctx: bodyCtx,
            locals: &lambdaLocals,
            expectedType: expectedFunctionType?.returnType
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
                sema: sema,
                ctx: ctx
            )
            
            // Apply subtype constraint only if needed
            if expectedFunctionType.returnType != sema.types.unitType {
                driver.emitSubtypeConstraint(
                    left: optimizedReturnType,
                    right: expectedFunctionType.returnType,
                    range: ast.arena.exprRange(body),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: expectedType)
            return expectedType
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
        // KIR lowering can emit `kk_kclass_create` with the correct token.
        if member == KnownCompilerNames(interner: interner).className,
           let receiver,
           case .thisRef = ast.arena.expr(receiver)
        {
            if let result = inferExprReceiverClassRef(
                id, receiver: receiver, range: range, ctx: ctx, locals: &locals
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
                sema: sema
            )
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
            } else {
                if case let .classType(classType) = sema.types.kind(of: nonNullReceiver),
                   let owner = sema.symbols.symbol(classType.classSymbol)
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
                        let resultType = expectedType ?? propertyType
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
                sema.bindings.bindIdentifier(id, symbol: propertySymbol)
                sema.bindings.bindCallableRefKind(id, kind: .propertyRef)
                sema.bindings.bindExprType(id, type: propertyType)
                return propertyType
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

        let chosen = driver.helpers.chooseCallableReferenceTarget(
            from: candidates,
            expectedType: expectedType,
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
            if let expectedType,
               case .functionType = sema.types.kind(of: expectedType)
            {
                driver.emitSubtypeConstraint(
                    left: inferredType,
                    right: expectedType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                resultType = expectedType
            } else {
                resultType = inferredType
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
        range: SourceRange,
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

    // MARK: - Lambda Parameter Inference Helpers

    private enum ParentLambdaCallContext {
        case topLevel(calleeName: InternedString, argIndex: Int)
        case member(receiverType: TypeID?, calleeName: InternedString, argIndex: Int)
    }

    /// Finds the parent call context for a lambda expression by scanning the arena.
    private func findParentCallContext(for lambdaId: ExprID, ctx: TypeInferenceContext, sema _: SemaModule) -> ParentLambdaCallContext? {
        let ast = ctx.ast
        for expr in ast.arena.exprs {
            switch expr {
            case let .call(callee, _, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }),
                      let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    continue
                }
                return .topLevel(calleeName: calleeName, argIndex: argIndex)

            case let .memberCall(receiver, calleeName, _, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex)

            case let .safeMemberCall(receiver, calleeName, _, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex)

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

        if let assignmentType = inferFromAssignmentContext(id: id, ctx: ctx, sema: sema) {
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

        switch callContext {
        case let .topLevel(calleeName, index):
            argIndex = index
            candidateSymbols = ctx.filterByVisibility(
                ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .function || symbol.kind == .constructor
                }
            ).visible

        case let .member(receiverType, calleeName, index):
            guard let receiverType else {
                return nil
            }
            argIndex = index
            candidateSymbols = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: receiverType,
                sema: sema
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
                inferredParameterTypes.append(functionType.params[0])
                continue
            }
            if let samFunctionType = driver.helpers.samFunctionType(for: parameterType, sema: sema),
               samFunctionType.params.count == 1
            {
                inferredParameterTypes.append(samFunctionType.params[0])
            }
        }

        guard let firstType = inferredParameterTypes.first else {
            return nil
        }
        let allSame = inferredParameterTypes.dropFirst().allSatisfy { $0 == firstType }
        return allSame ? firstType : nil
    }

    /// Infers lambda parameter type from assignment context
    private func inferFromAssignmentContext(id: ExprID, ctx: TypeInferenceContext, sema: SemaModule) -> TypeID? {
        // This would analyze assignments like `val x: (Int) -> String = { it.toString() }`
        return nil
    }

    /// Optimizes return type inference for lambda expressions
    private func inferOptimizedReturnType(
        inferredBodyType: TypeID,
        expectedReturnType: TypeID,
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext
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
        
        // Try to find a common supertype
        if let commonType = findCommonSupertype(inferredBodyType, expectedReturnType, sema: sema) {
            return commonType
        }
        
        // Fall back to inferred type
        return inferredBodyType
    }

    /// Finds the common supertype of two types
    private func findCommonSupertype(_ type1: TypeID, _ type2: TypeID, sema: SemaModule) -> TypeID? {
        // This would implement type hierarchy analysis to find common supertype
        // For now, return nil as a placeholder
        return nil
    }
}
