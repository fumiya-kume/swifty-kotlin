import Foundation

// Handles expression type inference dispatch and specific expression cases.
// Derived from TypeCheckSemaPhase+ExprInference.swift and TypeCheckSemaPhase+ExprInferCases.swift.

extension ExprTypeChecker {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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
        let (visibleIDs, _) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if let propSymbol = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package || (ctx.implicitReceiverType != nil
                && (parentSym.kind == .class || parentSym.kind == .object || parentSym.kind == .interface))
        }) {
            sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            let propType = sema.symbols.propertyType(for: propSymbol.id) ?? sema.types.anyType
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

        if interner.resolve(name) == "field" {
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

    // MARK: - Specific Expression Cases (from +ExprInferCases.swift)

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func inferNameRefExpr(
        _ id: ExprID,
        name: InternedString,
        nameRange: SourceRange?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        if interner.resolve(name) == "null" {
            sema.bindings.bindExprType(id, type: sema.types.nullableNothingType)
            return sema.types.nullableNothingType
        }
        if interner.resolve(name) == "this",
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
            sema.bindings.bindExprType(id, type: local.type)
            return local.type
        }
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let (visibleIDs, invisibleSyms) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if candidates.isEmpty {
            if let firstInvisible = invisibleSyms.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(name), range: nameRange, diagnostics: ctx.semaCtx.diagnostics)
            } else if interner.resolve(name) == "field" {
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
        if let first = candidates.first {
            sema.bindings.bindIdentifier(id, symbol: first.id)
        }
        let resolvedType = candidates.first.flatMap { symbol in
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
        } ?? sema.types.anyType
        // Propagate compile-time constant value for `const val` references
        // so downstream passes can fold without re-querying the symbol table.
        if let first = candidates.first, first.flags.contains(.constValue) {
            if let constKind = sema.symbols.constValueExprKind(for: first.id) {
                sema.bindings.bindConstExprValue(id, value: constKind)
            }
        }
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    // swiftlint:disable:next function_body_length
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

        // Extract label from the lambda literal AST node for labeled lambda support
        let label: InternedString? = if case let .lambdaLiteral(_, _, lbl, _) = ast.arena.expr(id) { lbl } else { nil }

        let expectedFunctionType: FunctionType? = if let expectedType,
                                                     case let .functionType(functionType) = sema.types.kind(of: expectedType)
        {
            functionType
        } else {
            nil
        }

        var lambdaLocals = locals
        let outerSymbols = Set(locals.values.map(\.symbol))

        // Implicit `it` parameter: when a no-arrow lambda has zero explicit params
        // and the expected function type has exactly one parameter, synthesise an
        // `it` binding so the body can reference it.
        let effectiveParams: [InternedString] = if params.isEmpty,
                                                   let expectedFunctionType,
                                                   expectedFunctionType.params.count == 1
        { // swiftlint:disable:this opening_brace
            [ctx.interner.intern("it")]
        } else {
            params
        }

        let parameterTypes: [TypeID] = if let expectedFunctionType,
                                          expectedFunctionType.params.count == effectiveParams.count
        { // swiftlint:disable:this opening_brace
            expectedFunctionType.params
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

        let bodyCtx: TypeInferenceContext = if let label {
            ctx.withLambdaLabel(label)
        } else {
            ctx
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

        if let expectedType, let expectedFunctionType {
            driver.emitSubtypeConstraint(
                left: inferredBodyType,
                right: expectedFunctionType.returnType,
                range: ast.arena.exprRange(body),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
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

    // swiftlint:disable:next cyclomatic_complexity
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
        if interner.resolve(member) == "class",
           let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver)
        { // swiftlint:disable:this opening_brace
            if let result = inferClassRefExpr(
                id, receiver: receiver, receiverName: receiverName,
                range: range, ctx: ctx, locals: &locals
            ) {
                return result
            }
        }

        let receiverType: TypeID? = if let receiver {
            driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        } else {
            nil
        }

        var candidates: [SymbolID] = []
        if let receiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: member,
                receiverType: nonNullReceiver,
                sema: sema
            )
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
            } else {
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

        let chosen = driver.helpers.chooseCallableReferenceTarget(
            from: candidates,
            expectedType: expectedType,
            bindReceiver: receiver != nil,
            sema: sema
        )

        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen)
        {
            let inferredType = driver.helpers.callableFunctionType(
                for: signature,
                bindReceiver: receiver != nil,
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

        let fallbackType: TypeID = if let expectedType,
                                      case .functionType = sema.types.kind(of: expectedType)
        {
            expectedType
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

    /// Helper: handles `T::class` / `SomeType::class` callable-ref expressions.
    /// Returns the inferred type if matched, or `nil` to fall through.
    private func inferClassRefExpr( // swiftlint:disable:this function_parameter_count
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
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return sema.types.anyType
        }
        for candidateID in allCandidateIDs {
            guard let sym = ctx.cachedSymbol(candidateID),
                  sym.kind == .class || sym.kind == .interface
                  || sym.kind == .object || sym.kind == .enumClass
            else { continue }
            let classType = sema.types.make(.classType(ClassType(classSymbol: sym.id)))
            sema.bindings.bindClassRefTargetType(id, type: classType)
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return sema.types.anyType
        }
        return nil
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
        ctx: TypeInferenceContext
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
        sema.bindings.bindExprType(id, type: receiverType)
        return receiverType
    }
    // swiftlint:disable:next file_length
}
