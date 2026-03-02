import Foundation

// Init block, secondary constructor, and function declaration type checking.

extension DeclTypeChecker {
    // MARK: - Init Block & Secondary Constructor Type Checking

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
            let ctorSymbols = sema.symbols.symbols(atDeclSite: ctor.range)
                .compactMap { sema.symbols.symbol($0) }
                .filter { $0.kind == .constructor }
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
                    let type = index < signature.parameterTypes.count
                        ? signature.parameterTypes[index]
                        : sema.types.anyType
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

            typeCheckConstructorDelegation(
                ctor: ctor,
                currentCtorSymbolID: currentCtorSymbolID,
                ownerSymbol: ownerSymbol,
                ctx: constructorCtx,
                locals: &locals
            )
            _ = inferFunctionBodyType(ctor.body, ctx: constructorCtx, locals: &locals, expectedType: nil)
        }
    }

    private func typeCheckConstructorDelegation(
        ctor: ConstructorDecl,
        currentCtorSymbolID: SymbolID?,
        ownerSymbol: SymbolID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard let delegation = ctor.delegationCall else { return }

        var argTypes: [CallArg] = []
        for arg in delegation.args {
            let argType = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: nil)
            argTypes.append(CallArg(label: arg.label, isSpread: arg.isSpread, type: argType))
        }

        let delegationTargetFQName = resolveDelegationTarget(
            delegation: delegation,
            ownerSymbol: ownerSymbol,
            ctx: ctx
        )

        if !delegationTargetFQName.isEmpty {
            let candidates = sema.symbols.lookupAll(fqName: delegationTargetFQName)
                .filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else { return false }
                    return symbol.kind == .constructor && candidate != currentCtorSymbolID
                }

            if candidates.isEmpty {
                emitUnresolvedDelegation(delegation: delegation, sema: sema)
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
            emitUnresolvedDelegation(delegation: delegation, sema: sema)
        }
    }

    private func resolveDelegationTarget(
        delegation: ConstructorDelegationCall,
        ownerSymbol: SymbolID?,
        ctx: TypeInferenceContext
    ) -> [InternedString] {
        let sema = ctx.sema
        switch delegation.kind {
        case .this:
            if let owner = ownerSymbol,
               let ownerSym = sema.symbols.symbol(owner)
            {
                return ownerSym.fqName + [ctx.interner.intern("<init>")]
            }
            return []
        case .super_:
            guard let owner = ownerSymbol else { return [] }
            let supertypes = sema.symbols.directSupertypes(for: owner)
            let classSupertypes = supertypes.filter {
                let kind = sema.symbols.symbol($0)?.kind
                return kind == .class || kind == .enumClass
            }
            if let superclass = classSupertypes.first,
               let superSym = sema.symbols.symbol(superclass)
            {
                return superSym.fqName + [ctx.interner.intern("<init>")]
            }
            return []
        }
    }

    private func emitUnresolvedDelegation(
        delegation: ConstructorDelegationCall,
        sema: SemaModule
    ) {
        let targetKind = delegation.kind == .this ? "this" : "super"
        sema.diagnostics.error(
            "KSWIFTK-SEMA-0055",
            "Unresolved \(targetKind)() delegation target: no matching constructor found.",
            range: delegation.range
        )
    }

    // MARK: - Function Declaration Type Checking

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

        updateInferredReturnType(
            function: function,
            symbol: symbol,
            bodyType: bodyType,
            signature: signature,
            sema: sema
        )
    }

    /// Updates the function signature with the inferred return type when no
    /// explicit annotation is present and the body type is suitable.
    private func updateInferredReturnType(
        function: FunDecl,
        symbol: SymbolID,
        bodyType: TypeID,
        signature: FunctionSignature,
        sema: SemaModule
    ) {
        let skipUpdate = if bodyType == sema.types.errorType {
            true
        } else if bodyType == sema.types.nothingType {
            switch function.body {
            case .block: true
            case .expr, .unit: false
            }
        } else {
            false
        }

        if function.returnType == nil, !skipUpdate {
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
