import Foundation

// swiftlint:disable type_body_length
final class CallTypeChecker {
    unowned let driver: TypeCheckDriver
    
    // MARK: - Processors
    
    private let builderDSLProcessor: BuilderDSLProcessor
    private let scopeFunctionProcessor: ScopeFunctionProcessor
    private let flowBuilderProcessor: FlowBuilderProcessor
    private let stdlibSpecialCallProcessor: StdlibSpecialCallProcessor
    private let comparisonProcessor: ComparisonProcessor
    private let memberCallProcessor: MemberCallProcessor
    private let samConversionProcessor: SAMConversionProcessor
    private let contractProcessor: ContractProcessor
    private let enumProcessor: EnumProcessor
    
    init(driver: TypeCheckDriver) {
        self.driver = driver
        
        // Processorsを初期化
        self.builderDSLProcessor = BuilderDSLProcessor(driver: driver)
        self.scopeFunctionProcessor = ScopeFunctionProcessor(driver: driver)
        self.flowBuilderProcessor = FlowBuilderProcessor(driver: driver)
        self.stdlibSpecialCallProcessor = StdlibSpecialCallProcessor(driver: driver)
        self.comparisonProcessor = ComparisonProcessor(driver: driver)
        self.memberCallProcessor = MemberCallProcessor(driver: driver)
        self.samConversionProcessor = SAMConversionProcessor(driver: driver)
        self.contractProcessor = ContractProcessor(driver: driver)
        self.enumProcessor = EnumProcessor(driver: driver)
    }

    func inferCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        let ast = ctx.ast
        let calleeExpr = ast.arena.expr(calleeID)
        let calleeName: InternedString? = if case let .nameRef(name, _) = calleeExpr {
            name
        } else {
            nil
        }
<<<<<<< /Users/kuu/kotlin-compiler/Sources/CompilerCore/Sema/TypeCheck/CallTypeChecker.swift
        // --- Builder DSL functions (STDLIB-002) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        if let calleeName {
            if let builderKind = builderDSLKind(for: calleeName, interner: interner),
               shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
            {
                let lambdaArgumentIndex: Int? = switch builderKind {
                case .buildString, .buildSet, .buildMap:
                    args.count == 1 ? 0 : nil
                case .buildList:
                    switch args.count {
                    case 1: 0
                    case 2: 1
                    default: nil
                    }
                }
                guard let lambdaArgumentIndex else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if builderKind == .buildList, args.count == 2 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                let argumentExprID = args[lambdaArgumentIndex].expr
                guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }

