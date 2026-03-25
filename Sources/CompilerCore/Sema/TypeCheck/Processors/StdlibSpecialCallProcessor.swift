import Foundation

class StdlibSpecialCallProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        let calleeNameStr = ctx.interner.resolve(calleeName)
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        
        // Regex constructor
        if calleeName == knownNames.regexCtor && args.count == 1 {
            return true
        }
        
        // generateSequence
        if calleeNameStr == "generateSequence" && args.count == 2 {
            return true
        }
        
        // repeat
        if calleeNameStr == "repeat" && args.count == 2 {
            return true
        }
        
        // measureTime functions
        if (calleeNameStr == "measureTimeMillis" || calleeNameStr == "measureNanoTime") && args.count == 1 {
            return !isShadowedByNonSyntheticSymbol(calleeName, ctx: ctx)
        }
        
        // kotlin.time.measureTime
        if calleeNameStr == "measureTime" && args.count == 1 {
            return !isShadowedByNonSyntheticSymbol(calleeName, ctx: ctx) &&
                   isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTime"], ctx: ctx)
        }
        
        // measureTimedValue
        if calleeName == ctx.interner.intern("measureTimedValue") && args.count == 1 {
            return !isShadowedByNonSyntheticSymbol(calleeName, ctx: ctx) &&
                   isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTimedValue"], ctx: ctx)
        }
        
        // Array constructors
        if knownNames.isPrimitiveArrayConstructorTypeName(calleeName) && args.count == 2 {
            return true
        }
        
        return false
    }
    
    func processCall(
        _ id: ExprID,
        calleeName: InternedString?,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let calleeName = calleeName else { return nil }
        
        let calleeNameStr = ctx.interner.resolve(calleeName)
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        let sema = ctx.sema
        
        // Regex constructor
        if calleeName == knownNames.regexCtor && args.count == 1 {
            return processRegexConstructor(id: id, args: args, ctx: ctx, locals: &locals, sema: sema, interner: ctx.interner)
        }
        
        // generateSequence
        if calleeNameStr == "generateSequence" && args.count == 2 {
            return processGenerateSequence(id: id, args: args, ctx: ctx, locals: &locals, sema: sema, interner: ctx.interner)
        }
        
        // repeat
        if calleeNameStr == "repeat" && args.count == 2 {
            return processRepeatFunction(id: id, args: args, range: range, ctx: ctx, locals: &locals, sema: sema)
        }
        
        // measureTime functions
        if calleeNameStr == "measureTimeMillis" && args.count == 1 {
            return processMeasureTimeMillis(id: id, args: args, ctx: ctx, locals: &locals, sema: sema)
        }
        
        if calleeNameStr == "measureNanoTime" && args.count == 1 {
            return processMeasureNanoTime(id: id, args: args, ctx: ctx, locals: &locals, sema: sema)
        }
        
        // kotlin.time.measureTime
        if calleeNameStr == "measureTime" && args.count == 1 {
            return processKotlinTimeMeasureTime(id: id, args: args, ctx: ctx, locals: &locals, sema: sema, interner: ctx.interner)
        }
        
        // measureTimedValue
        if calleeName == ctx.interner.intern("measureTimedValue") && args.count == 1 {
            return processMeasureTimedValue(id: id, args: args, ctx: ctx, locals: &locals, sema: sema, interner: ctx.interner)
        }
        
        // Array constructors
        if knownNames.isPrimitiveArrayConstructorTypeName(calleeName) && args.count == 2 {
            return processArrayConstructor(id: id, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs, sema: sema, interner: ctx.interner)
        }
        
        return nil
    }
    
        
    private func processRegexConstructor(
        id: ExprID, args: [CallArgument], ctx: TypeInferenceContext, locals: inout LocalBindings, sema: SemaModule, interner: StringInterner
    ) -> TypeID {
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
    
    private func processGenerateSequence(
        id: ExprID, args: [CallArgument], ctx: TypeInferenceContext, locals: inout LocalBindings, sema: SemaModule, interner: StringInterner
    ) -> TypeID {
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
        ) ?? sema.types.anyType
        
        sema.bindings.bindExprType(id, type: sequenceType)
        return sequenceType
    }
    
    private func processRepeatFunction(
        id: ExprID, args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext, locals: inout LocalBindings, sema: SemaModule
    ) -> TypeID {
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
            range: ctx.ast.arena.exprRange(args[0].expr) ?? range,
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
    
    private func processMeasureTimeMillis(
        id: ExprID, args: [CallArgument], ctx: TypeInferenceContext, locals: inout LocalBindings, sema: SemaModule
    ) -> TypeID {
        let longType = sema.types.longType
        
        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
        sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTimeMillis)
        sema.bindings.bindExprType(id, type: longType)
        return longType
    }
    
    private func processMeasureNanoTime(
        id: ExprID, args: [CallArgument], ctx: TypeInferenceContext, locals: inout LocalBindings, sema: SemaModule
    ) -> TypeID {
        let longType = sema.types.longType
        
        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
        sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureNanoTime)
        sema.bindings.bindExprType(id, type: longType)
        return longType
    }
    
    private func processKotlinTimeMeasureTime(
        id: ExprID, args: [CallArgument], ctx: TypeInferenceContext, locals: inout LocalBindings, sema: SemaModule, interner: StringInterner
    ) -> TypeID {
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        
        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: blockType)
        
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
    
    private func processMeasureTimedValue(
        id: ExprID, args: [CallArgument], ctx: TypeInferenceContext, locals: inout LocalBindings, sema: SemaModule, interner: StringInterner
    ) -> TypeID {
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        
        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: blockType)
        
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
    
    private func processArrayConstructor(
        id: ExprID, calleeName: InternedString, args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext, locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID], sema: SemaModule, interner: StringInterner
    ) -> TypeID {
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
            range: ctx.ast.arena.exprRange(args[0].expr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]
        let kotlinArraySymbol = sema.symbols.lookup(fqName: arrayFQName)
        let isKotlinArray = calleeNameStr == "Array"
        
        let inferLambdaOnce: Bool
        let elementReturnType: TypeID
        
        if isKotlinArray, let explicitTypeArg = explicitTypeArgs.first {
            elementReturnType = explicitTypeArg
            inferLambdaOnce = true
        } else if isKotlinArray, let kotlinArraySymbol, let expectedType, expectedType != sema.types.errorType,
                  case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                  expectedClassType.classSymbol == kotlinArraySymbol,
                  let firstArg = expectedClassType.args.first {
            switch firstArg {
            case let .invariant(type), let .in(type), let .out(type):
                elementReturnType = type
            case .star:
                elementReturnType = sema.types.anyType
            }
            inferLambdaOnce = true
        } else if isKotlinArray {
            let lambdaExpected = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: sema.types.makeNullable(sema.types.anyType)
            )))
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpected)
            
            let bodyType: TypeID? = if case let .lambdaLiteral(_, body, _, _) = ctx.ast.arena.expr(args[1].expr) {
                sema.bindings.exprTypes[body]
            } else {
                nil
            }
            let inferred = bodyType ?? sema.types.anyType
            elementReturnType = (inferred != sema.types.errorType) ? inferred : sema.types.anyType
            inferLambdaOnce = false
        } else {
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
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: initExpectedType)
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
            ) ?? sema.types.anyType
        } else {
            resultType = makeSyntheticPrimitiveArrayType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                arrayName: calleeNameStr
            ) ?? sema.types.anyType
        }
        
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }
}
