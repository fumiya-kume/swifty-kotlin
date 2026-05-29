import Foundation

final class CallLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    /// Maps a numeric receiver type (nullable or non-nullable) to its runtime
    /// symbol prefix (e.g. "kk_int", "kk_long", "kk_uint", "kk_ulong"),
    /// or nil if the receiver is not one of the coercion-eligible numeric
    /// types. Nullable receivers are normalized to non-nullable for dispatch.
    /// Shared by both normal and safe-call member lowering paths.
    func numericCoercionRuntimePrefix(
        receiverType: TypeID,
        sema: SemaModule
    ) -> String? {
        let nonNull = sema.types.makeNonNullable(receiverType)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let doubleType = sema.types.make(.primitive(.double, .nonNull))
        let floatType = sema.types.make(.primitive(.float, .nonNull))
        let ubyteType = sema.types.ubyteType
        let ushortType = sema.types.ushortType
        let uintType = sema.types.uintType
        let ulongType = sema.types.ulongType
        if nonNull == intType { return "kk_int" }
        if nonNull == longType { return "kk_long" }
        if nonNull == doubleType { return "kk_double" }
        if nonNull == floatType { return "kk_float" }
        if nonNull == ubyteType { return "kk_ubyte" }
        if nonNull == ushortType { return "kk_ushort" }
        if nonNull == uintType { return "kk_uint" }
        if nonNull == ulongType { return "kk_ulong" }
        return nil
    }

    /// Shared helper for coerceIn(range) lowering (STDLIB-525, STDLIB-CONV-006).
    /// Decomposes a range argument into first/last bounds and emits a call to
    /// kk_{int,long,uint,ulong}_coerceIn. Used by both normal and safe-call member lowering
    /// paths to avoid duplication for the numeric types that expose range coercion.
    func emitCoerceInRange(
        prefix: String,
        receiverType: TypeID,
        loweredReceiverID: KIRExprID,
        loweredRangeArgID: KIRExprID,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        // Use non-nullable receiver type for temporaries so Long receivers get
        // Long-typed bounds instead of always Int.
        let boundType = sema.types.makeNonNullable(receiverType)
        let firstExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        let lastExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_first"),
            arguments: [loweredRangeArgID],
            result: firstExpr,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_range_last"),
            arguments: [loweredRangeArgID],
            result: lastExpr,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(prefix + "_coerceIn"),
            arguments: [loweredReceiverID, firstExpr, lastExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }

    func dataClassPropertyNames(
        ownerSymbol: SymbolID,
        sema: SemaModule
    ) -> [InternedString] {
        guard let owner = sema.symbols.symbol(ownerSymbol),
              owner.flags.contains(.dataType)
        else {
            return []
        }

        let primaryParameterNames: [InternedString] = sema.symbols.children(ofFQName: owner.fqName)
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .constructor }
            .min { lhs, rhs in
                let lhsOffset = lhs.declSite?.start.offset ?? Int.max
                let rhsOffset = rhs.declSite?.start.offset ?? Int.max
                if lhsOffset != rhsOffset {
                    return lhsOffset < rhsOffset
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }
            .flatMap { constructor in
                sema.symbols.functionSignature(for: constructor.id)?.valueParameterSymbols.compactMap { paramID in
                    sema.symbols.symbol(paramID)?.name
                }
            } ?? []

        guard !primaryParameterNames.isEmpty else {
            return []
        }

        let propertiesByName = Dictionary(
            sema.symbols.children(ofFQName: owner.fqName)
                .compactMap { sema.symbols.symbol($0) }
                .filter { $0.kind == .property && !$0.flags.contains(.synthetic) }
                .map { ($0.name, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        return primaryParameterNames.compactMap { propertiesByName[$0] }
    }

    func emitDataClassFieldRegistration(
        objectSymbol: SymbolID,
        classID: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let propertyNames = dataClassPropertyNames(ownerSymbol: objectSymbol, sema: sema)
        guard !propertyNames.isEmpty else {
            return
        }

        let intType = sema.types.intType
        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))

        for (index, propertyName) in propertyNames.enumerated() {
            let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
            instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))

            let nameExpr = arena.appendExpr(.stringLiteral(propertyName), type: intType)
            instructions.append(.constValue(result: nameExpr, value: .stringLiteral(propertyName)))

            let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_json_register_data_class_field_name"),
                arguments: [classIDExpr, indexExpr, nameExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
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
        // argument is already marked as a SAM conversion.  Lower the lambda
        // directly; the SAM wrapper is produced by LambdaLowerer.
        if args.count == 1,
           sema.bindings.isSamConversion(args[0].expr)
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

        if let loweredMeasureTime = lowerMeasureTimeMillisCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureTime
        }

        if let loweredMeasureMicros = lowerMeasureTimeMicrosCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureMicros
        }

        if let loweredMeasureNano = lowerMeasureNanoTimeCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureNano
        }

        if let loweredMeasureTimeDuration = lowerMeasureTimeCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureTimeDuration
        }

        if let loweredMeasureTimedValue = lowerMeasureTimedValueCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredMeasureTimedValue
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
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return loweredEnumValues
        }

        if let loweredEnumEntries = lowerEnumEntriesCallExpr(
            exprID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
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
           calleeName == interner.intern("contextOf")
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            if let contextValue = driver.ctx.contextReceiverValue(matching: boundType, sema: sema) {
                return contextValue
            }
            let fallback = arena.appendExpr(.unit, type: boundType)
            instructions.append(.constValue(result: fallback, value: .unit))
            return fallback
        }

        // --- Scope function: with(receiver, block) (STDLIB-004) ---
        if let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
           scopeKind == .scopeWith,
           args.count == 2
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let loweredReceiverID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            // Set up implicit receiver for the lambda body.
            let receiverSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
            let receiverType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let receiverSymExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            instructions.append(.copy(from: loweredReceiverID, to: receiverSymExpr))

            let savedReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
            let savedReceiverSymbol = driver.ctx.activeImplicitReceiverSymbol()
            driver.ctx.setLocalValue(receiverSymExpr, for: receiverSymbol)
            driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverSymExpr)

            let loweredLambdaID = driver.lowerExpr(
                args[1].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)

            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
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
                // Non-lambda-literal argument; restore state and
                // fall through to normal call lowering.
                driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)
            }
            return result
        }

        // --- Context helper: context(with, block) (STDLIB-KOTLIN-ROOT-CTX-001) ---
        if let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
           scopeKind == .scopeContext,
           args.count >= 2,
           args.count <= 7
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
            let loweredLambdaID = driver.lowerExpr(
                args[args.count - 1].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
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
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("invoke"),
                    arguments: [loweredLambdaID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return result
        }

        // --- Scope function: top-level run(block) (STDLIB-401) ---
        if let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
           scopeKind == .scopeTopLevelRun,
           args.count == 1
        {
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType
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
                // Callable reference or other non-lambda callable: invoke it
                // so that `run(::foo)` calls foo() rather than returning the
                // reference itself.  Use the already-lowered ID to avoid
                // double-lowering the lambda argument expression.
                let invokeName = interner.intern("invoke")
                instructions.append(.call(
                    symbol: nil,
                    callee: invokeName,
                    arguments: [loweredLambdaID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
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
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
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
        // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
        if sourceCalleeName == interner.intern("generateSequence"),
           loweredArgIDs.count == 1,
           let nextFunctionType = sema.bindings.exprTypes[args[0].expr],
           case .functionType = sema.types.kind(of: sema.types.makeNonNullable(nextFunctionType))
        {
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: chosen,
                callee: interner.intern("kk_sequence_generate_noarg"),
                arguments: [loweredArgIDs[0]],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if sourceCalleeName == interner.intern("generateSequence"),
           loweredArgIDs.count == 2,
           let seedFunctionType = sema.bindings.exprTypes[args[0].expr],
           case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(seedFunctionType)),
           functionType.params.isEmpty,
           let seedCallableInfo = driver.ctx.callableValueInfo(for: loweredArgIDs[0])
        {
            let seedResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.makeNonNullable(functionType.returnType)
            )
            instructions.append(.call(
                symbol: seedCallableInfo.symbol,
                callee: seedCallableInfo.callee,
                arguments: seedCallableInfo.captureArguments,
                result: seedResult,
                canThrow: false,
                thrownResult: nil
            ))
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: chosen,
                callee: interner.intern("kk_sequence_generate"),
                arguments: [seedResult, loweredArgIDs[1]],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if sema.bindings.builderDSLKind(for: exprID) == .buildString {
            let builderRuntimeCallee: String? = switch (interner.resolve(sourceCalleeName), loweredArgIDs.count) {
            case ("append", 1):
                "kk_string_builder_append"
            case ("appendLine", 0):
                "kk_string_builder_append_line_noarg"
            case ("appendLine", 1):
                "kk_string_builder_append_line"
            case ("appendRange", 3):
                "kk_string_builder_append_range"
            default:
                nil
            }
            if let builderRuntimeCallee {
                let result = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boundType ?? sema.types.anyType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(builderRuntimeCallee),
                    arguments: loweredArgIDs,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
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
        if chosen == nil,
           loweredCallable == nil,
           let implicitStringBuilderCall = implicitReceiverStringBuilderRuntimeCallee(
               sourceCalleeName: sourceCalleeName,
               loweredArguments: loweredArgIDs,
               sema: sema,
               arena: arena,
               interner: interner
           )
        {
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: boundType ?? sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: implicitStringBuilderCall.callee,
                arguments: [implicitStringBuilderCall.receiver] + loweredArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        let callNormalized: NormalizedCallResult = if callBinding != nil {
            if let chosen,
               (sema.symbols.externalLinkName(for: chosen) == "kk_comparator_from_multi_selectors_vararg" ||
                sema.symbols.externalLinkName(for: chosen) == "kk_compareValuesByVararg")
            {
                NormalizedCallResult(arguments: loweredArgIDs, defaultMask: 0)
            } else {
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
            }
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
        if callableInvokeCallee != nil {
            finalArgIDs.insert(loweredCalleeExprID, at: 0)
        }
        if callableInvokeCallee == nil, let loweredCallable {
            finalArgIDs.insert(contentsOf: loweredCallable.captureArguments, at: 0)
        } else if let chosen,
                  sema.symbols.symbol(chosen)?.kind == .constructor,
                  sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true
        {
            // Constructor calls need an allocated object as the implicit receiver (p0).
            // Allocate via kk_array_new(slotCount) and prepend it to the argument list.
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
            let allocatedObj = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: allocType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: allocatedObj,
                canThrow: false,
                thrownResult: nil
            ))
            if let ownerNominalSymbol {
                let childTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: ownerNominalSymbol,
                    sema: sema,
                    interner: interner
                )
                let childExpr = arena.appendExpr(.intLiteral(childTypeID), type: intType)
                instructions.append(.constValue(result: childExpr, value: .intLiteral(childTypeID)))
                for superSymbol in sema.symbols.directSupertypes(for: ownerNominalSymbol) {
                    let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                        symbol: superSymbol,
                        sema: sema,
                        interner: interner
                    )
                    let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
                    instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
                    let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                    let superKind = sema.symbols.symbol(superSymbol)?.kind
                    let registerCallee: InternedString = if superKind == .interface {
                        interner.intern("kk_type_register_iface")
                    } else {
                        interner.intern("kk_type_register_super")
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: registerCallee,
                        arguments: [childExpr, parentExpr],
                        result: registerResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                if let objectLayout = sema.symbols.nominalLayout(for: ownerNominalSymbol) {
                    for interfaceSymbol in sema.symbols.directSupertypes(for: ownerNominalSymbol) {
                        guard sema.symbols.symbol(interfaceSymbol)?.kind == .interface,
                              let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol)
                        else {
                            continue
                        }
                        let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
                        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                            symbol: interfaceSymbol,
                            sema: sema,
                            interner: interner
                        )
                        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
                        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
                        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
                        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
                        let registerIfaceResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_object_register_itable_iface"),
                            arguments: [allocatedObj, interfaceTypeExpr, ifaceSlotExpr],
                            result: registerIfaceResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        for (methodSymbol, methodSlotInt) in interfaceLayout.vtableSlots {
                            let methodSlot = Int64(methodSlotInt)
                            let implementationSymbol: SymbolID = {
                                guard let methodSym = sema.symbols.symbol(methodSymbol),
                                      let ownerSym = sema.symbols.symbol(ownerNominalSymbol)
                                else {
                                    return methodSymbol
                                }
                                let overrideFQName = ownerSym.fqName + [methodSym.name]
                                for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
                                    guard let candidateSym = sema.symbols.symbol(candidate),
                                          candidateSym.kind == .function,
                                          sema.symbols.parentSymbol(for: candidate) == ownerNominalSymbol
                                    else {
                                        continue
                                    }
                                    return candidate
                                }
                                return methodSymbol
                            }()
                            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
                            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
                            let methodFnExpr = arena.appendExpr(.symbolRef(implementationSymbol), type: intType)
                            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementationSymbol)))
                            let registerMethodResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                            instructions.append(.call(
                                symbol: nil,
                                callee: interner.intern("kk_object_register_itable_method"),
                                arguments: [allocatedObj, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                                result: registerMethodResult,
                                canThrow: false,
                                thrownResult: nil
                            ))
                        }
                    }
                }
                // REFL-005: Register KClass metadata for this nominal type.
                emitKClassMetadataRegistration(
                    objectSymbol: ownerNominalSymbol,
                    typeID: childTypeID,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            finalArgIDs.insert(allocatedObj, at: 0)
        } else if let chosen,
                  let signature = sema.symbols.functionSignature(for: chosen),
                  signature.receiverType != nil,
                  let implicitReceiver = driver.ctx.activeImplicitReceiverExprID()
        {
            finalArgIDs.insert(implicitReceiver, at: 0)
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
        // Only expand captures for the first argument (the launcher entry
        // function reference); subsequent arguments are value args for the
        // referenced suspend function and should not be expanded.
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
               || sourceCalleeName == knownNames.produce,
               let firstArg = finalArgIDs.first,
               let callableInfo = driver.ctx.callableValueInfo(for: firstArg),
               !callableInfo.captureArguments.isEmpty
            {
                finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 1)
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
           sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true
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
            if loweredCalleeName == interner.intern("kk_channel_create"), finalArgIDs.isEmpty {
                let capacityExpr = arena.appendExpr(
                    .intLiteral(0),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: capacityExpr, value: .intLiteral(0)))
                finalArgIDs.append(capacityExpr)
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
            }
            let callCanThrow = needsThrownChannel(calleeName: loweredCalleeName, interner: interner)
            let thrownResult = callCanThrow
                ? arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.nullableAnyType
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
            instructions.append(.call(
                symbol: callSymbol,
                callee: loweredCalleeName,
                arguments: finalArgIDs,
                result: result,
                canThrow: callCanThrow,
                thrownResult: thrownResult
            ))
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

    private func runtimeCallableInvokeCallee(
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

        if functionType.isSuspend {
            switch functionType.params.count {
            case 0:
                return interner.intern("kk_suspend_function_invoke_0")
            case 1:
                return interner.intern("kk_suspend_function_invoke")
            default:
                return nil
            }
        }

        switch functionType.params.count {
        case 0:
            return interner.intern("kk_function_invoke_0")
        case 1:
            return interner.intern("kk_function_invoke")
        case 2:
            return interner.intern("kk_function_invoke_2")
        case 3:
            return interner.intern("kk_function_invoke_3")
        default:
            return nil
        }
    }

    private func implicitReceiverStringBuilderRuntimeCallee(
        sourceCalleeName: InternedString,
        loweredArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> (receiver: KIRExprID, callee: InternedString)? {
        guard let implicitReceiver = driver.ctx.activeImplicitReceiverExprID(),
              let receiverType = arena.exprType(implicitReceiver),
              case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        guard knownNames.isStringBuilderSymbol(symbol) else {
            return nil
        }

        // For append(value), dispatch to typed overloads when the argument is a primitive.
        if interner.resolve(sourceCalleeName) == "append", loweredArguments.count == 1 {
            let argCallee: String
            if let argType = arena.exprType(loweredArguments[0]) {
                let nonNull = sema.types.makeNonNullable(argType)
                if nonNull == sema.types.booleanType {
                    argCallee = "kk_string_builder_append_bool"
                } else if nonNull == sema.types.charType {
                    argCallee = "kk_string_builder_append_char"
                } else if nonNull == sema.types.make(.primitive(.float, .nonNull)) {
                    argCallee = "kk_string_builder_append_float"
                } else if nonNull == sema.types.make(.primitive(.double, .nonNull)) {
                    argCallee = "kk_string_builder_append_double"
                } else {
                    argCallee = "kk_string_builder_append_obj"
                }
            } else {
                argCallee = "kk_string_builder_append_obj"
            }
            return (implicitReceiver, interner.intern(argCallee))
        }

        let callee: String? = switch (interner.resolve(sourceCalleeName), loweredArguments.count) {
        case ("appendLine", 0):
            "kk_string_builder_append_line_noarg_obj"
        case ("appendLine", 1):
            "kk_string_builder_append_line_obj"
        case ("appendRange", 3):
            "kk_string_builder_appendRange_obj"
        case ("toString", 0):
            "kk_string_builder_toString"
        case ("clear", 0):
            "kk_string_builder_clear"
        case ("reverse", 0):
            "kk_string_builder_reverse"
        case ("length", 0):
            "kk_string_builder_length_prop"
        case ("deleteCharAt", 1):
            "kk_string_builder_deleteCharAt"
        case ("deleteAt", 1):
            "kk_string_builder_deleteAt"
        case ("insert", 2):
            "kk_string_builder_insert_obj"
        case ("delete", 2):
            "kk_string_builder_delete_obj"
        case ("deleteRange", 2):
            "kk_string_builder_deleteRange"
        case ("insertRange", 4):
            "kk_string_builder_insertRange_obj"
        case ("setRange", 3):
            "kk_string_builder_setRange"
        case ("set", 2):
            // STDLIB-TEXT-FN-064: operator fun set(index, value) desugars to setCharAt
            "kk_string_builder_setCharAt"
        default:
            nil
        }

        guard let callee else {
            return nil
        }
        return (implicitReceiver, interner.intern(callee))
    }

    /// Returns true if the callee is a runtime function that requires a thrown
    /// channel (outThrown) parameter in its ABI. This ensures the codegen
    /// appends the extra `intptr_t * _Nullable` slot.
    private func needsThrownChannel(calleeName: InternedString, interner: StringInterner) -> Bool {
        let name = interner.resolve(calleeName)
        return name == "kk_runCatching" || name == "kk_synchronized"
    }

    private func shouldRethrowThrownChannelResult(calleeName: InternedString, interner: StringInterner) -> Bool {
        interner.resolve(calleeName) == "kk_synchronized"
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
        let runtimeCallee: InternedString? = if case let .classType(classType) = sema.types.kind(of: nonNullArgumentType),
                                                let symbol = sema.symbols.symbol(classType.classSymbol)
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
            case knownNames.string:
                interner.intern("kk_string_toList")
            default:
                interner.intern("kk_sequence_to_list")
            }
        } else {
            interner.intern("kk_sequence_to_list")
        }
        guard let runtimeCallee else {
            return loweredArgIDs[0]
        }

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
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
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType) else {
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
        case ("toInt", sema.types.doubleType, sema.types.intType): interner.intern("kk_double_to_int")
        case ("toInt", sema.types.floatType, sema.types.intType): interner.intern("kk_float_to_int")
        case ("toInt", sema.types.charType, sema.types.intType): interner.intern("kk_char_to_int")
        case ("toInt", sema.types.intType, sema.types.intType), ("toInt", sema.types.longType, sema.types.intType): nil
        case ("toLong", sema.types.intType, sema.types.longType): interner.intern("kk_int_to_long")
        case ("toLong", sema.types.uintType, sema.types.longType): interner.intern("kk_uint_to_long")
        case ("toLong", sema.types.ubyteType, sema.types.longType): interner.intern("kk_ubyte_to_long")
        case ("toLong", sema.types.ushortType, sema.types.longType): interner.intern("kk_ushort_to_long")
        case ("toLong", sema.types.doubleType, sema.types.longType): interner.intern("kk_double_to_long")
        case ("toLong", sema.types.floatType, sema.types.longType): interner.intern("kk_float_to_long")
        case ("toLong", sema.types.charType, sema.types.longType): interner.intern("kk_char_to_long")
        case ("toLong", sema.types.longType, sema.types.longType), ("toLong", sema.types.ulongType, sema.types.longType): nil
        case ("toUInt", sema.types.intType, sema.types.uintType): interner.intern("kk_int_to_uint")
        case ("toUInt", sema.types.longType, sema.types.uintType): interner.intern("kk_long_to_uint")
        case ("toUInt", sema.types.ubyteType, sema.types.uintType): interner.intern("kk_ubyte_to_uint")
        case ("toUInt", sema.types.ushortType, sema.types.uintType): interner.intern("kk_ushort_to_uint")
        case ("toUInt", sema.types.charType, sema.types.uintType): interner.intern("kk_char_to_uint")
        case ("toUInt", sema.types.uintType, sema.types.uintType), ("toUInt", sema.types.ulongType, sema.types.uintType): nil
        case ("toULong", sema.types.intType, sema.types.ulongType): interner.intern("kk_int_to_ulong")
        case ("toULong", sema.types.longType, sema.types.ulongType): interner.intern("kk_long_to_ulong")
        case ("toULong", sema.types.ubyteType, sema.types.ulongType): interner.intern("kk_ubyte_to_ulong")
        case ("toULong", sema.types.ushortType, sema.types.ulongType): interner.intern("kk_ushort_to_ulong")
        case ("toULong", sema.types.charType, sema.types.ulongType): interner.intern("kk_char_to_ulong")
        case ("toULong", sema.types.uintType, sema.types.ulongType): interner.intern("kk_uint_to_ulong")
        case ("toULong", sema.types.ulongType, sema.types.ulongType): nil
        case ("toFloat", sema.types.intType, sema.types.floatType): interner.intern("kk_int_to_float")
        case ("toFloat", sema.types.longType, sema.types.floatType): interner.intern("kk_long_to_float")
        case ("toFloat", sema.types.doubleType, sema.types.floatType): interner.intern("kk_double_to_float")
        case ("toFloat", sema.types.floatType, sema.types.floatType): nil
        case ("toDouble", sema.types.intType, sema.types.doubleType): interner.intern("kk_int_to_double_bits")
        case ("toDouble", sema.types.longType, sema.types.doubleType): interner.intern("kk_long_to_double")
        case ("toDouble", sema.types.floatType, sema.types.doubleType): interner.intern("kk_float_to_double_bits")
        case ("toDouble", sema.types.doubleType, sema.types.doubleType): nil
        case ("toByte", sema.types.intType, sema.types.intType): interner.intern("kk_int_to_byte")
        case ("toByte", sema.types.longType, sema.types.intType): interner.intern("kk_long_to_byte")
        case ("toShort", sema.types.intType, sema.types.intType): interner.intern("kk_int_to_short")
        case ("toShort", sema.types.longType, sema.types.intType): interner.intern("kk_long_to_short")
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
        case ("toChar", sema.types.intType, sema.types.charType): interner.intern("kk_int_to_char")
        case ("toChar", sema.types.longType, sema.types.charType): interner.intern("kk_long_to_char")
        case ("toChar", sema.types.uintType, sema.types.charType): interner.intern("kk_uint_to_char")
        case ("toChar", sema.types.ulongType, sema.types.charType): interner.intern("kk_ulong_to_char")
        case ("toChar", sema.types.ubyteType, sema.types.charType): interner.intern("kk_ubyte_to_char")
        case ("toChar", sema.types.ushortType, sema.types.charType): interner.intern("kk_ushort_to_char")
        case ("toChar", sema.types.charType, sema.types.charType): nil
        default: nil
        }

        if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toByte", "toShort", "toChar"].contains(calleeStr),
           runtimeCallee == nil
        {
            return loweredArgumentID
        }
        guard let runtimeCallee else {
            return nil
        }

        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType)
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: [loweredArgumentID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    // MARK: - REFL-005: typeOf<T>() Lowering

}