                let receiverType = builderDSLReceiverType(
                    kind: builderKind,
                    lambdaExprID: argumentExprID,
                    expectedType: expectedType,
                    ctx: ctx,
                    locals: locals,
                    sema: sema,
                    interner: interner
                )
                let returnType: TypeID = switch builderKind {
                case .buildString:
                    sema.types.stringType
                case .buildList:
                    builderDSLBuildListReturnType(receiverType: receiverType, sema: sema, interner: interner)
                case .buildSet:
                    builderDSLBuildSetReturnType(receiverType: receiverType, sema: sema, interner: interner)
                case .buildMap:
                    builderDSLBuildMapReturnType(receiverType: receiverType, sema: sema, interner: interner)
                }
                // Infer the lambda argument with the builder receiver as implicit `this`.
                var builderCtx = ctx.with(implicitReceiverType: receiverType)
                builderCtx.isBuilderLambdaScope = true
                builderCtx.builderKind = builderKind
                _ = driver.inferExpr(argumentExprID, ctx: builderCtx, locals: &locals)
                sema.bindings.markBuilderDSLExpr(id, kind: builderKind)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
        }

        // --- sequence { ... } builder (STDLIB-330) ---
        // Intercept before eager argument inference so the lambda is inferred
        // with a SequenceScope<T> implicit receiver and T can be recovered from
        // expected type or nested yield()/yieldAll() calls.
        if let calleeName,
           interner.resolve(calleeName) == "sequence",
           args.count == 1,
           shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let returnType = sequenceBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = sequenceBuilderReceiverType(
                sequenceType: returnType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sequenceBuilderLambdaType(
                receiverType: receiverType,
                sema: sema
            )
            _ = driver.inferExpr(
                argumentExprID,
                ctx: ctx.with(implicitReceiverType: receiverType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let refinedReturnType = sequenceBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("sequence"),
            ]) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }

        // --- iterator { ... } builder (STDLIB-331/564) ---
        if let calleeName,
           interner.resolve(calleeName) == "iterator",
           args.count == 1,
           locals[calleeName] == nil
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let returnType = iteratorBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = sequenceBuilderReceiverType(
                sequenceType: returnType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sequenceBuilderLambdaType(
                receiverType: receiverType,
                sema: sema
            )
            _ = driver.inferExpr(
                argumentExprID,
                ctx: ctx.with(implicitReceiverType: receiverType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let refinedReturnType = iteratorBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("iterator"),
            ]) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }

        // --- Scope function: with(receiver, block) (STDLIB-004, STDLIB-061) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        // Intercept when no local or user-defined (non-synthetic) `with` shadows the stdlib helper.
        if let calleeName, args.count == 2,
           calleeName == knownNames.with,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               guard let sym = ctx.cachedSymbol(candidate) else { return false }
               return !sym.flags.contains(.synthetic)
           })
        {
            // First arg is the receiver object
            let withReceiverType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            // Second arg is the lambda with receiver
            var receiverCtx = ctx.with(implicitReceiverType: withReceiverType)
            let nonNullWithReceiverType = sema.types.makeNonNullable(withReceiverType)
            if case let .classType(classType) = sema.types.kind(of: nonNullWithReceiverType),
               let receiverSymbol = sema.symbols.symbol(classType.classSymbol),
               knownNames.isStringBuilderSymbol(receiverSymbol)
            {
                receiverCtx.isBuilderLambdaScope = true
                receiverCtx.builderKind = .buildString
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: withReceiverType,
                params: [],
                returnType: expectedType ?? sema.types.anyType
            )))
            let lambdaType = driver.inferExpr(
                args[1].expr, ctx: receiverCtx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[1].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeWith)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- Scope function: top-level run(block) (STDLIB-401) ---
        // `run { expr }` simply executes the block lambda and returns the result.
        // Intercept when no local or user-defined (non-synthetic) `run` shadows the stdlib helper.
        // The single argument must be a lambda literal or callable reference;
        // otherwise (e.g. `run(123)`) fall through to normal call resolution.
        if isTopLevelRunCandidate(
            calleeName: calleeName,
            args: args,
            knownNames: knownNames,
            ast: ast,
            ctx: ctx,
            locals: locals
        ) {
            let lambdaExpectedType: TypeID? = if let expectedType {
                sema.types.make(.functionType(FunctionType(
                    params: [],
                    returnType: expectedType
                )))
            } else {
                nil
            }
            let lambdaType = driver.inferExpr(
                args[0].expr, ctx: ctx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeTopLevelRun)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- runCatching(block) (STDLIB-590) ---
        // `runCatching { expr }` executes the block lambda and wraps the result
        // in a Result<T>.  Similar to top-level `run`, but returns Result<T>.
        if let calleeName, args.count == 1,
           calleeName == knownNames.runCatching,
           locals[calleeName] == nil,
           isLambdaOrCallableRefArg(args[0].expr, ast: ast),
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "runCatching"], ctx: ctx)
        {
            let lambdaType = driver.inferExpr(
                args[0].expr, ctx: ctx, locals: &locals, expectedType: nil
            )
            let innerType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            // Build Result<T> type
            let resultType: TypeID = if let resultClassSymbol = sema.symbols.lookup(fqName: knownNames.kotlinResultFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: resultClassSymbol,
                    args: [.out(innerType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            // Mark the lambda for closure ABI expansion in KIR
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            // Bind the call to the synthetic runCatching function symbol
            if let runCatchingSymbol = sema.symbols.lookup(fqName: knownNames.kotlinRunCatchingFQName) {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: runCatchingSymbol,
                    substitutedTypeArguments: [innerType],
                    parameterMapping: [0: 0]
                ))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- Flow builder function (CORO-003) ---
        // `flow { emit(...) }` is treated as a builtin cold stream factory.
        // We infer the lambda with a flow-builder scope so unqualified `emit`
        // resolves in Sema fallback.
        if let calleeName,
           calleeName == knownNames.flow,
           args.count == 1,
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let flowLambdaExprID = args[0].expr
            guard isValidBuilderLambdaArgument(flowLambdaExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var flowBuilderCtx = ctx.with(implicitReceiverType: sema.types.anyType)
            flowBuilderCtx.isFlowBuilderLambdaScope = true
            let flowLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: true,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                flowLambdaExprID,
                ctx: flowBuilderCtx,
                locals: &locals,
                expectedType: flowLambdaExpectedType
            )
            sema.bindings.markFlowExpr(id)
            if let explicitElementType = explicitTypeArgs.first {
                sema.bindings.bindFlowElementType(explicitElementType, forExpr: id)
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    sema.bindings.bindFlowElementType(type, forExpr: id)
                case .star:
                    break
                }
            }
            let flowElementType = sema.bindings.flowElementType(forExpr: id) ?? sema.types.anyType
            let flowExprType = driver.helpers.makeFlowType(
                elementType: flowElementType, sema: sema, interner: interner
            ) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: flowExprType)
            return flowExprType
        }

        // --- Flow builder lambda calls (CORO-003) ---
        // Inside `flow { ... }`, unqualified `emit` resolves as a builtin
        // effect call and returns Unit.
        if ctx.isFlowBuilderLambdaScope,
           let calleeName,
           calleeName == knownNames.emit,
           args.count == 1,
           ctx.cachedScopeLookup(calleeName).isEmpty,
           locals[calleeName] == nil
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        if let calleeName,
           calleeName == knownNames.regexCtor,
           args.count == 1
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
            let regexType: TypeID = if let regexSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("text"),
                interner.intern("Regex"),
            ]) {
                sema.types.make(.classType(ClassType(
                    classSymbol: regexSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            sema.bindings.bindExprType(id, type: regexType)
            return regexType
        }

        if let calleeName,
           interner.resolve(calleeName) == "generateSequence",
           args.count == 2
        {
            let seedType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
            let nextExpectedType = sema.types.make(.functionType(FunctionType(
                params: [seedType],
                returnType: sema.types.makeNullable(seedType),
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: nextExpectedType)
            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            sema.bindings.markCollectionExpr(id)
            let sequenceType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: seedType
            )
            sema.bindings.bindExprType(id, type: sequenceType)
            return sequenceType
        }

        // --- Stdlib repeat(times) { ... } (STDLIB-008) ---
        // Infer the lambda argument with the expected `(Int) -> Unit` type so
        // implicit `it` resolves to the loop index.
        if let calleeName,
           interner.resolve(calleeName) == "repeat",
           args.count == 2,
           shouldUseRepeatSpecialHandling(calleeName: calleeName, locals: locals)
        {
            let intType = sema.types.intType
            let unitType = sema.types.unitType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let actionExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: unitType
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: actionExpectedType
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .repeatLoop)
            sema.bindings.bindExprType(id, type: unitType)
            return unitType
        }

        // --- Stdlib measureTimeMillis { ... } (STDLIB-131) ---
        if let calleeName,
           interner.resolve(calleeName) == "measureTimeMillis",
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let longType = sema.types.longType
            // Intentionally passing expectedType:nil — the block's return type is
            // not constrained here because KIR lowering discards the lambda result.
            // The synthetic stub already declares the parameter as () -> Unit,
            // which is enforced during overload resolution.
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTimeMillis)
            sema.bindings.bindExprType(id, type: longType)
            return longType
        }

        // --- Stdlib measureNanoTime { ... } (STDLIB-550) ---
        if let calleeName,
           interner.resolve(calleeName) == "measureNanoTime",
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let longType = sema.types.longType
            // Intentionally passing expectedType:nil — same rationale as
            // measureTimeMillis above: KIR lowering discards the lambda result
            // and the synthetic stub enforces the () -> Unit contract.
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureNanoTime)
            sema.bindings.bindExprType(id, type: longType)
            return longType
        }

        // --- Stdlib kotlin.time.measureTime { ... } (STDLIB-585) ---
        // Verify both the name and that the resolved symbol is the synthetic
        // kotlin.time.measureTime (not a user-defined function with the same name).
        if let calleeName,
           interner.resolve(calleeName) == "measureTime",
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTime"], ctx: ctx)
        {
            // Infer the block argument with an expected function type () -> Unit
            // so non-callable arguments are caught during type checking.
            let blockType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockType
            )
            // Look up the synthetic Duration class to build the return type.
            let durationFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("Duration")]
            let durationType: TypeID
            if let durationSymbol = sema.symbols.lookup(fqName: durationFQName) {
                durationType = sema.types.make(.classType(ClassType(
                    classSymbol: durationSymbol, args: [], nullability: .nonNull
                )))
            } else {
                durationType = sema.types.anyType
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTime)
            sema.bindings.bindExprType(id, type: durationType)
            return durationType
        }

        // --- Stdlib kotlin.time.measureTimedValue { ... } (STDLIB-660) ---
        if let calleeName,
           calleeName == interner.intern("measureTimedValue"),
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTimedValue"], ctx: ctx)
        {
            // Infer the block argument with an expected function type () -> T
            // so non-callable arguments are caught during type checking.
            let blockType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockType
            )

            // Look up the TimedValue class to build the return type.
            let timedValueFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("TimedValue")]
            let timedValueType: TypeID
            if let timedValueSymbol = sema.symbols.lookup(fqName: timedValueFQName) {
                timedValueType = sema.types.make(.classType(ClassType(
                    classSymbol: timedValueSymbol, args: [], nullability: .nonNull
                )))
            } else {
                timedValueType = sema.types.anyType
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTimedValue)
            sema.bindings.bindExprType(id, type: timedValueType)
            return timedValueType
        }

        // --- Stdlib Array(size) { init } constructor (STDLIB-085/086, TYPE-103) ---
        if let calleeName,
           knownNames.isPrimitiveArrayConstructorTypeName(calleeName),
           args.count == 2,
           locals[calleeName] == nil
        {
            let intType = sema.types.intType
            let calleeNameStr = interner.resolve(calleeName)
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            // Determine the element type from the expected type annotation or
            // the init lambda's return type, avoiding erasure to Any.
            //
            // Only extract the generic argument from the expected type when:
            //   1. The callee is "Array" (not a primitive array like IntArray), AND
            //   2. The expected type is actually kotlin.Array<...> (not some unrelated
            //      generic type like List<String>).
            // Primitive arrays (IntArray, LongArray, etc.) have fixed element types
            // that must not be overridden by contextual expected types.
            let arrayFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("Array"),
            ]
            let kotlinArraySymbol = sema.symbols.lookup(fqName: arrayFQName)
            let isKotlinArray = calleeNameStr == "Array"
            let inferLambdaOnce: Bool
            let elementReturnType: TypeID
            if isKotlinArray,
               let explicitTypeArg = explicitTypeArgs.first
            {
                elementReturnType = explicitTypeArg
                inferLambdaOnce = true
            } else if isKotlinArray,
               let kotlinArraySymbol,
               let expectedType, expectedType != sema.types.errorType,
               case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
               expectedClassType.classSymbol == kotlinArraySymbol,
               let firstArg = expectedClassType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    elementReturnType = type
                case .star:
                    elementReturnType = sema.types.anyType
                }
                inferLambdaOnce = true
            } else if isKotlinArray {
                // No expected type and no explicit type argument for Array(size) { init }.
                // Infer the lambda with `it` constrained to Int, then extract the
                // actual body return type from bindings to avoid erasing to Any.
                let lambdaExpected = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: sema.types.makeNullable(sema.types.anyType)
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: lambdaExpected
                )
                // Read back the lambda body's actual inferred type.
                let bodyType: TypeID? = if case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(args[1].expr) {
                    sema.bindings.exprTypes[body]
                } else {
                    nil
                }
                let inferred = bodyType ?? sema.types.anyType
                elementReturnType = (inferred != sema.types.errorType) ? inferred : sema.types.anyType
                inferLambdaOnce = false
            } else {
                // For primitive array constructors, the element type is fixed.
                elementReturnType = switch calleeNameStr {
                case "IntArray": sema.types.intType
                case "LongArray": sema.types.longType
                case "ShortArray": sema.types.intType
                case "ByteArray": sema.types.intType
                case "DoubleArray": sema.types.make(.primitive(.double, .nonNull))
                case "FloatArray": sema.types.make(.primitive(.float, .nonNull))
                case "BooleanArray": sema.types.booleanType
                case "CharArray": sema.types.make(.primitive(.char, .nonNull))
                default: sema.types.anyType
                }
                inferLambdaOnce = false
            }
            let initExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: elementReturnType
            )))
            if !inferLambdaOnce {
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initExpectedType
                )
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
            sema.bindings.markCollectionExpr(id)
            let resultType: TypeID
            if calleeNameStr == "Array" {
                resultType = makeSyntheticArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: elementReturnType
                )
            } else {
                resultType = makeSyntheticPrimitiveArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    arrayName: calleeNameStr
                )
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- Stdlib enumValues<T>() / enumValueOf<T>(name) (STDLIB-171) ---
        if let calleeName,
           let enumSpecialKind = enumStdlibSpecialCallKind(
               calleeName: calleeName,
               args: args,
               explicitTypeArgs: explicitTypeArgs,
               ctx: ctx,
               locals: locals,
               interner: interner,
               sema: sema,
               range: range
           )
        {
            switch enumSpecialKind {
            case let .enumValues(_, arrayType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValues)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: arrayType)
                return arrayType
            case let .enumValueOf(enumType, stubSymbol):
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValueOf)
                sema.bindings.bindExprType(id, type: enumType)
                return enumType
            case let .enumEntries(enumType, entriesType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [enumType],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumEntries)
                sema.bindings.bindExprType(id, type: entriesType)
                return entriesType
            }
        }

        if let calleeName,
           (args.count == 2 || args.count == 3)
        {
            // Infer the first argument without an expected type to determine the overload.
            let firstArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )

            // Resolve which numeric type this overload targets.
            let supportedNumericTypes = [sema.types.longType, sema.types.doubleType, sema.types.floatType, sema.types.intType]
            let resolvedParamType = supportedNumericTypes.first(where: { firstArgType == $0 }) ?? sema.types.intType

            if let specialKind = comparisonSpecialCallKind(
                for: calleeName,
                argCount: args.count,
                resolvedParamType: resolvedParamType,
                ctx: ctx,
                locals: locals
            ) {
                let expectedType = resolvedParamType

                // Emit subtype constraint for the first argument.
                driver.emitSubtypeConstraint(
                    left: firstArgType,
                    right: expectedType,
                    range: ast.arena.exprRange(args[0].expr) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )

                // Infer remaining arguments with the resolved type.
                for i in 1 ..< args.count {
                    let argType = driver.inferExpr(
                        args[i].expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: expectedType
                    )
                    driver.emitSubtypeConstraint(
                        left: argType,
                        right: expectedType,
                        range: ast.arena.exprRange(args[i].expr) ?? range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                }

                let paramTypes = Array(repeating: expectedType, count: args.count)
                let chosen = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.parameterTypes == paramTypes
                })
                if let chosen,
                   let signature = sema.symbols.functionSignature(for: chosen)
                {
                    var paramMapping: [Int: Int] = [:]
                    for i in 0 ..< args.count {
                        paramMapping[i] = i
                    }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [],
                            parameterMapping: paramMapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                    sema.bindings.bindExprType(id, type: signature.returnType)
                    return signature.returnType
                }
                sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                sema.bindings.bindExprType(id, type: expectedType)
                return expectedType
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "contract",
           args.count == 1
        {
            let builderSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("contracts"),
                interner.intern("ContractBuilder"),
            ])
            let builderType = builderSymbol.map {
                sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
            } ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: builderType,
                params: [],
                returnType: sema.types.unitType
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx.with(implicitReceiverType: builderType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // --- Comparator factory functions: compareBy, compareByDescending (STDLIB-649) ---
        if let calleeName,
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let calleeNameStr = interner.resolve(calleeName)
            if calleeNameStr == "compareBy" || calleeNameStr == "compareByDescending" {
                // Resolve the Comparator<T> return type.
                // The lambda selector has signature (T) -> Comparable<*>.
                // T is inferred from explicit type args, calling context, or defaults to Any.
                let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                    explicitT
                } else if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                // Bind to the synthetic function symbol
                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.count == 1
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        // --- Comparator factory functions: naturalOrder, reverseOrder (STDLIB-649) ---
        if let calleeName,
           args.isEmpty,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let calleeNameStr = interner.resolve(calleeName)
            if calleeNameStr == "naturalOrder" || calleeNameStr == "reverseOrder" {
                let elementType: TypeID = if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.isEmpty
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [:]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        if let calleeName,
           calleeName == knownNames.channel,
           args.isEmpty
        {
            let visibleCandidates = ctx.cachedScopeLookup(calleeName)
            let channelSymbol = visibleCandidates.first { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function
                else {
                    return false
                }
                return sema.symbols.externalLinkName(for: candidate) == "kk_channel_create"
            } ?? visibleCandidates.compactMap { candidate -> SymbolID? in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .class,
                      sema.symbols.externalLinkName(for: candidate) == nil
                else {
                    return nil
                }
                let ctorFQName = symbol.fqName + [interner.intern("<init>")]
                return sema.symbols.lookupAll(fqName: ctorFQName).first { ctorID in
                    sema.symbols.externalLinkName(for: ctorID) == "kk_channel_create"
                }
            }.first
            if let channelSymbol {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: channelSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(channelSymbol))
                let resultType: TypeID = if let explicitTypeArg = explicitTypeArgs.first,
                                            let signature = sema.symbols.functionSignature(for: channelSymbol),
                                            case let .classType(classType) = sema.types.kind(of: signature.returnType)
                {
                    sema.types.make(.classType(ClassType(
                        classSymbol: classType.classSymbol,
                        args: [.invariant(explicitTypeArg)],
                        nullability: classType.nullability
                    )))
                } else {
                    sema.symbols.functionSignature(for: channelSymbol)?.returnType ?? sema.types.anyType
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "delay",
           args.count == 1
        {
            let delayArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.longType
            )
            if delayArgType == sema.types.intType,
               let argumentExpr = ast.arena.expr(args[0].expr),
               case .intLiteral = argumentExpr
            {
                sema.bindings.bindExprType(args[0].expr, type: sema.types.longType)
            } else {
                driver.emitSubtypeConstraint(
                    left: delayArgType,
                    right: sema.types.longType,
                    range: ast.arena.exprRange(args[0].expr) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        let coroutineLauncherName = calleeName.map { interner.resolve($0) }
        let coroutineLauncherExpectedLambdaType: TypeID?
        if let coroutineLauncherName,
           ["runBlocking", "launch", "async", "coroutineScope"].contains(coroutineLauncherName),
           let firstArg = args.first,
           let firstArgExpr = ast.arena.expr(firstArg.expr),
           case .lambdaLiteral = firstArgExpr
        {
            let lambdaReturnType: TypeID = switch coroutineLauncherName {
            case "launch":
                sema.types.unitType
            default:
                expectedType ?? sema.types.anyType
            }
            coroutineLauncherExpectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: lambdaReturnType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            coroutineLauncherExpectedLambdaType = nil
        }
        let withContextExpectedLambdaType: TypeID? = if let calleeName,
                                                        (calleeName == knownNames.withContext
                                                            || calleeName == knownNames.withTimeout
                                                            || calleeName == knownNames.withTimeoutOrNull),
                                                        args.count >= 2,
                                                        let secondArgExpr = ast.arena.expr(args[1].expr),
                                                        case .lambdaLiteral = secondArgExpr
        {
            sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: expectedType ?? sema.types.anyType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            nil
        }

        if let calleeName,
           let samCallType = inferSamConvertedCallExpr(
               id,
               calleeName: calleeName,
               args: args,
               range: range,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs
           )
        {
            sema.bindings.bindExprType(id, type: samCallType)
            return samCallType
        }

        var candidates: [SymbolID]
        var callInvisible: [SemanticSymbol] = []
        if let calleeName {
            let allCallCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            // @DslMarker restriction: filter out candidates that belong to an
            // outer receiver class that shares a DslMarker annotation with the
            // current implicit receiver.
            let dslBlockedCandidates = allCallCandidates.filter { ctx.isCandidateBlockedByDslMarker($0) }
            let dslFiltered = allCallCandidates.filter { !ctx.isCandidateBlockedByDslMarker($0) }
            let (vis, invis) = ctx.filterByVisibility(dslFiltered)
            candidates = vis
            callInvisible = invis
            // If all candidates were blocked by DslMarker, emit a specific diagnostic.
            if candidates.isEmpty, !dslBlockedCandidates.isEmpty {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-DSLMARKER",
                    "'@DslMarker' implicit access to '\(interner.resolve(calleeName))' from outer receiver is restricted. Use explicit receiver.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if candidates.isEmpty, let local = locals[calleeName] {
                if let sym = ctx.cachedSymbol(local.symbol), sym.kind == .function {
                    candidates = [local.symbol]
                }
            }
            if candidates.isEmpty {
                let classSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .annotationClass || symbol.kind == .object
                }
                if let classSym = classSymbols.first, let classSymbol = ctx.cachedSymbol(classSym) {
                    // P5-112: Prohibit direct instantiation of abstract classes.
                    if classSymbol.flags.contains(.abstractType) {
                        let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-ABSTRACT",
                            "Cannot create an instance of abstract class '\(className)'.",
                            range: range
                        )
                        sema.bindings.bindExprType(id, type: sema.types.errorType)
                        return sema.types.errorType
                    }
                    let initName = interner.intern("<init>")
                    let ctorFQName = classSymbol.fqName + [initName]
                    let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                    if !ctorSymbols.isEmpty {
                        let (vis, invis) = ctx.filterByVisibility(ctorSymbols)
                        candidates = vis
                        callInvisible.append(contentsOf: invis)
                    }
                }
            }
            // --- Typealias constructor calls ---
            // If the callee is a typealias (e.g. `typealias IntPair = Pair<Int, Int>`),
            // expand it to the underlying class and resolve its constructor.
            if candidates.isEmpty {
                let aliasSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .typeAlias
                }
                if let aliasSym = aliasSymbols.first {
                    let aliasTypeParameters = sema.symbols.typeAliasTypeParameters(for: aliasSym)
                    let aliasTypeArgs: [TypeArg] = if !explicitTypeArgs.isEmpty {
                        explicitTypeArgs.map { TypeArg.invariant($0) }
                    } else if !aliasTypeParameters.isEmpty,
                              let expectedType,
                              case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
                    {
                        Array(expectedClassType.args.prefix(aliasTypeParameters.count))
                    } else {
                        []
                    }
                    if let expanded = driver.helpers.expandTypeAlias(
                        aliasSym,
                        typeArgs: aliasTypeArgs,
                        sema: sema,
                        visited: [],
                        depth: 0,
                        diagnostics: ctx.semaCtx.diagnostics
                    ),
                       case let .classType(classType) = sema.types.kind(of: expanded),
                       let underlyingSymbol = ctx.cachedSymbol(classType.classSymbol)
                    {
                        let initName = interner.intern("<init>")
                        let ctorFQName = underlyingSymbol.fqName + [initName]
                        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                        if !ctorSymbols.isEmpty {
                            let (vis, invis) = ctx.filterByVisibility(ctorSymbols)
                            candidates = vis
                            callInvisible.append(contentsOf: invis)
                        }
                    }
                }
            }
        } else {
            candidates = []
        }
        let contextualArgExpectedTypes: [TypeID?] = if candidates.count == 1,
                                                       let signature = sema.symbols.functionSignature(for: candidates[0])
        {
            args.enumerated().map { index, argument in
                if index == 0, let coroutineLauncherExpectedLambdaType {
                    return coroutineLauncherExpectedLambdaType
                }
                if index == 1, let withContextExpectedLambdaType {
                    return withContextExpectedLambdaType
                }
                guard index < signature.parameterTypes.count else {
                    return nil
                }
                let parameterType = signature.parameterTypes[index]
                if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                    return parameterType
                }
                return nil
            }
        } else {
            args.indices.map { index in
                if index == 0, let coroutineLauncherExpectedLambdaType {
                    return coroutineLauncherExpectedLambdaType
                }
                if index == 1, let withContextExpectedLambdaType {
                    return withContextExpectedLambdaType
                }
                return nil
            }
        }
        let argTypes = args.enumerated().map { index, argument in
            if let contextualExpectedType = contextualArgExpectedTypes[index] {
                return driver.inferExpr(
                    argument.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: contextualExpectedType
                )
            }
            return driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }
        if !candidates.isEmpty {
            let resolvedArgs: [CallArg] = zip(args, argTypes).map { argument, type in
                CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: candidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName ?? InternedString(),
                    args: resolvedArgs,
                    explicitTypeArgs: explicitTypeArgs
                ),
                expectedType: expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                ctx: ctx.semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0023",
                    "Unresolved function '\(nameStr)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            // ANNO-001: Check for @Deprecated annotation on the resolved callee.
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: sema,
                interner: interner,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            if args.count == 2,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               ["kk_require_lazy", "kk_check_lazy", "kk_precondition_assert_lazy"].contains(externalLinkName)
            {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            applyContractEffects(
                chosen: chosen,
                args: args,
                argTypes: argTypes,
                ctx: ctx,
                locals: &locals
            )
            if let calleeName {
                let resolvedName = interner.resolve(calleeName)
                if KnownCompilerNames.stdlibCollectionFactoryNames.contains(resolvedName) {
                    sema.bindings.markCollectionExpr(id)
                }
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               [
                   "kk_int_progression_fromClosedRange",
                   "kk_long_progression_fromClosedRange",
                   "kk_uint_progression_fromClosedRange",
                   "kk_ulong_progression_fromClosedRange",
               ].contains(externalLinkName)
            {
                sema.bindings.markRangeExpr(id)
                if externalLinkName == "kk_ulong_progression_fromClosedRange" {
                    sema.bindings.markULongRangeExpr(id)
                }
            }
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        var callableTarget: CallableTarget?
        var callableCalleeType: TypeID?
        if let calleeName,
           let local = locals[calleeName]
        {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(calleeName))' must be initialized before use.",
                    range: range
                )
            }
            sema.bindings.bindIdentifier(calleeID, symbol: local.symbol)
            sema.bindings.bindExprType(calleeID, type: local.type)
            let localSymbolKind = ctx.cachedSymbol(local.symbol)?.kind
            if localSymbolKind != .function {
                callableTarget = .localValue(local.symbol)
                callableCalleeType = local.type
            }
        } else if let calleeName {
            if !ctx.cachedScopeLookup(calleeName).isEmpty {
                callableCalleeType = driver.inferExpr(
                    calleeID,
=======
        
        // 各Processorに処理を委譲
        let processors: [CallTypeProcessor] = [
            builderDSLProcessor,
            scopeFunctionProcessor,
            flowBuilderProcessor,
            stdlibSpecialCallProcessor,
            comparisonProcessor,
            contractProcessor,
            enumProcessor,
            samConversionProcessor
        ]
        
        for processor in processors {
            if processor.canHandle(calleeName: calleeName, args: args, ctx: ctx) {
                if let result = processor.processCall(
                    id,
                    calleeName: calleeName,
                    args: args,
                    range: range,
>>>>>>> /Users/kuu/.windsurf/worktrees/kotlin-compiler/kotlin-compiler-63220bb6/Sources/CompilerCore/Sema/TypeCheck/CallTypeChecker.swift
                    ctx: ctx,
                    locals: &locals,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs
                ) {
                    return result
                }
            }
        }
        
        // フォールバック: 通常の呼び出し処理
        return processRegularCall(
            id: id,
            calleeID: calleeID,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func processRegularCall(
        id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let calleeExpr = ast.arena.expr(calleeID)
        
        // 通常の関数呼び出しの解決
        // ここに元のCallTypeCheckerの一般的な呼び出し処理を実装
        
        // 一時的にエラー型を返す
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }
    
    // MARK: - 共通ユーティリティメソッド
    
    /// 呼び出し可能値の呼び出しを処理
    func inferCallableValueInvocation(
        _ id: ExprID,
        calleeType: TypeID,
        callableTarget: CallableTarget?,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?
    ) -> TypeID? {
        let sema = ctx.sema
        let nonNullCalleeType = sema.types.makeNonNullable(calleeType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCalleeType) else {
            return nil
        }
        
        // 関数型の呼び出し処理
        // 元のCallTypeChecker+CallableValueInvocation.swiftのロジックを移動
        
        return sema.types.anyType
    }
    
    /// 呼び出しをバインドして戻り型を解決
    func bindCallAndResolveReturnType(
        _ id: ExprID,
        chosen: SymbolID,
        resolved: ResolvedCall,
        sema: SemaModule
    ) -> TypeID {
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        
        if sema.symbols.externalLinkName(for: chosen) == "kk_string_split" {
            sema.bindings.markCollectionExpr(id)
        }
        
        if let signature = sema.symbols.functionSignature(for: chosen) {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            return sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        }
        
        return sema.types.anyType
    }
}

// swiftlint:enable type_body_length
