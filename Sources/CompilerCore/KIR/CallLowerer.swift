import RuntimeABI

final class CallLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    /// True when the resolved callee is a bundled Kotlin source declaration
    /// (is a bundled/user source declaration or an imported library symbol),
    /// meaning the lowering path should not rewrite it to a `kk_*` runtime helper.
    private func isSourceBacked(_ symbol: SymbolID?, sema: SemaModule) -> Bool {
        guard let symbol else { return false }
        return sema.symbols.isSourceBackedSymbol(symbol)
    }

    /// Returns whether a direct lambda argument may use a label-free return to
    /// leave the caller. Kotlin permits this only for function-type parameters
    /// of inline functions that are neither `crossinline` nor `noinline`.
    func allowsNonLocalReturn(
        argumentExpr: ExprID,
        argumentIndex: Int,
        ast: ASTModule,
        sema: SemaModule,
        callBinding: CallBinding?,
        chosen: SymbolID?
    ) -> Bool {
        guard case .lambdaLiteral = ast.arena.expr(argumentExpr),
              let chosen,
              sema.symbols.symbol(chosen)?.flags.contains(.inlineFunction) == true,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return false
        }
        let parameterIndex = callBinding?.parameterMapping[argumentIndex] ?? argumentIndex
        guard signature.parameterTypes.indices.contains(parameterIndex) else {
            return false
        }
        let parameterType = signature.parameterTypes[parameterIndex]
        guard case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) else {
            return false
        }
        // Older synthetic/imported signatures may not carry the parallel flag
        // array. Preserve their historical behavior conservatively.
        guard signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex) else {
            return true
        }
        return signature.valueParameterAllowsNonLocalReturn[parameterIndex]
    }

    /// True when the call resolved to the stdlib `kotlin.contextOf` intrinsic.
    /// A user-declared `contextOf()` resolves to its own symbol and must keep
    /// normal call lowering instead of being replaced by a context receiver.
    private func isStdlibContextOfCall(
        _ exprID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .symbol(symbol)? = sema.bindings.callableTarget(for: exprID),
              let resolved = sema.symbols.symbol(symbol)
        else {
            return false
        }
        return resolved.fqName.map { interner.resolve($0) } == ["kotlin", "contextOf"]
    }

    /// Returns the `StringBuilder` class symbol when `symbolID` is one of its
    /// constructors, so callers can both gate on "is this a StringBuilder
    /// construction" and reuse the owner symbol for itable registration
    /// without a second lookup.
    private func stringBuilderConstructorOwner(
        _ symbolID: SymbolID?,
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> SymbolID? {
        guard let symbolID,
              sema.symbols.symbol(symbolID)?.kind == .constructor,
              let ownerSymbol = sema.symbols.parentSymbol(for: symbolID),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              knownNames.isStringBuilderSymbol(ownerInfo)
        else {
            return nil
        }
        return ownerSymbol
    }

    /// True for the compiler-provided `kotlin.Any.<init>()`. Its constructor
    /// has no body; the normal constructor path already allocates and registers
    /// the object, so emitting a second call would create an undefined callee.
    private func isSyntheticAnyConstructor(
        _ symbolID: SymbolID?,
        sema: SemaModule
    ) -> Bool {
        guard let symbolID,
              let constructor = sema.symbols.symbol(symbolID),
              constructor.kind == .constructor,
              constructor.flags.contains(.synthetic),
              let ownerSymbol = sema.symbols.parentSymbol(for: symbolID)
        else {
            return false
        }
        return ownerSymbol == sema.types.anyClassSymbol
    }

    private func lowerStringBuilderConstructorCall(
        finalArgIDs: [KIRExprID],
        resultType: TypeID,
        nominalSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let result = arena.appendTemporary(type: resultType)
        let runtimeCallee: InternedString
        let runtimeArgs: [KIRExprID]
        let canThrow: Bool
        let firstArgType = finalArgIDs.first.flatMap { arena.exprType($0) }
        if let firstArg = finalArgIDs.first,
           let firstArgType,
           sema.types.isSubtype(sema.types.makeNonNullable(firstArgType), sema.types.stringType)
        {
            runtimeCallee = interner.intern("__kk_string_builder_new_from_string_flat")
            runtimeArgs = [firstArg]
            canThrow = false
        } else if let firstArg = finalArgIDs.first,
                  let firstArgType,
                  sema.types.isSubtype(sema.types.makeNonNullable(firstArgType), sema.types.intType)
        {
            // BUG-165: StringBuilder(capacity: Int) has no Kotlin-level body
            // to validate the argument itself (see StringBuilder.kt), so a
            // negative capacity must be rejected here — matching
            // kk_array_new_checked's precedent for the same
            // ignored-negative-size failure mode.
            runtimeCallee = interner.intern("__kk_string_builder_new_capacity_checked")
            runtimeArgs = [firstArg]
            canThrow = true
        } else {
            runtimeCallee = interner.intern("__kk_string_builder_new")
            runtimeArgs = []
            canThrow = false
        }
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: runtimeArgs,
            result: result,
            canThrow: canThrow,
            thrownResult: nil
        ))
        // BUG-166: StringBuilder instances bypass the normal kk_object_new
        // construction path (see the BUG-044 comment in RuntimeStringBuilder.swift),
        // so they never receive the itable registrations a regular class
        // constructor gets from KIRLoweringDriver+ObjectInitializer.swift.
        // Without this, dispatching a call through an Appendable/CharSequence-typed
        // reference to a StringBuilder finds no itable entry and panics with
        // KSWIFTK-RUNTIME-0001 ("method not found in vtable/itable") even though
        // `is`/`as` checks (registered separately in runtimeRegisterStringBuilderType)
        // succeed.
        appendObjectItableMethodRegistrations(
            objectValue: result,
            nominalSymbol: nominalSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        return result
    }

    /// True for synthetic runtime-backed factory constructors that allocate
    /// their own object (atomic scalar boxes and built-in exception classes).
    private func isAtomicScalarConstructor(
        _ symbolID: SymbolID?,
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> Bool {
        guard let symbolID,
              sema.symbols.symbol(symbolID)?.kind == .constructor,
              let ownerSymbol = sema.symbols.parentSymbol(for: symbolID),
              let ownerInfo = sema.symbols.symbol(ownerSymbol)
        else {
            return false
        }
        return knownNames.isAtomicScalarFactorySymbol(ownerInfo)
            || isRuntimeFactoryConstructor(symbolID, sema: sema)
    }

    /// True when the constructor's runtime ABI entry point is a factory that
    /// allocates and returns an object handle (e.g. built-in exception
    /// `kk_*_exception_new_message`). Such constructors must not receive an
    /// implicit `this` allocated by `kk_object_new`.
    private func isRuntimeFactoryConstructor(
        _ symbolID: SymbolID,
        sema: SemaModule
    ) -> Bool {
        guard let externalLinkName = sema.symbols.externalLinkName(for: symbolID),
              !externalLinkName.isEmpty,
              let signature = sema.symbols.functionSignature(for: symbolID),
              let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == externalLinkName })
        else {
            return false
        }
        let abiValueParameters = spec.parameters.filter { parameter in
            !(spec.isThrowing && parameter.name == "outThrown" && parameter.type == .nullableIntptrPointer)
        }
        guard abiParametersMatchFactorySignature(abiValueParameters, signature, sema: sema) else {
            return false
        }
        switch spec.returnType {
        case .intptr, .opaquePointer, .nullableOpaquePointer:
            return true
        default:
            return false
        }
    }

    /// Checks whether the runtime ABI parameters (with the trailing `outThrown`
    /// slot removed) line up with the Kotlin-level constructor signature.
    /// A `String` parameter may be lowered as a single pointer/handle or as a
    /// flat 4-word aggregate (`data`, `length`, `byteCount`, `hash`) depending on
    /// the ABI entry point; the backend has its own tables for the latter, so
    /// this helper recognises the flat-string pattern so `String` factory
    /// constructors are not mistaken for normal `this`-accepting constructors.
    private func abiParametersMatchFactorySignature(
        _ abiParameters: [RuntimeABIParameter],
        _ signature: FunctionSignature,
        sema: SemaModule
    ) -> Bool {
        var abiIndex = 0
        for parameterType in signature.parameterTypes {
            guard abiIndex < abiParameters.count else { return false }
            // Function-valued constructor parameters are expanded to a raw
            // function pointer and closure handle before reaching a runtime
            // factory bridge (for example DeepRecursiveFunction's block).
            if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                guard abiIndex + 1 < abiParameters.count,
                      abiParameters[abiIndex].type == .intptr,
                      abiParameters[abiIndex + 1].type == .intptr
                else {
                    return false
                }
                abiIndex += 2
                continue
            }
            if isFlatStringGroup(at: abiIndex, in: abiParameters) {
                abiIndex += 4
            } else {
                abiIndex += 1
            }
        }
        return abiIndex == abiParameters.count
    }

    private func hasFunctionValueParameter(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
            return false
        }
        return signature.parameterTypes.contains { parameterType in
            if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                return true
            }
            return false
        }
    }

    private func isFlatStringGroup(
        at index: Int,
        in parameters: [RuntimeABIParameter]
    ) -> Bool {
        guard index + 3 < parameters.count else { return false }
        let dataParam = parameters[index]
        let lengthParam = parameters[index + 1]
        let byteCountParam = parameters[index + 2]
        let hashParam = parameters[index + 3]
        guard dataParam.type == .nullableConstUInt8Pointer,
              lengthParam.type == .intptr,
              byteCountParam.type == .intptr,
              hashParam.type == .intptr
        else {
            return false
        }
        // Unprefixed flat-string quartet used by many single-string entry points.
        if dataParam.name == "data"
            && lengthParam.name == "length"
            && byteCountParam.name == "byteCount"
            && hashParam.name == "hash"
        {
            return true
        }
        guard dataParam.name.hasSuffix("Data") else { return false }
        let prefix = String(dataParam.name.dropLast(4))
        return lengthParam.name == "\(prefix)Length"
            && byteCountParam.name == "\(prefix)ByteCount"
            && hashParam.name == "\(prefix)Hash"
    }

    private func lowerAtomicScalarConstructorCall(
        constructorSymbol: SymbolID,
        finalArgIDs: [KIRExprID],
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let result = arena.appendTemporary(type: resultType)
        // The runtime factory (e.g. `kk_atomic_int_create`)
        // allocates the box itself; we must not precede it with `kk_object_new`
        // and an implicit `this` argument.
        let callee = sema.symbols.externalLinkName(for: constructorSymbol)
            .flatMap { name in name.isEmpty ? nil : interner.intern(name) }
            ?? interner.intern("__kk_atomic_unknown_create")
        let canThrow = sema.symbols.functionSignature(for: constructorSymbol)?.canThrow ?? false
        // Keep the constructor symbol on the call so ABI lowering can resolve the
        // FunctionSignature (e.g. type-parameter parameters for Pair/Triple) while
        // the runtime factory callee handles allocation directly.
        instructions.append(.call(
            symbol: constructorSymbol,
            callee: callee,
            arguments: finalArgIDs,
            result: result,
            canThrow: canThrow,
            thrownResult: nil
        ))
        return result
    }


    // swiftlint:disable:next cyclomatic_complexity
    func lowerCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // SAM constructor calls: `Transformer { ... }` — the single lambda
        // argument is already marked as a SAM conversion and no call binding
        // exists for the constructor (the callee name is the fun interface itself).
        // Lower the lambda directly; the SAM wrapper is produced by LambdaLowerer.
        // A regular function call with a single SAM-converted argument (e.g.
        // `useOp(::myCompare)`) must still call the function, so require the
        // absence of a call binding here.
        if args.count == 1,
           sema.bindings.isSamConversion(args[0].expr),
           sema.bindings.callBinding(for: exprID) == nil
        {
            return driver.lowerExpr(
                args[0].expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // Invoke operator calls are lowered as member calls: the callee expr
        // becomes the receiver and the invoke method is the callee.
        if sema.bindings.isInvokeOperatorCall(exprID) {
            let invokeName = interner.intern("invoke")
            return lowerMemberCallExpr(
                exprID,
                receiverExpr: calleeExpr,
                calleeName: invokeName,
                args: args,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        if let loweredSuspendIntrinsic = lowerSuspendCoroutineUninterceptedOrReturnCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredSuspendIntrinsic
        }

        if let loweredRepeat = lowerRepeatCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredRepeat
        }

        if let loweredArrayConstructor = lowerArrayConstructorCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredArrayConstructor
        }

        if let loweredAtomicIntArrayFactory = lowerAtomicIntArrayFactoryCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredAtomicIntArrayFactory
        }

        if let loweredAtomicLongArrayFactory = lowerAtomicLongArrayFactoryCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredAtomicLongArrayFactory
        }

        if let loweredEnumValues = lowerEnumValuesCallExpr(
            exprID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredEnumValues
        }

        if let loweredEnumEntries = lowerEnumEntriesCallExpr(
            exprID,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredEnumEntries
        }

        if let loweredEnumValueOf = lowerEnumValueOfCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredEnumValueOf
        }

        // REFL-005: typeOf<T>() — reified inline function returning KType
        if let loweredTypeOf = lowerTypeOfCallExpr(
            exprID,
            calleeExpr: calleeExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredTypeOf
        }

        if let loweredComparison = lowerComparisonSpecialCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredComparison
        }

        if args.isEmpty,
           let callee = ast.arena.expr(calleeExpr),
           case let .nameRef(calleeName, _) = callee,
           calleeName == interner.intern("contextOf"),
           isStdlibContextOfCall(exprID, sema: sema, interner: interner)
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            if let contextValue = driver.ctx.contextReceiverValue(matching: boundType, sema: sema) {
                return contextValue
            }
            let fallback = arena.appendExpr(.unit, type: boundType)
            instructions.append(.constValue(result: fallback, value: .unit))
            return fallback
        }

        // --- Context helper: context(with, block) (STDLIB-KOTLIN-ROOT-CTX-001) ---
        if let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
           scopeKind == .scopeContext,
           args.count >= 2,
           args.count <= 23
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let loweredContextArguments = args.dropLast().map { contextArgument in
                driver.lowerExpr(
                    contextArgument.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[args.count - 1].expr) {
                let contextReceiverValues = zip(args.dropLast(), loweredContextArguments).map { argument, loweredExpr in
                    KIRLoweringContext.ContextReceiverValue(
                        type: sema.bindings.exprTypes[argument.expr] ?? sema.types.anyType,
                        exprID: loweredExpr
                    )
                }
                return driver.ctx.withContextReceiverValues(contextReceiverValues) {
                    driver.lowerExpr(
                        bodyExpr,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
            }
            let previousLambdaAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
                argumentExpr: args[args.count - 1].expr,
                argumentIndex: args.count - 1,
                ast: ast,
                sema: sema,
                callBinding: sema.bindings.callBinding(for: exprID),
                chosen: sema.bindings.callBinding(for: exprID)?.chosenCallee
            )
            let loweredLambdaID = driver.lowerExpr(
                args[args.count - 1].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            driver.ctx.pendingLambdaNonLocalReturnAllowance = previousLambdaAllowance

            let result = arena.appendTemporary(type: boundType
            )
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: info.captureArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                emitNonThrowingCall(
                    callee: interner.intern("invoke"),
                    arg: loweredLambdaID,
                    result: result,
                    into: &instructions
                )
            }
            return result
        }

        let boundType = sema.bindings.exprTypes[exprID]
        let loweredCalleeExprID = driver.lowerExpr(
            calleeExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let callBinding = sema.bindings.callBindings[exprID]
        let chosen = callBinding?.chosenCallee
        let loweredCallable = driver.ctx.callableValueInfo(for: loweredCalleeExprID)
            ?? chosen.flatMap { symbol in
                driver.ctx.localValue(for: symbol).flatMap { driver.ctx.callableValueInfo(for: $0) }
            }
        let callableValueCallBinding = sema.bindings.callableValueCalls[exprID]
        let sourceCalleeName: InternedString = if let callee = ast.arena.expr(calleeExpr), case let .nameRef(name, _) = callee {
            name
        } else if let loweredCallable {
            loweredCallable.callee
        } else {
            interner.intern("<unknown>")
        }
        let loweredArgIDs = args.enumerated().map { argumentIndex, argument in
            let previousAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
                argumentExpr: argument.expr,
                argumentIndex: argumentIndex,
                ast: ast,
                sema: sema,
                callBinding: callBinding,
                chosen: chosen
            )
            defer {
                driver.ctx.pendingLambdaNonLocalReturnAllowance = previousAllowance
            }
            return driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let knownNames = KnownCompilerNames(interner: interner)
        // buildList, buildSet, and buildMap are fully Kotlinized (KSP-622, KSP-623)
        // and no longer use builder-DSL runtime lowering.
        if let loweredToList = tryLowerCollectionToListCall(
            sourceCalleeName: sourceCalleeName,
            args: args,
            loweredArgIDs: loweredArgIDs,
            boundType: boundType,
            sema: sema,
            arena: arena,
            interner: interner,
            knownNames: knownNames,
            instructions: &instructions
        ) {
            return loweredToList
        }
        if let loweredCollectionFactory = tryLowerCollectionFactoryCall(
            sourceCalleeName: sourceCalleeName,
            args: args,
            loweredArgIDs: loweredArgIDs,
            chosenCallee: chosen,
            boundType: boundType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return loweredCollectionFactory
        }
        if args.count == 1,
           let loweredNumericConversion = lowerTopLevelNumericConversionCall(
               sourceCalleeName: sourceCalleeName,
               argumentExpr: args[0].expr,
               loweredArgumentID: loweredArgIDs[0],
               boundType: boundType ?? sema.types.anyType,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return loweredNumericConversion
        }
        return lowerResolvedCallBody(
            exprID,
            args: args,
            loweredArgIDs: loweredArgIDs,
            chosen: chosen,
            callBinding: callBinding,
            callableValueCallBinding: callableValueCallBinding,
            loweredCallable: loweredCallable,
            loweredCalleeExprID: loweredCalleeExprID,
            sourceCalleeName: sourceCalleeName,
            boundType: boundType,
            knownNames: knownNames,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }

    /// Emits the call/allocation instructions for an already-resolved call
    /// target: the callee (function, constructor, or callable value) and its
    /// arguments are already lowered by the time this runs. Shared by
    /// `lowerCallExpr` (plain `.call` nodes, which supply
    /// `loweredCalleeExprID`/`loweredCallable`/`callableValueCallBinding`
    /// derived from lowering `calleeExpr`) and
    /// `tryLowerFQNTopLevelResolvedCall` (namespace-qualified function/
    /// constructor calls reached via `.memberCall`, e.g.
    /// `kotlin.math.abs(x)` or `kotlin.text.StringBuilder()`, which have no
    /// callee expression to lower at all — `chosen` and `callBinding` come
    /// directly from Sema's FQN top-level resolution, so
    /// `loweredCalleeExprID`/`loweredCallable`/`callableValueCallBinding` are
    /// always nil there).
    // swiftlint:disable:next cyclomatic_complexity
    func lowerResolvedCallBody(
        _ exprID: ExprID,
        args: [CallArgument],
        loweredArgIDs: [KIRExprID],
        chosen: SymbolID?,
        callBinding: CallBinding?,
        callableValueCallBinding: CallableValueCallBinding?,
        loweredCallable: KIRCallableValueInfo?,
        loweredCalleeExprID: KIRExprID?,
        sourceCalleeName: InternedString,
        boundType: TypeID?,
        knownNames: KnownCompilerNames,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        let callNormalized: NormalizedCallResult = if callBinding != nil {
            driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                spreadFlags: args.map(\.isSpread),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            NormalizedCallResult(
                arguments: normalizedCallableValueArguments(
                    providedArguments: loweredArgIDs,
                    callableValueCallBinding: callableValueCallBinding,
                    sema: sema
                ),
                defaultMask: 0
            )
        }
        var finalArgIDs = callNormalized.arguments
        var implicitReceiverDispatch: (receiver: KIRExprID, kind: KIRDispatchKind)?
        // Compiler-generated lambdas/local functions use the compiler ABI
        // (including the hidden thrown channel), so route them through their
        // lowered symbol directly instead of Swift closure helpers.
        let callableInvokeCallee: InternedString? = if loweredCallable == nil {
            runtimeCallableInvokeCallee(
                callableValueCallBinding: callableValueCallBinding,
                sema: sema,
                interner: interner
            )
        } else {
            nil
        }
        let isAtomicFactory = chosen.map {
            isAtomicScalarConstructor($0, sema: sema, knownNames: knownNames)
        } ?? false
        if callableInvokeCallee == nil,
           loweredCallable == nil,
           let stringBuilderOwnerSymbol = stringBuilderConstructorOwner(chosen, sema: sema, knownNames: knownNames)
        {
            return lowerStringBuilderConstructorCall(
                finalArgIDs: finalArgIDs,
                resultType: boundType ?? sema.types.anyType,
                nominalSymbol: stringBuilderOwnerSymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        if callableInvokeCallee == nil,
           loweredCallable == nil,
           let chosen,
           isAtomicFactory,
           !hasFunctionValueParameter(chosen, sema: sema)
        {
            return lowerAtomicScalarConstructorCall(
                constructorSymbol: chosen,
                finalArgIDs: finalArgIDs,
                resultType: boundType ?? sema.types.anyType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        if callableInvokeCallee != nil, let loweredCalleeExprID {
            finalArgIDs.insert(loweredCalleeExprID, at: 0)
            if let callableValueCallBinding,
               case let .functionType(functionType) = sema.types.kind(
                   of: sema.types.makeNonNullable(callableValueCallBinding.functionType)
               ),
               functionType.receiver != nil,
               let implicitReceiver = driver.ctx.activeImplicitReceiverExprID()
            {
                // A receiver-function value invoked as `block()` inside a
                // receiver scope uses the active implicit receiver as its
                // dispatch receiver (e.g. the bodies of T.run and T.apply).
                finalArgIDs.insert(implicitReceiver, at: 1)
            }
        }
        if callableInvokeCallee == nil, let loweredCallable {
            finalArgIDs.insert(contentsOf: loweredCallable.captureArguments, at: 0)
        } else if let chosen,
                  !isAtomicFactory,
                  sema.symbols.symbol(chosen)?.kind == .constructor
        {
            // Constructor calls need an allocated object as the implicit receiver (p0).
            // Allocate via kk_object_new(slotCount) and prepend it to the argument list.
            // Derive slot count from NominalLayout.instanceSizeWords of the owning class.
            let allocType = boundType ?? sema.types.anyType
            let intType = sema.types.make(.primitive(.int, .nonNull))
            var slotCount: Int64 = 1
            var ownerNominalSymbol: SymbolID?
            if let parentClassID = sema.symbols.parentSymbol(for: chosen),
               let layout = sema.symbols.nominalLayout(for: parentClassID)
            {
                ownerNominalSymbol = parentClassID
                slotCount = Int64(max(layout.instanceSizeWords, 1))
            }
            let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
            instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
            let classIDValue: Int64 = if let ownerNominalSymbol {
                RuntimeTypeCheckToken.stableNominalTypeID(symbol: ownerNominalSymbol, sema: sema, interner: interner)
            } else {
                0
            }
            let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
            instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
            let allocatedObj = arena.appendTemporary(type: allocType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: allocatedObj,
                canThrow: false,
                thrownResult: nil
            ))
            if let ownerNominalSymbol {
                if sema.symbols.symbol(ownerNominalSymbol)?.flags.contains(.dataType) == true {
                    let registerDataClassResult = arena.appendTemporary(type: intType)
                    emitNonThrowingCall(
                        callee: interner.intern("kk_runtime_register_data_class"),
                        arg: classIDExpr,
                        result: registerDataClassResult,
                        into: &instructions
                    )
                }
                let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: ownerNominalSymbol,
                    sema: sema,
                    interner: interner
                )
                appendNominalSupertypeEdgeRegistrations(
                    childSymbol: ownerNominalSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                appendObjectItableMethodRegistrations(
                    objectValue: allocatedObj,
                    nominalSymbol: ownerNominalSymbol,
                    driver: driver,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                // BUG-141: register interface property getters into the itable.
                appendObjectItablePropertyGetterRegistrations(
                    objectValue: allocatedObj,
                    nominalSymbol: ownerNominalSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                appendObjectVtableMethodRegistrations(
                    objectValue: allocatedObj,
                    nominalSymbol: ownerNominalSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                // REFL-005: Register KClass metadata for this nominal type.
                emitKClassMetadataRegistration(
                    objectSymbol: ownerNominalSymbol,
                    typeID: childTypeID,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                if let throwableSymbol = sema.symbols.lookup(
                    fqName: [interner.intern("kotlin"), interner.intern("Throwable")]
                ) {
                    let ownerType = sema.types.make(.classType(ClassType(
                        classSymbol: ownerNominalSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    let throwableType = sema.types.make(.classType(ClassType(
                        classSymbol: throwableSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    // Capture a Kotlin-defined Throwable subclass at allocation time,
                    // before its constructor body can observe the receiver.
                    if sema.types.isSubtype(ownerType, throwableType) {
                        let captureResult = arena.appendTemporary(type: intType)
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_throwable_captureStackTrace"),
                            arg: allocatedObj,
                            result: captureResult,
                            into: &instructions
                        )
                    }
                }
            }
            finalArgIDs.insert(allocatedObj, at: 0)
            if isSyntheticAnyConstructor(chosen, sema: sema) {
                // Any's implicit constructor is represented by allocation only;
                // there is no source or runtime constructor body to call.
                instructions.append(.copy(from: allocatedObj, to: result))
                return result
            }
        } else if let chosen,
                  let signature = sema.symbols.functionSignature(for: chosen),
                  signature.receiverType != nil
        {
            var implicitReceiver = driver.ctx.activeImplicitReceiverExprID()
            if implicitReceiver == nil,
               sema.bindings.isCoroutineScopeImplicitReceiverCall(exprID)
            {
                let receiver = arena.appendTemporary(type: signature.receiverType ?? sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_current_scope"),
                    arguments: [],
                    result: receiver,
                    canThrow: false,
                    thrownResult: nil
                ))
                implicitReceiver = receiver
            }
            if let implicitReceiver {
                finalArgIDs.insert(implicitReceiver, at: 0)
            }
            // An unqualified `compute()` inside a member body is `this.compute()`
            // and must dispatch through the receiver's vtable/itable exactly like
            // the explicit form: a subclass override, or a base-class
            // implementation of an interface method, is otherwise bypassed.
            if let implicitReceiver,
               sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true
            {
                implicitReceiverDispatch = resolveVirtualDispatch(
                    callee: chosen,
                    receiverTypeID: arena.exprType(implicitReceiver),
                    sema: sema,
                    interner: interner
                ).map { (receiver: implicitReceiver, kind: $0) }
            }
        }
        if loweredCallable == nil {
            materializeSourceBackedFunctionValueArguments(
                chosenCallee: chosen,
                sourceArgExprs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
        }
        if loweredCallable == nil, let chosen {
            finalArgIDs = appendClosureArgumentsIfNeeded(
                finalArgIDs,
                originalArgs: args,
                chosenCallee: chosen,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        // Inject callable value captures for coroutine launcher arguments.
        // When a suspend lambda/closure with captures is passed to a launcher
        // (runBlocking/launch/async), the capture values must be included in
        // the call arguments so the CoroutineLoweringPass can store them in
        // the continuation via launcherArgs and forward them through the thunk.
        // Guard on chosen == nil && loweredCallable == nil to avoid misfiring
        // on user-defined functions that happen to share a launcher name.
        // Only expand captures for the launcher entry function reference; the
        // remaining arguments are value args for the referenced suspend
        // function and should not be expanded. The entry reference is normally
        // arguments[0], but a dispatcher-aware `launch(dispatcher) { ... }`
        // carries the dispatcher at arguments[0] and the suspend lambda at
        // arguments[1] (matching rewriteLauncherCall's dispatcher-aware path),
        // so scan for the first argument that actually is a callable value and
        // insert its captures right after it.
        if loweredCallable == nil {
            let isSyntheticCoroutineLauncher: Bool = if let chosen,
                                                        let chosenInfo = sema.symbols.symbol(chosen)
            {
                chosenInfo.fqName == knownNames.kotlinxCoroutinesRunBlockingFQName
                    || chosenInfo.fqName == knownNames.kotlinxCoroutinesLaunchFQName
                    || chosenInfo.fqName == knownNames.kotlinxCoroutinesAsyncFQName
                    || chosenInfo.fqName == knownNames.kotlinxCoroutinesProduceFQName
            } else {
                true
            }
            if isSyntheticCoroutineLauncher,
               sourceCalleeName == knownNames.runBlocking
               || sourceCalleeName == knownNames.launch
               || sourceCalleeName == knownNames.async
               || sourceCalleeName == knownNames.produce
            {
                // A leading dispatcher (only valid for `launch`) pushes the
                // entry reference to index 1; otherwise it is index 0.
                let entryIndex = finalArgIDs.indices.first { index in
                    driver.ctx.callableValueInfo(for: finalArgIDs[index]) != nil
                }
                if let entryIndex,
                   entryIndex <= 1,
                   let callableInfo = driver.ctx.callableValueInfo(for: finalArgIDs[entryIndex]),
                   !callableInfo.captureArguments.isEmpty
                {
                    finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: entryIndex + 1)
                }
            }
        }
        if sourceCalleeName == knownNames.withContext,
           finalArgIDs.count >= 2,
           let callableInfo = driver.ctx.callableValueInfo(for: finalArgIDs[1]),
           !callableInfo.captureArguments.isEmpty
        {
            finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 2)
        }
        if callNormalized.defaultMask != 0,
           let chosen,
           (sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true ||
            sema.symbols.externalLinkName(for: driver.callSupportLowerer.defaultStubSymbol(for: chosen)) != nil)
        {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            appendDefaultMaskArgument(
                callNormalized.defaultMask,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            let stubName = interner.intern(interner.resolve(sourceCalleeName) + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: chosen)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            let loweredCalleeName: InternedString = if let callableInvokeCallee {
                callableInvokeCallee
            } else if let chosen,
                                                       let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                                                       !externalLinkName.isEmpty
            {
                interner.intern(externalLinkName)
            } else if let loweredCallable {
                loweredCallable.callee
            } else if chosen == nil {
                driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
                    for: sourceCalleeName,
                    argumentCount: finalArgIDs.count,
                    argumentTypes: finalArgIDs.map { arena.exprType($0) ?? sema.types.anyType },
                    interner: interner,
                    types: sema.types,
                    knownNames: knownNames
                ) ?? sourceCalleeName
            } else {
                sourceCalleeName
            }
            if loweredCalleeName == interner.intern("__kk_throwable_new"), finalArgIDs.isEmpty {
                // Throwable() and the zero-argument synthetic exception constructors
                // route here, but the runtime bridge still expects a nullable message
                // pointer. Pass the null sentinel so it defaults to "Throwable".
                let nullMessageExpr = arena.appendExpr(
                    .intLiteral(Int64.min),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: nullMessageExpr, value: .intLiteral(Int64.min)))
                finalArgIDs.append(nullMessageExpr)
            } else if loweredCalleeName == interner.intern("kk_coroutine_cancel_current"),
                      finalArgIDs.count == 1
            {
                // The synthetic one-argument `cancel(message)` overload lowers
                // to the same runtime ABI as the two-argument overload and
                // supplies a null cause implicitly.
                let nullCauseExpr = arena.appendExpr(
                    .intLiteral(0),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: nullCauseExpr, value: .intLiteral(0)))
                finalArgIDs.append(nullCauseExpr)
            } else if loweredCalleeName == interner.intern("kk_channel_send")
                || loweredCalleeName == interner.intern("kk_channel_receive")
                || loweredCalleeName == interner.intern("kk_mutex_lock")
                || loweredCalleeName == interner.intern("kk_semaphore_acquire")
            {
                // Implicit-receiver calls (e.g. `send(x)` inside a `produce { }`
                // block) reach this path instead of `emitMemberCallInstruction`,
                // which normally appends the zero continuation placeholder for
                // these callees. Without it the runtime ABI receives one fewer
                // argument than expected.
                let continuationExpr = arena.appendExpr(
                    .intLiteral(0),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
                finalArgIDs.append(continuationExpr)
            }
            let callCanThrow = needsThrownChannel(calleeName: loweredCalleeName, interner: interner)
            let thrownResult = callCanThrow
                ? arena.appendTemporary(type: sema.types.nullableAnyType
                )
                : nil
            // When calling a callable value (function-type local/parameter),
            // use its symbol so InlineLoweringPass can match it against lambda
            // parameter symbols and expand the lambda body in place.
            let callSymbol: SymbolID? = chosen ?? loweredCallable?.symbol ?? {
                if let binding = callableValueCallBinding,
                   case let .localValue(sym) = binding.target
                {
                    return sym
                }
                return nil
            }()
            if let implicitReceiverDispatch, finalArgIDs.first == implicitReceiverDispatch.receiver {
                instructions.append(.virtualCall(
                    symbol: callSymbol,
                    callee: loweredCalleeName,
                    receiver: implicitReceiverDispatch.receiver,
                    arguments: Array(finalArgIDs.dropFirst()),
                    result: result,
                    canThrow: callCanThrow,
                    thrownResult: thrownResult,
                    dispatch: implicitReceiverDispatch.kind
                ))
            } else {
                instructions.append(.call(
                    symbol: callSymbol,
                    callee: loweredCalleeName,
                    arguments: finalArgIDs,
                    result: result,
                    canThrow: callCanThrow,
                    thrownResult: thrownResult
                ))
            }
            if let thrownResult,
               shouldRethrowThrownChannelResult(calleeName: loweredCalleeName, interner: interner)
            {
                let continueLabel = driver.ctx.makeLoopLabel()
                let rethrowLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
                instructions.append(.jump(continueLabel))
                instructions.append(.label(rethrowLabel))
                instructions.append(.rethrow(value: thrownResult))
                instructions.append(.label(continueLabel))
            }
        }
        return result
    }

    func runtimeCallableInvokeCallee(
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard let callableValueCallBinding else {
            return nil
        }
        let nonNullFunctionType = sema.types.makeNonNullable(callableValueCallBinding.functionType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullFunctionType) else {
            return nil
        }

        let valueArity = functionType.params.count + (functionType.receiver == nil ? 0 : 1)

        if functionType.isSuspend {
            switch valueArity {
            case 0:
                return interner.intern("kk_suspend_function_invoke_0")
            case 1:
                return interner.intern("kk_suspend_function_invoke")
            case 2:
                return interner.intern("kk_suspend_function_invoke_2")
            default:
                return nil
            }
        }

        switch valueArity {
        case 0:
            return interner.intern("kk_function_invoke_0")
        case 1:
            return interner.intern("kk_function_invoke")
        case 2:
            return interner.intern("kk_function_invoke_2")
        case 3:
            return interner.intern("kk_function_invoke_3")
        case 4:
            return interner.intern("kk_function_invoke_4")
        default:
            return nil
        }
    }

    /// Returns true if the callee is a runtime function that requires a thrown
    /// channel (outThrown) parameter in its ABI. This ensures the codegen
    /// appends the extra `intptr_t * _Nullable` slot.
    func needsThrownChannel(calleeName: InternedString, interner: StringInterner) -> Bool {
        let name = interner.resolve(calleeName)
        return [
            "kk_runtime_result_get_or_else",
            "kk_runtime_result_get_or_throw",
            "kk_runtime_result_map",
            "kk_runtime_result_fold",
            "kk_runtime_result_on_success",
            "kk_runtime_result_on_failure",
            "kk_runtime_result_recover",
            "kk_runtime_result_recover_catching",
            "kk_runtime_result_run_catching",
            "__kk_synchronized",
            "__kk_string_builder_new_capacity_checked",
            "__kk_mutable_list_add",
            "__kk_mutable_set_add",
            "__kk_mutable_map_put",
            "__kk_enum_entries_get",
            "kk_iterable_iterator",
        ].contains(name)
    }

    func shouldRethrowThrownChannelResult(calleeName: InternedString, interner: StringInterner) -> Bool {
        [
            "kk_runtime_result_get_or_else",
            "kk_runtime_result_get_or_throw",
            "kk_runtime_result_map",
            "kk_runtime_result_fold",
            "kk_runtime_result_on_success",
            "kk_runtime_result_on_failure",
            "kk_runtime_result_recover",
            "__kk_synchronized",
            "__kk_enum_entries_get",
            "kk_iterable_iterator",
        ].contains(interner.resolve(calleeName))
    }

    private func tryLowerCollectionToListCall(
        sourceCalleeName: InternedString,
        args: [CallArgument],
        loweredArgIDs: [KIRExprID],
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        knownNames: KnownCompilerNames,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sourceCalleeName == interner.intern("toList"),
              args.count == 1,
              sema.bindings.isCollectionExpr(args[0].expr)
        else {
            return nil
        }

        let argumentType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
        let nonNullArgumentType = sema.types.makeNonNullable(argumentType)
        let runtimeCallee: InternedString? = if let (_, symbol) = resolveClassTypeSymbol(nonNullArgumentType, sema: sema)
        {
            switch symbol.name {
            case knownNames.list, knownNames.mutableList:
                nil
            case interner.intern("Range"), interner.intern("IntRange"):
                interner.intern("kk_range_toList")
            case interner.intern("LongRange"):
                interner.intern("kk_long_range_toList")
            case interner.intern("ULongRange"):
                interner.intern("kk_ulong_range_toList")
            case interner.intern("CharRange"), interner.intern("CharProgression"):
                interner.intern("kk_char_range_toList")
            default:
                interner.intern("kk_sequence_to_list")
            }
        } else {
            interner.intern("kk_sequence_to_list")
        }
        guard let runtimeCallee else {
            return loweredArgIDs[0]
        }

        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: loweredArgIDs,
            result: result,
            canThrow: runtimeCallee == interner.intern("kk_sequence_to_list"),
            thrownResult: nil
        ))
        return result
    }

    func callableRequiresThrownChannel(_ lambdaSymbol: SymbolID, arena: KIRArena) -> Bool {
        guard let function = arena.function(for: lambdaSymbol) else {
            return false
        }
        for instruction in function.body {
            switch instruction {
            case let .call(_, _, _, _, canThrow, _, _, _),
                 let .virtualCall(_, _, _, _, _, canThrow, _, _):
                if canThrow {
                    return true
                }
            case .rethrow:
                return true
            default:
                continue
            }
        }
        return false
    }

    func appendReifiedTypeTokens(
        chosenCallee: SymbolID?,
        callBinding: CallBinding?,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard let chosenCallee,
              let callBinding,
              let signature = sema.symbols.functionSignature(for: chosenCallee),
              !signature.reifiedTypeParameterIndices.isEmpty
        else {
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        for index in signature.reifiedTypeParameterIndices.sorted() {
            let concreteType = index < callBinding.substitutedTypeArguments.count
                ? callBinding.substitutedTypeArguments[index]
                : sema.types.anyType
            let encodedToken = RuntimeTypeCheckToken.encode(type: concreteType, sema: sema, interner: interner)
            let tokenExpr = arena.appendExpr(
                .intLiteral(encodedToken),
                type: intType
            )
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            arguments.append(tokenExpr)
        }
    }

    func appendDefaultMaskArgument(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let maskExpr = arena.appendExpr(.intLiteral(Int64(defaultMask)), type: intType)
        instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(defaultMask))))
        arguments.append(maskExpr)
    }

    func normalizedCallableValueArguments(
        providedArguments: [KIRExprID],
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule
    ) -> [KIRExprID] {
        guard let callableValueCallBinding,
              case let .functionType(functionType) = sema.types.kind(of: callableValueCallBinding.functionType)
        else {
            return providedArguments
        }

        let parameterCount = functionType.params.count
        guard parameterCount == providedArguments.count,
              !callableValueCallBinding.parameterMapping.isEmpty
        else {
            return providedArguments
        }

        var reordered = Array(repeating: KIRExprID.invalid, count: parameterCount)
        for (argIndex, paramIndex) in callableValueCallBinding.parameterMapping {
            guard argIndex >= 0,
                  argIndex < providedArguments.count,
                  paramIndex >= 0,
                  paramIndex < parameterCount,
                  reordered[paramIndex] == .invalid
            else {
                return providedArguments
            }
            reordered[paramIndex] = providedArguments[argIndex]
        }

        guard !reordered.contains(.invalid) else {
            return providedArguments
        }
        return reordered
    }

    func recoverMemberCallBinding(
        exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        argumentExprs: [ExprID],
        sema: SemaModule
    ) -> CallBinding? {
        let existingBinding = sema.bindings.callBindings[exprID]
        if let existing = existingBinding,
           existing.chosenCallee != .invalid,
           sema.symbols.symbol(existing.chosenCallee) != nil
        {
            return existing
        }
        if case let .symbol(symbol)? = sema.bindings.callableTarget(for: exprID),
           symbol != .invalid,
           let signature = sema.symbols.functionSignature(for: symbol),
           signature.receiverType != nil
        {
            let parameterMapping = normalizedParameterMapping(
                existingBinding?.parameterMapping,
                argumentCount: argumentExprs.count
            )
            return CallBinding(
                chosenCallee: symbol,
                substitutedTypeArguments: [],
                parameterMapping: parameterMapping
            )
        }

        guard let receiverType = sema.bindings.exprTypes[receiverExpr] else {
            return nil
        }
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard let classType = resolveClassType(nonNullReceiverType, sema: sema) else {
            return nil
        }
        var ownerQueue: [SymbolID] = [classType.classSymbol]
        var visitedOwners: Set<SymbolID> = []
        var candidates: [SymbolID] = []
        while let owner = ownerQueue.first {
            ownerQueue.removeFirst()
            guard visitedOwners.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner
                else {
                    continue
                }
                candidates.append(candidate)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        if receiverType != nonNullReceiverType {
            candidates.append(contentsOf: extensionCandidates(
                named: calleeName,
                nonNullReceiverType: nonNullReceiverType,
                argumentCount: argumentExprs.count,
                sema: sema
            ))
        }
        candidates.sort(by: { $0.rawValue < $1.rawValue })
        guard !candidates.isEmpty else {
            return nil
        }

        let argumentTypes = argumentExprs.map { exprID in
            sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        }

        let matched = candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == argumentTypes.count
            else {
                return false
            }
            return zip(argumentTypes, signature.parameterTypes).allSatisfy { argumentType, parameterType in
                sema.types.isSubtype(argumentType, parameterType)
            }
        }

        guard let chosen = matched else {
            return nil
        }

        let parameterMapping = normalizedParameterMapping(
            existingBinding?.parameterMapping,
            argumentCount: argumentExprs.count
        )
        return CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: [],
            parameterMapping: parameterMapping
        )
    }

    /// Source-level extension functions and extension-property getters declared
    /// for `nonNullReceiverType`. Sema resolves those against the narrowed
    /// receiver, but a receiver whose static type stays nullable (a mutable
    /// local keeps its declared type across a null check) leaves no call
    /// binding behind, and only the bare source name would reach codegen.
    private func extensionCandidates(
        named calleeName: InternedString,
        nonNullReceiverType: TypeID,
        argumentCount: Int,
        sema: SemaModule
    ) -> [SymbolID] {
        func receiverMatches(_ candidate: SymbolID) -> Bool {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  signature.parameterTypes.count == argumentCount
            else {
                return false
            }
            return sema.types.isSubtype(
                nonNullReceiverType,
                sema.types.makeNonNullable(declaredReceiver)
            )
        }

        return sema.symbols.lookupByShortName(calleeName).compactMap { candidate in
            guard let symbol = sema.symbols.symbol(candidate) else {
                return nil
            }
            switch symbol.kind {
            case .function:
                return receiverMatches(candidate) ? candidate : nil
            case .property:
                guard argumentCount == 0,
                      let getter = sema.symbols.extensionPropertyGetterAccessor(for: candidate),
                      receiverMatches(getter)
                else {
                    return nil
                }
                return getter
            default:
                return nil
            }
        }
    }

    private func normalizedParameterMapping(
        _ parameterMapping: [Int: Int]?,
        argumentCount: Int
    ) -> [Int: Int] {
        if let parameterMapping, !parameterMapping.isEmpty {
            return parameterMapping
        }
        var positionalMapping: [Int: Int] = [:]
        for index in 0 ..< argumentCount {
            positionalMapping[index] = index
        }
        return positionalMapping
    }

    private func lowerTopLevelNumericConversionCall(
        sourceCalleeName: InternedString,
        argumentExpr: ExprID,
        loweredArgumentID: KIRExprID,
        boundType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let receiverType = sema.types.makeNonNullable(sema.bindings.exprTypes[argumentExpr] ?? sema.types.anyType)
        let calleeStr = interner.resolve(sourceCalleeName)

        let runtimeCallee: InternedString? = switch (calleeStr, receiverType, boundType) {
        case ("toInt", sema.types.uintType, sema.types.intType): interner.intern("kk_uint_to_int")
        case ("toInt", sema.types.ulongType, sema.types.intType): interner.intern("kk_ulong_to_int")
        case ("toInt", sema.types.ubyteType, sema.types.intType): interner.intern("kk_ubyte_to_int")
        case ("toInt", sema.types.ushortType, sema.types.intType): interner.intern("kk_ushort_to_int")
        case ("toInt", sema.types.doubleType, sema.types.intType): interner.intern("__kk_double_to_int")
        case ("toInt", sema.types.floatType, sema.types.intType): interner.intern("__kk_float_to_int")
        case ("toInt", sema.types.charType, sema.types.intType): nil
        case ("toInt", sema.types.byteType, sema.types.intType): nil
        case ("toInt", sema.types.shortType, sema.types.intType): nil
        case ("toInt", sema.types.intType, sema.types.intType), ("toInt", sema.types.longType, sema.types.intType): nil
        case ("toLong", sema.types.intType, sema.types.longType): interner.intern("kk_int_to_long")
        case ("toLong", sema.types.uintType, sema.types.longType): interner.intern("kk_uint_to_long")
        case ("toLong", sema.types.ubyteType, sema.types.longType): interner.intern("kk_ubyte_to_long")
        case ("toLong", sema.types.ushortType, sema.types.longType): interner.intern("kk_ushort_to_long")
        case ("toLong", sema.types.doubleType, sema.types.longType): interner.intern("__kk_double_to_long")
        case ("toLong", sema.types.floatType, sema.types.longType): interner.intern("__kk_float_to_long")
        case ("toLong", sema.types.charType, sema.types.longType): nil
        case ("toLong", sema.types.byteType, sema.types.longType): nil
        case ("toLong", sema.types.shortType, sema.types.longType): nil
        case ("toLong", sema.types.longType, sema.types.longType), ("toLong", sema.types.ulongType, sema.types.longType): nil
        case ("toUInt", sema.types.intType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.longType, sema.types.uintType): interner.intern("kk_long_to_uint")
        case ("toUInt", sema.types.ubyteType, sema.types.uintType): interner.intern("kk_ubyte_to_uint")
        case ("toUInt", sema.types.ushortType, sema.types.uintType): interner.intern("kk_ushort_to_uint")
        case ("toUInt", sema.types.charType, sema.types.uintType): nil
        case ("toUInt", sema.types.byteType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.shortType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.uintType, sema.types.uintType), ("toUInt", sema.types.ulongType, sema.types.uintType): nil
        case ("toULong", sema.types.intType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.longType, sema.types.ulongType): interner.intern("kk_long_to_ulong")
        case ("toULong", sema.types.ubyteType, sema.types.ulongType): interner.intern("kk_ubyte_to_ulong")
        case ("toULong", sema.types.ushortType, sema.types.ulongType): interner.intern("kk_ushort_to_ulong")
        case ("toULong", sema.types.charType, sema.types.ulongType): nil
        case ("toULong", sema.types.byteType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.shortType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.uintType, sema.types.ulongType): interner.intern("kk_uint_to_ulong")
        case ("toULong", sema.types.ulongType, sema.types.ulongType): nil
        case ("toFloat", sema.types.intType, sema.types.floatType): interner.intern("kk_int_to_float")
        case ("toFloat", sema.types.longType, sema.types.floatType): interner.intern("kk_long_to_float")
        case ("toFloat", sema.types.doubleType, sema.types.floatType): interner.intern("kk_double_to_float")
        case ("toFloat", sema.types.floatType, sema.types.floatType): nil
        case ("toDouble", sema.types.longType, sema.types.doubleType): interner.intern("kk_long_to_double")
        case ("toDouble", sema.types.floatType, sema.types.doubleType): interner.intern("__kk_float_to_double_bits")
        case ("toDouble", sema.types.doubleType, sema.types.doubleType): nil
        case ("toByte", sema.types.intType, sema.types.byteType): interner.intern("kk_int_to_byte")
        case ("toByte", sema.types.longType, sema.types.byteType): interner.intern("kk_long_to_byte")
        case ("toByte", sema.types.uintType, sema.types.byteType): interner.intern("kk_uint_to_byte")
        case ("toByte", sema.types.ulongType, sema.types.byteType): interner.intern("kk_ulong_to_byte")
        case ("toByte", sema.types.ubyteType, sema.types.byteType): interner.intern("kk_ubyte_to_byte")
        case ("toByte", sema.types.ushortType, sema.types.byteType): interner.intern("kk_ushort_to_byte")
        case ("toByte", sema.types.byteType, sema.types.byteType): nil
        case ("toByte", sema.types.shortType, sema.types.byteType): interner.intern("kk_int_to_byte")
        case ("toShort", sema.types.intType, sema.types.shortType): interner.intern("kk_int_to_short")
        case ("toShort", sema.types.longType, sema.types.shortType): interner.intern("kk_long_to_short")
        case ("toShort", sema.types.uintType, sema.types.shortType): interner.intern("kk_uint_to_short")
        case ("toShort", sema.types.ulongType, sema.types.shortType): interner.intern("kk_ulong_to_short")
        case ("toShort", sema.types.ubyteType, sema.types.shortType): interner.intern("kk_ubyte_to_short")
        case ("toShort", sema.types.ushortType, sema.types.shortType): interner.intern("kk_ushort_to_short")
        case ("toShort", sema.types.byteType, sema.types.shortType): nil
        case ("toShort", sema.types.shortType, sema.types.shortType): nil
        case ("toUByte", sema.types.intType, sema.types.ubyteType): interner.intern("kk_int_to_ubyte")
        case ("toUByte", sema.types.longType, sema.types.ubyteType): interner.intern("kk_long_to_ubyte")
        case ("toUByte", sema.types.uintType, sema.types.ubyteType): interner.intern("kk_uint_to_ubyte")
        case ("toUByte", sema.types.ulongType, sema.types.ubyteType): interner.intern("kk_ulong_to_ubyte")
        case ("toUByte", sema.types.ubyteType, sema.types.ubyteType): nil
        case ("toUShort", sema.types.intType, sema.types.ushortType): interner.intern("kk_int_to_ushort")
        case ("toUShort", sema.types.longType, sema.types.ushortType): interner.intern("kk_long_to_ushort")
        case ("toUShort", sema.types.uintType, sema.types.ushortType): interner.intern("kk_uint_to_ushort")
        case ("toUShort", sema.types.ulongType, sema.types.ushortType): interner.intern("kk_ulong_to_ushort")
        case ("toUShort", sema.types.ushortType, sema.types.ushortType): nil
        case ("toChar", sema.types.uintType, sema.types.charType): interner.intern("kk_uint_to_char")
        case ("toChar", sema.types.ulongType, sema.types.charType): interner.intern("kk_ulong_to_char")
        case ("toChar", sema.types.ubyteType, sema.types.charType): interner.intern("kk_ubyte_to_char")
        case ("toChar", sema.types.ushortType, sema.types.charType): interner.intern("kk_ushort_to_char")
        case ("toChar", sema.types.charType, sema.types.charType): nil
        default: nil
        }

        let isCharNarrowingConversion = receiverType == sema.types.charType
            && (calleeStr == "toByte" || calleeStr == "toShort")
        if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toByte", "toShort", "toChar"].contains(calleeStr),
           runtimeCallee == nil,
           !isCharNarrowingConversion
        {
            return loweredArgumentID
        }
        guard let runtimeCallee else {
            return nil
        }

        let result = arena.appendTemporary(type: boundType)
        emitNonThrowingCall(
            callee: runtimeCallee,
            arg: loweredArgumentID,
            result: result,
            into: &instructions
        )
        return result
    }

    // MARK: - REFL-005: typeOf<T>() Lowering

}
