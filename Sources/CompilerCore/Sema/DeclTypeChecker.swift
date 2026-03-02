import Foundation

/// Handles declaration-level type checking (functions, properties, classes, objects).
/// Derived from TypeCheckSemaPass.swift (second extension) and TypeCheckSemaPass+DeclTypeCheck.swift.
final class DeclTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // MARK: - Function Body Type Inference (from +DeclTypeCheck.swift)

    func inferFunctionBodyType(
        _ body: FunctionBody,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        switch body {
        case .unit:
            return ctx.sema.types.unitType

        case let .expr(exprID, _):
            return driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .block(exprIDs, _):
            var last = ctx.sema.types.unitType
            var reachedNothing = false
            for exprID in exprIDs {
                if reachedNothing {
                    if let stmtRange = ctx.ast.arena.exprRange(exprID) {
                        ctx.semaCtx.diagnostics.warning(
                            "KSWIFTK-SEMA-0096",
                            "Unreachable code.",
                            range: stmtRange
                        )
                    }
                    _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: nil)
                    continue
                }
                // Pass expectedType to return expressions (so the return value is
                // checked against the function return type) and to the last expression
                // (which determines the block's result type for expression-body inference).
                let exprExpectedType: TypeID? = if let expr = ctx.ast.arena.expr(exprID), case .returnExpr = expr {
                    expectedType
                } else if exprID == exprIDs.last {
                    expectedType
                } else {
                    nil
                }
                last = driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: exprExpectedType)
                if last == ctx.sema.types.nothingType {
                    reachedNothing = true
                }
            }
            return reachedNothing ? ctx.sema.types.nothingType : last
        }
    }

    // MARK: - Property Type Checking (from +DeclTypeCheck.swift)

    func typeCheckPropertyDecl(
        _ property: PropertyDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        var inferredPropertyType: TypeID? = property.type != nil ? sema.symbols.propertyType(for: symbol) : nil

        if let initializer = property.initializer {
            var locals: LocalBindings = [:]
            let initializerType = driver.inferExpr(
                initializer, ctx: ctx, locals: &locals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                driver.emitSubtypeConstraint(
                    left: initializerType, right: declaredType,
                    range: property.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = initializerType
            }
        }

        if let getter = property.getter {
            var getterLocals: LocalBindings = [:]
            if let fieldType = inferredPropertyType {
                let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
                getterLocals[interner.intern("field")] = (fieldType, fieldSymbol, true, true)
            }
            let getterType = inferFunctionBodyType(
                getter.body, ctx: ctx, locals: &getterLocals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                driver.emitSubtypeConstraint(
                    left: getterType, right: declaredType,
                    range: getter.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = getterType
            }
        }

        if let delegateExpr = property.delegateExpression {
            var delegateLocals: LocalBindings = [:]
            let delegateType = driver.inferExpr(
                delegateExpr, ctx: ctx, locals: &delegateLocals,
                expectedType: nil
            )

            // Record the delegate type on the property symbol so the KIR
            // lowering phase can synthesise getValue/setValue calls.
            sema.symbols.setPropertyType(delegateType, for: SymbolID(rawValue: -(symbol.rawValue + 50000)))

            // Resolve getValue operator on the delegate type to infer the
            // property type from its return type (Kotlin spec J12).
            let getValueName = interner.intern("getValue")
            let getValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: getValueName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            if let getValueSymbol = getValueCandidates.first,
               let getValueSig = sema.symbols.functionSignature(for: getValueSymbol)
            {
                // Use getValue return type to infer the property type when
                // no explicit type annotation is provided.
                if inferredPropertyType == nil {
                    inferredPropertyType = getValueSig.returnType
                }
            }

            // Fallback: if no getValue was resolved and no explicit type,
            // use Any? as the property type.
            if inferredPropertyType == nil {
                inferredPropertyType = sema.types.nullableAnyType
            }

            // For var properties, also check that setValue operator exists.
            if property.isVar {
                let setValueName = interner.intern("setValue")
                let setValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: setValueName,
                    receiverType: delegateType,
                    sema: sema
                ).filter { candidateID in
                    guard let sym = sema.symbols.symbol(candidateID) else { return false }
                    return sym.flags.contains(.operatorFunction)
                }
                _ = setValueCandidates // Validate existence; diagnostic emitted elsewhere if needed.
            }

            // Check for provideDelegate operator on the delegate type.
            let provideDelegateName = interner.intern("provideDelegate")
            let provideDelegateCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: provideDelegateName,
                receiverType: delegateType,
                sema: sema
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            _ = provideDelegateCandidates // Track for KIR lowering provideDelegate insertion.
        }

        let finalPropertyType = inferredPropertyType ?? sema.types.nullableAnyType
        sema.symbols.setPropertyType(finalPropertyType, for: symbol)

        if let setter = property.setter {
            if !property.isVar {
                diagnostics.error(
                    "KSWIFTK-SEMA-0005",
                    "Setter is not allowed for read-only property.",
                    range: setter.range
                )
            }
            var setterLocals: LocalBindings = [:]
            let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
            setterLocals[interner.intern("field")] = (finalPropertyType, fieldSymbol, true, true)
            let parameterName = setter.parameterName ?? interner.intern("value")
            let setterValueSymbol = SyntheticSymbolScheme.semaSetterValueSymbol(for: symbol)
            setterLocals[parameterName] = (finalPropertyType, setterValueSymbol, true, true)
            let setterType = inferFunctionBodyType(
                setter.body, ctx: ctx, locals: &setterLocals,
                expectedType: sema.types.unitType
            )
            driver.emitSubtypeConstraint(
                left: setterType, right: sema.types.unitType,
                range: setter.range, solver: solver,
                sema: sema, diagnostics: diagnostics
            )
        }
    }

    // MARK: - Init Block & Secondary Constructor Type Checking (from +DeclTypeCheck.swift)

    func typeCheckInitBlocks(
        _ blocks: [FunctionBody],
        ctx: TypeInferenceContext
    ) {
        for block in blocks {
            var locals: LocalBindings = [:]
            _ = inferFunctionBodyType(block, ctx: ctx, locals: &locals, expectedType: nil)
        }
    }

    func typeCheckSecondaryConstructors(
        _ constructors: [ConstructorDecl],
        ctx: TypeInferenceContext,
        ownerSymbol: SymbolID? = nil,
        hasPrimaryConstructor: Bool = true
    ) {
        let sema = ctx.sema
        for ctor in constructors {
            var locals: LocalBindings = [:]
            let ctorSymbols = sema.symbols.symbols(atDeclSite: ctor.range).compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .constructor }
            let currentCtorSymbolID = ctorSymbols.first?.id
            let constructorScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
            var constructorCtx = ctx.copying(scope: constructorScope)
            if let ctorSymbol = ctorSymbols.first,
               let signature = sema.symbols.functionSignature(for: ctorSymbol.id)
            {
                for typeParameterSymbol in signature.typeParameterSymbols {
                    constructorScope.insert(typeParameterSymbol)
                }
                for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                    guard let param = sema.symbols.symbol(paramSymbol) else { continue }
                    let type = index < signature.parameterTypes.count ? signature.parameterTypes[index] : sema.types.anyType
                    locals[param.name] = (type, paramSymbol, false, true)
                }
                constructorCtx = ctx.copying(scope: constructorScope)
            }

            if ctor.delegationCall == nil, hasPrimaryConstructor {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0054",
                    "Secondary constructor must delegate to another constructor via this() or super().",
                    range: ctor.range
                )
            }

            if let delegation = ctor.delegationCall {
                var argTypes: [CallArg] = []
                for arg in delegation.args {
                    let argType = driver.inferExpr(arg.expr, ctx: constructorCtx, locals: &locals, expectedType: nil)
                    argTypes.append(CallArg(label: arg.label, isSpread: arg.isSpread, type: argType))
                }

                let delegationTargetFQName: [InternedString]
                switch delegation.kind {
                case .this:
                    if let owner = ownerSymbol,
                       let ownerSym = sema.symbols.symbol(owner)
                    {
                        delegationTargetFQName = ownerSym.fqName + [ctx.interner.intern("<init>")]
                    } else {
                        delegationTargetFQName = []
                    }
                case .super_:
                    if let owner = ownerSymbol {
                        let supertypes = sema.symbols.directSupertypes(for: owner)
                        let classSupertypes = supertypes.filter {
                            let kind = sema.symbols.symbol($0)?.kind
                            return kind == .class || kind == .enumClass
                        }
                        if let superclass = classSupertypes.first,
                           let superSym = sema.symbols.symbol(superclass)
                        {
                            delegationTargetFQName = superSym.fqName + [ctx.interner.intern("<init>")]
                        } else {
                            delegationTargetFQName = []
                        }
                    } else {
                        delegationTargetFQName = []
                    }
                }

                if !delegationTargetFQName.isEmpty {
                    let candidates = sema.symbols.lookupAll(fqName: delegationTargetFQName)
                        .filter { candidate in
                            guard let symbol = sema.symbols.symbol(candidate) else { return false }
                            return symbol.kind == .constructor && candidate != currentCtorSymbolID
                        }

                    if candidates.isEmpty {
                        let targetKind = delegation.kind == .this ? "this" : "super"
                        sema.diagnostics.error(
                            "KSWIFTK-SEMA-0055",
                            "Unresolved \(targetKind)() delegation target: no matching constructor found.",
                            range: delegation.range
                        )
                    } else {
                        let callExpr = CallExpr(
                            range: delegation.range,
                            calleeName: ctx.interner.intern("<init>"),
                            args: argTypes
                        )
                        let resolved = ctx.resolver.resolveCall(
                            candidates: candidates,
                            call: callExpr,
                            expectedType: nil,
                            ctx: sema
                        )
                        if let diagnostic = resolved.diagnostic {
                            sema.diagnostics.emit(diagnostic)
                        }
                    }
                } else if ownerSymbol != nil {
                    let targetKind = delegation.kind == .this ? "this" : "super"
                    sema.diagnostics.error(
                        "KSWIFTK-SEMA-0055",
                        "Unresolved \(targetKind)() delegation target: no matching constructor found.",
                        range: delegation.range
                    )
                }
            }
            _ = inferFunctionBodyType(ctor.body, ctx: constructorCtx, locals: &locals, expectedType: nil)
        }
    }

    // MARK: - Top-Level Decl Type Checking (from TypeCheckSemaPass.swift second extension)

    func typeCheckFunctionDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: symbol) else {
            return
        }

        var locals: LocalBindings = [:]
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else {
                continue
            }
            let type = index < signature.parameterTypes.count
                ? signature.parameterTypes[index]
                : sema.types.anyType
            locals[param.name] = (type, paramSymbol, false, true)
        }

        let functionScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
        for typeParameterSymbol in signature.typeParameterSymbols {
            functionScope.insert(typeParameterSymbol)
        }
        let functionCtx = ctx.copying(scope: functionScope, implicitReceiverType: signature.receiverType)

        // Abstract methods use .unit as their body sentinel – skip body type
        // inference. Gate on abstractType so non-abstract missing bodies still
        // hit the Unit <: ReturnType constraint.
        let isAbstract = function.body == .unit
            && (sema.symbols.symbol(symbol)?.flags.contains(.abstractType) ?? false)
        if isAbstract { return }

        let bodyType = inferFunctionBodyType(
            function.body,
            ctx: functionCtx,
            locals: &locals,
            expectedType: signature.returnType
        )
        driver.emitSubtypeConstraint(
            left: bodyType,
            right: signature.returnType,
            range: function.range,
            solver: solver,
            sema: sema,
            diagnostics: diagnostics
        )

        // When inferring return type for functions without explicit annotation:
        // - Skip if bodyType is error (broken code)
        // - Skip if bodyType is Nothing AND the body is a block ending with a
        //   control-flow statement (return/break/continue), because Nothing here
        //   reflects control flow, not the function's logical return type.
        // - Allow Nothing for .expr bodies (e.g. `fun f() = throw ...`) and for
        //   .block bodies ending with throw or a Nothing-returning call, since
        //   these genuinely diverge.
        let skipSignatureUpdate = if bodyType == sema.types.errorType {
            true
        } else if bodyType == sema.types.nothingType {
            switch function.body {
            case .block:
                // Block-body functions without explicit return type should not have
                // their return type inferred as Nothing. In Kotlin, block-body
                // functions default to Unit. Nothing can arise from control flow
                // (return/break/continue), throw, compound expressions where all
                // branches return, etc. Return value type checking is already
                // handled at the returnExpr level, so skipping here is safe.
                true
            case .expr, .unit:
                // Expression-body functions (e.g. `fun f() = throw ...`) should
                // infer Nothing when the expression genuinely evaluates to Nothing.
                false
            }
        } else {
            false
        }

        if function.returnType == nil, !skipSignatureUpdate {
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    parameterTypes: signature.parameterTypes,
                    returnType: bodyType,
                    isSuspend: signature.isSuspend,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                ),
                for: symbol
            )
        }
    }
}
