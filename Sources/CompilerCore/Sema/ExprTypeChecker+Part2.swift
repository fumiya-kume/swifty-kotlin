import Foundation

/// Handles expression type inference dispatch and specific expression cases.
/// Derived from TypeCheckSemaPhase+ExprInference.swift and TypeCheckSemaPhase+ExprInferCases.swift.

extension ExprTypeChecker {
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
            let resultType: TypeID
            switch underlyingOp {
            case .add:
                if local.type == stringType || valueType == stringType {
                    resultType = stringType
                } else if local.type == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .subtract:
                if local.type == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .multiply, .divide, .modulo:
                resultType = intType
            default:
                resultType = local.type
            }
            locals[name] = (resultType, local.symbol, local.isMutable, local.isInitialized)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // Fall back to top-level property lookup for compound assignments like `counter += 1`
        // where `counter` is a top-level var.
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let (visibleIDs, _) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        // Only match top-level properties, not class member properties.
        // Top-level properties have no parentSymbol set (nil) or parent is a package.
        // Class member properties always have parentSymbol set to a class/object/interface.
        if let propSymbol = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package
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
            let resultType: TypeID
            switch underlyingOp {
            case .add:
                if propType == stringType || valueType == stringType {
                    resultType = stringType
                } else if propType == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .subtract:
                if propType == charType && valueType == intType {
                    resultType = charType
                } else {
                    resultType = intType
                }
            case .multiply, .divide, .modulo:
                resultType = intType
            default:
                resultType = propType
            }
            _ = resultType  // top-level property type not updated in locals
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0013",
            "Unresolved local variable '\(interner.resolve(name))'.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    // MARK: - Specific Expression Cases (from +ExprInferCases.swift)

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
           let receiverType = ctx.implicitReceiverType {
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
            if symbol.kind == .property || symbol.kind == .field || symbol.kind == .object {
                return sema.symbols.propertyType(for: symbol.id)
            }
            // Objects are singletons – always resolve to their nominal type so
            // that `ObjectName.member()` works.
            if symbol.kind == .object {
                return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
            }
            // For class/interface/enum symbols, only resolve to nominal type when
            // they have a companion object so that `ClassName.companionMember()`
            // can resolve.  Without a companion, keep the previous anyType
            // fallback so that `ClassName.instanceMethod()` correctly errors.
            if (symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass),
               sema.symbols.companionObjectSymbol(for: symbol.id) != nil {
                return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
            }
            return nil
        } ?? sema.types.anyType
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
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

        let expectedFunctionType: FunctionType?
        if let expectedType,
           case .functionType(let functionType) = sema.types.kind(of: expectedType) {
            expectedFunctionType = functionType
        } else {
            expectedFunctionType = nil
        }

        var lambdaLocals = locals
        let outerSymbols = Set(locals.values.map { $0.symbol })
        let parameterTypes: [TypeID]
        if let expectedFunctionType, expectedFunctionType.params.count == params.count {
            parameterTypes = expectedFunctionType.params
        } else {
            parameterTypes = Array(repeating: sema.types.anyType, count: params.count)
        }
        for (offset, param) in params.enumerated() {
            let syntheticSymbol = SymbolID(rawValue: Int32(clamping: Int64(-1_000_000) - Int64(id.rawValue) * 256 - Int64(offset)))
            let parameterType = offset < parameterTypes.count ? parameterTypes[offset] : sema.types.anyType
            lambdaLocals[param] = (
                type: parameterType,
                symbol: syntheticSymbol,
                isMutable: false,
                isInitialized: true
            )
        }

        let inferredBodyType = driver.inferExpr(
            body,
            ctx: ctx,
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
        let outerSymbols = Set(locals.values.map { $0.symbol })

        let receiverType: TypeID?
        if let receiver {
            receiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        } else {
            receiverType = nil
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
                          let declaredReceiver = signature.receiverType else {
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
               localSymbol.kind == .function {
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
           let signature = sema.symbols.functionSignature(for: chosen) {
            let inferredType = driver.helpers.callableFunctionType(
                for: signature,
                bindReceiver: receiver != nil,
                sema: sema
            )
            let resultType: TypeID
            if let expectedType,
               case .functionType = sema.types.kind(of: expectedType) {
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

        let fallbackType: TypeID
        if let expectedType,
           case .functionType = sema.types.kind(of: expectedType) {
            fallbackType = expectedType
        } else {
            fallbackType = sema.types.anyType
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

    func inferSuperRefExpr(
        _ id: ExprID,
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
        if let classSymbol = driver.helpers.nominalSymbol(of: receiverType, types: sema.types) {
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
        }
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
}
