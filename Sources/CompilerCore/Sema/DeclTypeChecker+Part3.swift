import Foundation

// Function-level type checking and class member scope building.

extension DeclTypeChecker {
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
        // Skip if bodyType is error (broken code)
        // Skip if bodyType is Nothing AND the body is a block ending with a
        // control-flow statement (return/break/continue), because Nothing here
        // reflects control flow, not the function's logical return type.
        // Allow Nothing for .expr bodies (e.g. `fun f() = throw ...`) and for
        // .block bodies ending with throw or a Nothing-returning call, since
        // these genuinely diverge.
        let skipSignatureUpdate = if bodyType == sema.types.errorType {
            true
        } else if bodyType == sema.types.nothingType {
            switch function.body {
            case .block:
                true
            case .expr, .unit:
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

    // MARK: - Class Member Scope Building

    func buildClassMemberScope(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext
    ) -> ClassMemberScope {
        let sema = ctx.sema
        let classScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: ownerSymbol,
            thisType: ownerType
        )

        for declID in memberFunctions + memberProperties + nestedClasses + nestedObjects {
            if let symbol = sema.bindings.declSymbols[declID] {
                classScope.insert(symbol)
            }
        }

        // Make companion properties available as unqualified names inside the
        // owning class/interface scope (e.g. `MAX_COUNT` instead of
        // `Companion.MAX_COUNT`).
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerSymbol),
           let companion = sema.symbols.symbol(companionSymbol)
        {
            for memberSymbol in sema.symbols.children(ofFQName: companion.fqName) {
                guard let member = sema.symbols.symbol(memberSymbol),
                      member.kind == .property || member.kind == .field
                else {
                    continue
                }
                classScope.insert(memberSymbol)
            }
        }

        return classScope
    }
}
