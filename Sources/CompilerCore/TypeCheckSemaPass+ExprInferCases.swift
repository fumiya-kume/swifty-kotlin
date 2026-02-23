import Foundation

extension TypeCheckSemaPassPhase {
    func inferNameRefExpr(
        _ id: ExprID,
        name: InternedString,
        nameRange: SourceRange?,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        if interner.resolve(name) == "null" {
            sema.bindings.bindExprType(id, type: sema.types.nullableAnyType)
            return sema.types.nullableAnyType
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
            sema.bindings.bindExprType(id, type: local.type)
            return local.type
        }
        let allCandidateIDs = scope.lookup(name)
        let (visibleIDs, invisibleSyms) = ctx.filterByVisibility(allCandidateIDs)
        let candidates = visibleIDs.compactMap { sema.symbols.symbol($0) }
        if candidates.isEmpty {
            if let firstInvisible = invisibleSyms.first {
                emitVisibilityError(for: firstInvisible, name: interner.resolve(name), range: nameRange, diagnostics: ctx.semaCtx.diagnostics)
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
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
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

        let inferredBodyType = inferExpr(
            body,
            ctx: ctx,
            locals: &lambdaLocals,
            expectedType: expectedFunctionType?.returnType
        )
        let captures = collectCapturedOuterSymbols(
            in: body,
            ast: ast,
            sema: sema,
            outerSymbols: outerSymbols
        )
        sema.bindings.bindCaptureSymbols(id, symbols: captures)

        if let expectedType, let expectedFunctionType {
            emitSubtypeConstraint(
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
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let scope = ctx.scope
        let outerSymbols = Set(locals.values.map { $0.symbol })

        let receiverType: TypeID?
        if let receiver {
            receiverType = inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        } else {
            receiverType = nil
        }

        var candidates: [SymbolID] = []
        if let receiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let memberCandidates = collectMemberFunctionCandidates(
                named: member,
                receiverType: nonNullReceiver,
                sema: sema
            )
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
            } else {
                candidates = scope.lookup(member).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let declaredReceiver = signature.receiverType else {
                        return false
                    }
                    return sema.types.isSubtype(nonNullReceiver, declaredReceiver)
                }
            }
        } else {
            candidates = scope.lookup(member).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            if candidates.isEmpty,
               let local = locals[member],
               let localSymbol = sema.symbols.symbol(local.symbol),
               localSymbol.kind == .function {
                candidates = [local.symbol]
            }
        }

        let chosen = chooseCallableReferenceTarget(
            from: candidates,
            expectedType: expectedType,
            bindReceiver: receiver != nil,
            sema: sema
        )

        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen) {
            let inferredType = callableFunctionType(
                for: signature,
                bindReceiver: receiver != nil,
                sema: sema
            )
            let resultType: TypeID
            if let expectedType,
               case .functionType = sema.types.kind(of: expectedType) {
                emitSubtypeConstraint(
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
                collectCapturedOuterSymbols(
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
            collectCapturedOuterSymbols(
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
        if let classSymbol = nominalSymbol(of: receiverType, types: sema.types) {
            let supertypes = sema.symbols.directSupertypes(for: classSymbol)
            let classSupertypes = supertypes.filter {
                let kind = sema.symbols.symbol($0)?.kind
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
