import Foundation

/// Helpers split from `CallTypeChecker+MemberCallInference.swift`:
/// Receiver-type predicates and synthetic-builtin dispatchers (Flow, Continuation, KClass, Channel, File, Coroutine handle).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs.
extension CallTypeChecker {

    /// Safe lookup for well-known stdlib symbols (List, Map, Pair, etc.).
    /// Returns `nil` if the symbol is not found. Callers should fall back to
    /// `sema.types.anyType` when the result is nil, following the error-resilient
    /// design principle (never crash on missing symbols).
    func lookupStdlibSymbol(_ name: String, symbols: SymbolTable, interner: StringInterner) -> SymbolID? {
        symbols.lookupByShortName(interner.intern(name)).first
    }

    /// Receiver check for the scope fallback that restores synthetic extensions excluded from import scopes.
    /// Aligns with `Helpers.collectMemberFunctionCandidates`: require `actual <: declared` when possible,
    /// but keep generics such as `Continuation<T>.intercepted` where `isSubtype(Continuation<Int>, Continuation<T>)`
    /// is not decided until inference (mirrors the `rangeUntil`/`genericReceiver` escape hatch there).
    func extensionSyntheticFallbackReceiverMatches(
        callSiteReceiver: TypeID,
        declaredReceiver: TypeID,
        sema: SemaModule
    ) -> Bool {
        let actual = sema.types.makeNonNullable(callSiteReceiver)
        let declared = sema.types.makeNonNullable(declaredReceiver)
        if sema.types.isSubtype(actual, declared) {
            return true
        }
        if case .typeParam = sema.types.kind(of: declared) {
            return true
        }
        func typeArgumentLikeMatch(actual: TypeID?, declared: TypeID?) -> Bool {
            switch (actual, declared) {
            case let (actual?, declared?):
                let actualNonNull = sema.types.makeNonNullable(actual)
                let declaredNonNull = sema.types.makeNonNullable(declared)
                if sema.types.isSubtype(actualNonNull, declaredNonNull) {
                    return true
                }
                if case .typeParam = sema.types.kind(of: declaredNonNull) {
                    return true
                }
                return false
            case (nil, nil):
                return true
            default:
                return false
            }
        }
        if case let .functionType(declaredFn) = sema.types.kind(of: declared),
           case let .functionType(actualFn) = sema.types.kind(of: actual),
           declaredFn.isSuspend == actualFn.isSuspend,
           declaredFn.params.count == actualFn.params.count,
           typeArgumentLikeMatch(actual: actualFn.receiver, declared: declaredFn.receiver),
           zip(actualFn.params, declaredFn.params).allSatisfy({ actualParam, declaredParam in
               typeArgumentLikeMatch(actual: actualParam, declared: declaredParam)
           }),
           typeArgumentLikeMatch(actual: actualFn.returnType, declared: declaredFn.returnType)
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .kClassType(actualKClass) = sema.types.kind(of: actual),
           declaredCt.classSymbol == sema.types.kClassInterfaceSymbol,
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t):
                   return typeArgumentLikeMatch(actual: actualKClass.argument, declared: t)
               case .in:
                   return true
               case .star:
                   return true
               }
           })
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .classType(actualCt) = sema.types.kind(of: actual),
           actualCt.classSymbol != declaredCt.classSymbol,
           sema.types.isNominalSubtypeSymbol(actualCt.classSymbol, of: declaredCt.classSymbol),
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t), let .in(t):
                   if case .typeParam = sema.types.kind(of: sema.types.makeNonNullable(t)) {
                       return true
                   }
                   return false
               case .star:
                   return false
               }
           })
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .classType(actualCt) = sema.types.kind(of: actual),
           actualCt.classSymbol == declaredCt.classSymbol,
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t), let .in(t):
                   if case .typeParam = sema.types.kind(of: sema.types.makeNonNullable(t)) {
                       return true
                   }
                   return false
               case .star:
                   return false
               }
           })
        {
            return true
        }
        if case let .kClassType(declaredKClass) = sema.types.kind(of: declared),
           case let .kClassType(actualKClass) = sema.types.kind(of: actual)
        {
            return typeArgumentLikeMatch(actual: actualKClass.argument, declared: declaredKClass.argument)
        }
        return false
    }

    func tryBuiltinFlowMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let memberName = ctx.interner.resolve(calleeName)
        let flowMembers: Set = [
            "map", "filter", "take", "collect", "toList", "first",
            "single",
            "transform", "takeWhile", "dropWhile", "flatMapConcat", "flatMapMerge", "flatMapLatest",
            "buffer", "conflate", "flowOn", "debounce", "sample", "delayEach",
            "catch", "retry", "retryWhen", "onErrorReturn", "onErrorResume",
        ]
        guard flowMembers.contains(memberName) else {
            return nil
        }

        switch memberName {
        case "toList":
            // Flow.toList() — collects all emitted values into a List
            guard args.isEmpty else {
                return nil
            }
            let listSymbol = sema.symbols.lookupByShortName(ctx.interner.intern("List")).first
            let resultType: TypeID = if let listSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "first":
            // Flow.first() — returns the first emitted value
            guard args.isEmpty else {
                return nil
            }
            let firstType = receiverElementType
            let finalType = safeCall ? sema.types.makeNullable(firstType) : firstType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "single":
            // Flow.single() — returns the only emitted value.
            guard args.isEmpty else {
                return nil
            }
            let singleType = receiverElementType
            let finalType = safeCall ? sema.types.makeNullable(singleType) : singleType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "take", "buffer", "debounce", "sample", "delayEach", "flowOn":
            guard args.count == 1 else {
                return nil
            }
            let expectedArgType: TypeID = memberName == "flowOn" ? sema.types.anyType : sema.types.intType
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedArgType)
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "conflate":
            guard args.isEmpty else {
                return nil
            }
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "retry":
            guard args.count == 1 else {
                return nil
            }
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.intType
            )
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "map", "filter", "collect", "transform", "takeWhile", "dropWhile",
             "flatMapConcat", "flatMapMerge", "flatMapLatest",
             "catch", "retryWhen", "onErrorReturn", "onErrorResume":
            guard args.count == 1 else {
                return nil
            }
            let expectsLambdaTypeConstraint = switch ast.arena.expr(args[0].expr) {
            case .callableRef:
                false
            default:
                true
            }
            let lambdaReturnType: TypeID = switch memberName {
            case "filter":
                sema.types.booleanType
            case "collect":
                sema.types.unitType
            case "takeWhile", "dropWhile":
                sema.types.unitType
            case "catch":
                sema.types.unitType
            case "retryWhen":
                sema.types.booleanType
            default:
                sema.types.anyType
            }
            let lambdaParameterTypes: [TypeID] = switch memberName {
            case "catch", "onErrorResume":
                [sema.types.anyType]
            case "retryWhen":
                [sema.types.anyType, sema.types.longType]
            default:
                [receiverElementType]
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: lambdaParameterTypes,
                returnType: lambdaReturnType,
                isSuspend: memberName == "collect",
                nullability: .nonNull
            )))
            if expectsLambdaTypeConstraint {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            } else {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            }

            if memberName != "collect" {
                sema.bindings.markFlowExpr(id)
                let resultElementType: TypeID = if memberName == "map" || memberName == "transform",
                                                   case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr),
                                                   let mappedType = sema.bindings.exprType(for: bodyExpr)
                {
                    mappedType
                } else if memberName == "flatMapConcat" || memberName == "flatMapMerge" || memberName == "flatMapLatest" {
                    sema.types.anyType
                } else {
                    receiverElementType
                }
                sema.bindings.bindFlowElementType(resultElementType, forExpr: id)
            }

            let resultType: TypeID
            if memberName == "collect" {
                resultType = sema.types.unitType
            } else {
                let resultElement = sema.bindings.flowElementType(forExpr: id) ?? receiverElementType
                resultType = driver.helpers.makeFlowType(
                    elementType: resultElement, sema: sema, interner: ctx.interner
                ) ?? sema.types.anyType
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        default:
            return nil
        }
    }

    func tryContinuationSyntheticMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        guard calleeName == knownNames.resume || calleeName == knownNames.resumeWith || calleeName == knownNames.resumeWithException else {
            return nil
        }
        guard let continuationSymbol = ctx.sema.symbols.lookup(fqName: knownNames.kotlinContinuationFQName),
              case let .classType(classType) = ctx.sema.types.kind(of: ctx.sema.types.makeNonNullable(receiverType)),
              classType.classSymbol == continuationSymbol
        else {
            return nil
        }
        guard args.count == 1 else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "No viable overload found for call.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: ctx.sema)
        }

        var expectedArgType: TypeID = ctx.sema.types.anyType
        if calleeName == knownNames.resume,
           case let .classType(classType) = ctx.sema.types.kind(of: ctx.sema.types.makeNonNullable(receiverType)),
           let continuationArg = classType.args.first
        {
            switch continuationArg {
            case let .invariant(type), let .out(type), let .in(type):
                expectedArgType = type
            case .star:
                expectedArgType = ctx.sema.types.anyType
            }
        } else if calleeName == knownNames.resumeWith,
                  case let .classType(classType) = ctx.sema.types.kind(of: ctx.sema.types.makeNonNullable(receiverType)),
                  let continuationArg = classType.args.first,
                  let resultSymbol = ctx.sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Result")])
        {
            let innerType: TypeID
            switch continuationArg {
            case let .invariant(type), let .out(type), let .in(type):
                innerType = type
            case .star:
                innerType = ctx.sema.types.anyType
            }
            expectedArgType = ctx.sema.types.make(.classType(ClassType(
                classSymbol: resultSymbol,
                args: [.out(innerType)],
                nullability: .nonNull
            )))
        }

        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedArgType)

        let expectedExternalLinkName = if calleeName == knownNames.resume {
            "kk_coroutine_continuation_resume"
        } else if calleeName == knownNames.resumeWith {
            "kk_coroutine_continuation_resume_with"
        } else {
            "kk_coroutine_continuation_resume_with_exception"
        }
        let functionSymbol = ctx.sema.symbols.lookupByShortName(calleeName).first(where: { candidate in
            guard let symbol = ctx.sema.symbols.symbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            return ctx.sema.symbols.externalLinkName(for: candidate) == expectedExternalLinkName
        })
        if let functionSymbol {
            ctx.sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: functionSymbol,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            ))
            ctx.sema.bindings.bindIdentifier(id, symbol: functionSymbol)
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }
        return nil
    }

    func kClassCastReturnType(
        from targetType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let nonNullTargetType = sema.types.makeNonNullable(targetType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullTargetType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.fqName.dropLast() == [interner.intern("kotlin")]
        else {
            return nonNullTargetType
        }
        let knownNames = KnownCompilerNames(interner: interner)
        return knownNames.builtinType(named: symbol.name, types: sema.types) ?? nonNullTargetType
    }

    func kClassSafeCastReturnType(
        from targetType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        sema.types.makeNullable(kClassCastReturnType(from: targetType, sema: sema, interner: interner))
    }

    func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isCoroutineHandleSymbol(symbol)
    }

    /// Returns true when the receiver type is java.io.File.
    func isFileType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.fqName.count >= 2
            && interner.resolve(symbol.fqName.last!) == "File"
            && interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == "io"
    }

    func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }

    func isKClassReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        kClassReceiverArgumentType(receiverType, sema: sema, interner: interner) != nil
    }

    func kClassReceiverArgumentType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if case let .kClassType(kClassType) = sema.types.kind(of: nonNullReceiverType) {
            return kClassType.argument
        }

        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let kotlinReflectKClassFQName = [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("KClass"),
        ]
        let kClassName = interner.intern("KClass")
        let isKClassSymbol = symbol.fqName == kotlinReflectKClassFQName
            || (symbol.name == kClassName && symbol.fqName.isEmpty)
        guard isKClassSymbol else {
            return nil
        }
        guard let firstArg = classType.args.first else {
            return sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
    }

    /// Handles numeric companion access on a type-name receiver:
    ///
    ///   - **Constants** (STDLIB-153): `Int.MAX_VALUE`, `Double.NaN`, `Float.POSITIVE_INFINITY`, etc.
    ///     when `args.isEmpty` — looked up via `numericCompanionConstant`.
    ///   - **Static functions** (STDLIB-NUM-130): `Double.fromBits(Long)`,
    ///     `Float.fromBits(Int)` etc. when `args.count == 1` — looked up via
    ///     `numericCompanionFunction`, with the receiver bound to `Unit` so
    ///     lowering does not pass the class name as an argument.
    ///
    /// Returns the inferred type when handled, or `nil` to fall through. Both
    /// branches require the receiver to be a `nameRef` (typed identifier) that
    /// is not currently bound as a local — an Int *value* named `Int` shadows
    /// the type and falls through.
    func tryInferNumericCompanionMemberCall(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
              locals[receiverName] == nil
        else {
            return nil
        }

        let receiverStr = interner.resolve(receiverName)
        let memberStr = interner.resolve(calleeName)

        // STDLIB-153: Numeric companion constants — Int.MAX_VALUE, Double.NaN, etc.
        if args.isEmpty,
           let (constantType, constantValue) = numericCompanionConstant(
               typeName: receiverStr, memberName: memberStr, sema: sema
           )
        {
            sema.bindings.bindConstExprValue(id, value: constantValue)
            sema.bindings.bindExprType(id, type: constantType)
            return constantType
        }

        // STDLIB-NUM-130: Numeric companion static functions — Double.fromBits(Long), Float.fromBits(Int).
        if args.count == 1,
           let (returnType, externalName) = numericCompanionFunction(
               typeName: receiverStr, memberName: memberStr, sema: sema
           )
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let fromBitsName = interner.intern(memberStr)
            let kotlinPkgName: [InternedString] = [interner.intern("kotlin")]
            let funcFQName = kotlinPkgName + [fromBitsName]
            let allCandidates = sema.symbols.lookupAll(fqName: funcFQName)
            if let funcSymbol = allCandidates.first(where: { sid in
                sema.symbols.symbol(sid)?.kind == .function
                    && sema.symbols.externalLinkName(for: sid) == externalName
            }) {
                sema.bindings.bindIdentifier(id, symbol: funcSymbol)
                sema.bindings.bindExprType(id, type: returnType)
                // Bind receiver as Unit so lowering does not pass the class name as argument.
                sema.bindings.bindExprType(receiverID, type: sema.types.unitType)
                return returnType
            }
        }

        return nil
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// This legacy inference path still owns many special cases while the split-out helpers
    /// are being migrated.
}
