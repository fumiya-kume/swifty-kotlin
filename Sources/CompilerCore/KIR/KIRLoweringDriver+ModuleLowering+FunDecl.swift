
extension KIRLoweringDriver {
    /// Lower a top-level function declaration into KIR declarations.
    func lowerTopLevelFunDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        if isRuntimeBackedBundledStdlibSourceFunction(
            symbol: symbol,
            sema: shared.sema,
            interner: shared.interner,
            sourceManager: compilationCtx.sourceManager
        ) {
            return []
        }
        if function.modifiers.contains(.external), function.body == .unit {
            return []
        }

        let sema = shared.sema
        let arena = shared.arena

        // Functions with an external link name are bridged to a runtime
        // function; call sites are redirected to that external link name
        // (see CallLowerer), so the source body is never executed. Do NOT
        // emit a KIRFunction declaration for them at all: NativeEmitter
        // unconditionally registers every emitted KIRFunction in
        // `internalFunctions[symbol]`, and call-site codegen prefers that
        // internal definition over the redirected external callee name.
        // Emitting even a stub body here would shadow the real runtime
        // function and cause calls to silently invoke the stub instead.
        if let externalLink = sema.symbols.externalLinkName(for: symbol), !externalLink.isEmpty {
            return []
        }

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        ctx.setCurrentFunctionSymbol(symbol)
        let signature = sema.symbols.functionSignature(for: symbol)
        let params = buildFunDeclParams(function, symbol: symbol, signature: signature, shared: shared)
        let returnType = signature?.returnType ?? sema.types.unitType
        var body: KIRLoweringEmitContext = [.beginBlock]
        bindFunctionParameterLocals(params: params, body: &body, arena: arena)
        lowerFunDeclBody(function, shared: shared, body: &body)
        body.append(.endBlock)
        // Auto-inline functions that have function-type parameters (receiver lambdas etc.)
        // so that lambda arguments are expanded at the call site, matching Kotlin semantics.
        // Suspend functions are excluded: inlining a body that invokes a suspend-lambda
        // parameter and then branches (try/catch, conditional throw) corrupts the CPS
        // state machine at the call site. Such functions compile as standalone CPS
        // coroutines instead, which handle post-suspension control flow correctly.
        let hasLambdaParam = params.contains { param in
            if case .functionType = sema.types.kind(of: param.type) { return true }
            return false
        }
        let hasNoInlineAnnotation = function.annotations.contains { ann in
            ann.name == "NoInline" || ann.name == "kotlin.native.NoInline"
        }
        let autoInline = hasLambdaParam && !function.isSuspend && !hasNoInlineAnnotation
        let effectiveInline: Bool = function.isInline || autoInline
        let isInlineOnly = !function.isInline && autoInline
        let kirID = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: function.name, params: params,
            returnType: returnType, body: Array(body),
            isSuspend: function.isSuspend, isInline: effectiveInline, isInlineOnly: isInlineOnly,
            isTailrec: function.isTailrec,
            sourceRange: function.range
        )))
        var declIDs: [KIRDeclID] = [kirID]
        appendDefaultStub(symbol: symbol, function: function, signature: signature, shared: shared, declIDs: &declIDs)
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()
        ctx.setCurrentFunctionSymbol(nil)
        return declIDs
    }

    // MARK: - Parameter building

    private func buildFunDeclParams(
        _ function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature?,
        shared: KIRLoweringSharedContext
    ) -> [KIRParameter] {
        let sema = shared.sema
        let arena = shared.arena
        var params: [KIRParameter] = []
        if let signature {
            if let receiverType = signature.receiverType {
                let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                ctx.setImplicitReceiver(
                    symbol: receiverSymbol,
                    exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                )
            }
            let isVararg = callSupportLowerer.normalizeBoolFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count)
            for (index, (paramSymbol, paramType)) in zip(signature.valueParameterSymbols, signature.parameterTypes).enumerated() {
                let effectiveType: TypeID
                if index < isVararg.count, isVararg[index] {
                    // Vararg parameters are passed as lists at the call site.
                    // Use List<T> type so the lowering pass can correctly
                    // classify the parameter as a collection expression.
                    let interner = shared.interner
                    let listFQName: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("List"),
                    ]
                    if let listSymbol = sema.symbols.lookup(fqName: listFQName) {
                        effectiveType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(paramType)],
                            nullability: .nonNull
                        )))
                    } else {
                        effectiveType = paramType
                    }
                } else {
                    effectiveType = paramType
                }
                params.append(KIRParameter(symbol: paramSymbol, type: effectiveType))
            }
        }
        if function.isInline, let signature, !signature.reifiedTypeParameterIndices.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            for index in signature.reifiedTypeParameterIndices.sorted() {
                guard index < signature.typeParameterSymbols.count else { continue }
                let typeParamSymbol = signature.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                params.append(KIRParameter(symbol: tokenSymbol, type: intType))
            }
        }
        return params
    }

    // MARK: - Default stub

    private func appendDefaultStub(
        symbol: SymbolID,
        function: FunDecl,
        signature: FunctionSignature?,
        shared: KIRLoweringSharedContext,
        declIDs: inout [KIRDeclID]
    ) {
        if let defaults = ctx.defaultArguments(for: symbol), let sig = signature {
            let stubID = callSupportLowerer.generateDefaultStubFunction(
                originalSymbol: symbol, originalName: function.name,
                signature: sig, defaultExpressions: defaults, shared: shared
            )
            declIDs.append(stubID)
        }
    }

    // MARK: - Body lowering

    private func lowerFunDeclBody(
        _ function: FunDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        switch function.body {
        case let .block(exprIDs, _):
            lowerFunDeclBlockBody(exprIDs: exprIDs, shared: shared, body: &body)
        case let .expr(exprID, _):
            let value = lowerExpr(exprID, shared: shared, emit: &body)
            body.append(.returnValue(value))
        case .unit:
            body.append(.returnUnit)
        }
    }

    private func lowerFunDeclBlockBody(
        exprIDs: [ExprID],
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        var terminatedByReturn = false
        for exprID in exprIDs {
            if let expr = ast.arena.expr(exprID), case let .returnExpr(value, _, _) = expr {
                if let value {
                    let lowered = lowerExpr(value, shared: shared, emit: &body)
                    body.append(.returnValue(lowered))
                } else {
                    body.append(.returnUnit)
                }
                terminatedByReturn = true
                break
            }
            if let expr = ast.arena.expr(exprID), case .throwExpr = expr {
                _ = lowerExpr(exprID, shared: shared, emit: &body)
                terminatedByReturn = true
                break
            }
            let lowered = lowerExpr(exprID, shared: shared, emit: &body)
            if controlFlowLowerer.isTerminatedExpr(lowered, arena: shared.arena, sema: sema) {
                terminatedByReturn = true
                break
            }
        }
        if !terminatedByReturn {
            body.append(.returnUnit)
        }
    }

    private func bindFunctionParameterLocals(
        params: [KIRParameter],
        body: inout KIRLoweringEmitContext,
        arena: KIRArena
    ) {
        if let receiverBinding = ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
            ctx.setLocalValue(receiverBinding.exprID, for: receiverBinding.symbol)
        }

        for param in params where param.symbol != ctx.activeImplicitReceiverSymbol() {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.setLocalValue(paramExpr, for: param.symbol)
        }
    }

    /// True when `symbol` is an extension whose receiver is `kotlin.collections.List`.
    private func isListReceiverFunction(
        symbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let receiverType = sema.symbols.functionSignature(for: symbol)?.receiverType,
              case let .classType(classType) = sema.types.kind(of: receiverType),
              let receiverName = sema.symbols.symbol(classType.classSymbol)?.fqName
        else {
            return false
        }
        return receiverName == [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
    }

    private func isRuntimeBackedBundledStdlibSourceFunction(
        symbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner,
        sourceManager: SourceManager
    ) -> Bool {
        guard let symbolInfo = sema.symbols.symbol(symbol) else {
            return false
        }
        let fileID = sema.symbols.sourceFileID(for: symbol) ?? symbolInfo.declSite?.start.file
        guard let fileID,
              sourceManager.origin(of: fileID)?.isBundledStdlib == true
        else {
            return false
        }
        guard symbolInfo.fqName.count >= 3 else {
            return false
        }

        let packageFQName = Array(symbolInfo.fqName.dropLast())
        let kotlinComparisonsPackage = [
            interner.intern("kotlin"),
            interner.intern("comparisons"),
        ]
        let name = interner.resolve(symbolInfo.name)
        if packageFQName == kotlinComparisonsPackage {
            // Calls to these source-backed declarations are lowered by
            // CallLowerer+StdlibComparisons rather than by emitting the
            // declaration bodies into every consumer module.
            return name == "maxOf" || name == "minOf"
        }

        let kotlinCollectionsPackage = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        if packageFQName == kotlinCollectionsPackage {
            // Remaining collection factory call sites are lowered by
            // CallLowerer+CollectionFactoryCalls and CollectionLiteralLoweringPass
            // directly to __kk_* runtime ABI, so their source bodies must not be emitted.
            switch name {
            case "emptyList", "listOf", "mutableListOf", "arrayListOf",
                 "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf",
                 "emptyMap", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf":
                return true
            case "shuffled":
                // List overloads still have dedicated runtime lowering; Set and
                // Iterable overloads remain ordinary source declarations.
                return isListReceiverFunction(symbol: symbol, sema: sema, interner: interner)
            default:
                return false
            }
        }

        let kotlinTextPackage = [
            interner.intern("kotlin"),
            interner.intern("text"),
        ]
        if packageFQName == kotlinTextPackage {
            // The String indent/format helpers are pure Kotlin; only the
            // private __kk_string_* bridges are external and skipped by the
            // external-function path. Public functions must be lowered so user
            // calls dispatch through the source declarations.
            return false
        }

        let kotlinTimePackage = [
            interner.intern("kotlin"),
            interner.intern("time"),
        ]
        if packageFQName == kotlinTimePackage {
            return false
        }

        return false
    }
}
