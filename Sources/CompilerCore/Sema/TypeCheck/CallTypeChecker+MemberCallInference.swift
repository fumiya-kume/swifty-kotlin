// swiftlint:disable file_length
import Foundation

extension CallTypeChecker {
    /// Safe lookup for well-known stdlib symbols (List, Map, Pair, etc.).
    /// Returns `nil` if the symbol is not found. Callers should fall back to
    /// `sema.types.anyType` when the result is nil, following the error-resilient
    /// design principle (never crash on missing symbols).
    private func lookupStdlibSymbol(_ name: String, symbols: SymbolTable, interner: StringInterner) -> SymbolID? {
        symbols.lookupByShortName(interner.intern(name)).first
    }

    /// Receiver check for the scope fallback that restores synthetic extensions excluded from import scopes.
    /// Aligns with `Helpers.collectMemberFunctionCandidates`: require `actual <: declared` when possible,
    /// but keep generics such as `Continuation<T>.intercepted` where `isSubtype(Continuation<Int>, Continuation<T>)`
    /// is not decided until inference (mirrors the `rangeUntil`/`genericReceiver` escape hatch there).
    private func extensionSyntheticFallbackReceiverMatches(
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
        return false
    }

    private func tryBuiltinFlowMemberCall(
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

    private func tryContinuationSyntheticMemberCall(
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

    private func kClassCastReturnType(
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

    private func kClassSafeCastReturnType(
        from targetType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        sema.types.makeNullable(kClassCastReturnType(from: targetType, sema: sema, interner: interner))
    }

    private func isCoroutineHandleReceiverType(
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
    private func isFileType(
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

    private func isChannelReceiverType(
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

    private func isKClassReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        kClassReceiverArgumentType(receiverType, sema: sema, interner: interner) != nil
    }

    private func kClassReceiverArgumentType(
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

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// This legacy inference path still owns many special cases while the split-out helpers
    /// are being migrated.
    func inferMemberCallImpl(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        // swiftlint:enable cyclomatic_complexity function_body_length

        if ["firstNotNullOf", "firstNotNullOfOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceRightOrNull", "sumBy", "sumByDouble"]
            .contains(interner.resolve(calleeName)),
           args.count == 1,
           let lambdaExpr = ast.arena.expr(args[0].expr),
           lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        }

        if args.isEmpty,
           case .callableRef = ast.arena.expr(receiverID),
           calleeName == knownNames.isInitialized
        {
            _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
            if let propertySymbol = sema.bindings.identifierSymbol(for: receiverID),
               let propertyInfo = sema.symbols.symbol(propertySymbol),
               propertyInfo.kind == .property,
               propertyInfo.flags.contains(.lateinitProperty)
            {
                let boolType = sema.types.make(.primitive(.boolean, .nonNull))
                sema.bindings.bindExprType(id, type: boolType)
                return boolType
            }

            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'isInitialized' is only available on lateinit property references.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // ── T::class.simpleName / T::class.qualifiedName ──────────────
        // Detect member access on a class-reference expression (callableRef
        // with member "class").  The result type is nullable String.
        // We eagerly infer the receiver so classRefTargetType gets bound,
        // then verify it was actually set (guards against `x::class` where
        // x is a local variable rather than a type name).
        if case let .callableRef(_, refMember, _) = ast.arena.expr(receiverID),
           refMember == knownNames.className
        {
            _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
            if sema.bindings.classRefTargetType(for: receiverID) != nil {
                if calleeName == knownNames.simpleName || calleeName == knownNames.qualifiedName {
                    _ = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals) }
                    let nullableStringType = sema.types.makeNullable(
                        sema.types.make(.primitive(.string, .nonNull))
                    )
                    sema.bindings.bindExprType(id, type: nullableStringType)
                    return nullableStringType
                }
                if calleeName == knownNames.isInstanceName, args.count == 1 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                    let boolType = sema.types.booleanType
                    sema.bindings.bindExprType(id, type: boolType)
                    return boolType
                }
                if calleeName == knownNames.kClassCastName, args.count == 1 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                    let targetType = sema.bindings.classRefTargetType(for: receiverID) ?? sema.types.anyType
                    let returnType = kClassCastReturnType(from: targetType, sema: sema, interner: interner)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
                if calleeName == knownNames.kClassSafeCastName, args.count == 1 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                    let targetType = sema.bindings.classRefTargetType(for: receiverID) ?? sema.types.anyType
                    let returnType = kClassSafeCastReturnType(from: targetType, sema: sema, interner: interner)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
                // STDLIB-REFLECT-060: KClass boolean properties (isFinal, isOpen, isAbstract)
                let kclassBooleanCallees: Set<InternedString> = [
                    knownNames.isFinalName, knownNames.isOpenName, knownNames.isAbstractName,
                ]
                if kclassBooleanCallees.contains(calleeName), args.isEmpty {
                    let boolType = sema.types.booleanType
                    sema.bindings.bindExprType(id, type: boolType)
                    return boolType
                }
                // STDLIB-REFLECT-060: KClass.visibility -> String?
                if calleeName == knownNames.visibilityName, args.isEmpty {
                    let nullableStringType = sema.types.makeNullable(
                        sema.types.make(.primitive(.string, .nonNull))
                    )
                    sema.bindings.bindExprType(id, type: nullableStringType)
                    return nullableStringType
                }
                // STDLIB-REFLECT-065: annotations
                let kclassMemberCollectionCallees: Set<InternedString> = [
                    knownNames.membersName, knownNames.constructorsName,
                    knownNames.propertiesName, knownNames.memberPropertiesName,
                    knownNames.declaredMemberPropertiesName,
                    knownNames.functionsName, knownNames.memberFunctionsName,
                    knownNames.declaredMemberFunctionsName,
                    // STDLIB-REFLECT-060: KClass collection properties
                    knownNames.typeParametersName, knownNames.supertypesName,
                    knownNames.annotationsName,
                ]
                if kclassMemberCollectionCallees.contains(calleeName), args.isEmpty {
                    let listType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.anyType
                    )
                    sema.bindings.markCollectionExpr(id)
                    sema.bindings.bindExprType(id, type: listType)
                    return listType
                }
                // STDLIB-REFLECT-065: findAnnotation<T>()
                if calleeName == knownNames.findAnnotationName {
                    // Infer arguments if present.
                    for arg in args {
                        _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
                    }
                    let nullableAnyType = sema.types.makeNullable(sema.types.anyType)
                    sema.bindings.bindExprType(id, type: nullableAnyType)
                    return nullableAnyType
                }
                // STDLIB-REFLECT-079: findAssociatedObject<T>()
                if calleeName == knownNames.findAssociatedObjectName {
                    return bindKClassFindAssociatedObjectCall(
                        id,
                        args: args,
                        explicitTypeArgs: explicitTypeArgs,
                        range: range,
                        ctx: ctx,
                        locals: &locals
                    )
                }
            }
        }

        // Numeric companion constants: Int.MAX_VALUE, Double.NaN, etc. (STDLIB-153)
        if args.isEmpty,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
           locals[receiverName] == nil
        {
            let receiverStr = interner.resolve(receiverName)
            let memberStr = interner.resolve(calleeName)
            if let (constantType, constantValue) = numericCompanionConstant(
                typeName: receiverStr, memberName: memberStr, sema: sema
            ) {
                sema.bindings.bindConstExprValue(id, value: constantValue)
                sema.bindings.bindExprType(id, type: constantType)
                return constantType
            }
        }

        // STDLIB-NUM-130: Numeric companion static functions: Double.fromBits(Long), Float.fromBits(Int)
        if args.count == 1,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
           locals[receiverName] == nil
        {
            let receiverStr = interner.resolve(receiverName)
            let memberStr = interner.resolve(calleeName)
            if let (returnType, externalName) = numericCompanionFunction(
                typeName: receiverStr, memberName: memberStr, sema: sema
            ) {
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
                    // Bind receiver as unit so lowering does not pass the class name as argument.
                    sema.bindings.bindExprType(receiverID, type: sema.types.unitType)
                    return returnType
                }
            }
        }

        let receiverType = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        let recoveredReceiverType: TypeID? = if case .any = sema.types.kind(of: sema.types.makeNonNullable(receiverType)) {
            if let symbol = sema.bindings.identifierSymbol(for: receiverID),
               let propertyType = sema.symbols.propertyType(for: symbol)
            {
                propertyType
            } else if case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
                      let local = locals[receiverName]
            {
                sema.symbols.propertyType(for: local.symbol) ?? local.type
            } else {
                nil
            }
        } else {
            nil
        }
        let effectiveCallRecursiveReceiverType = recoveredReceiverType ?? receiverType
        if interner.resolve(calleeName) == "flatMapIndexed",
           args.count == 1,
           isSequenceLikeType(receiverType, sema: sema, interner: interner)
        {
            let receiverElementType: TypeID = if case let .classType(classType) = sema.types.kind(
                of: sema.types.makeNonNullable(receiverType)
            ), let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, receiverElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let lambdaBodyType = inferredLambdaReturnType(
                argExpr: args[0].expr,
                ast: ast,
                sema: sema
            )
            let flattenedElementType = getCollectionElementType(
                lambdaBodyType,
                sema: sema,
                interner: interner
            )
            if let owner = driver.helpers.nominalSymbol(
                of: sema.types.makeNonNullable(receiverType),
                types: sema.types
            ),
               let ownerSymbol = sema.symbols.symbol(owner)
            {
                let memberFQName = ownerSymbol.fqName + [calleeName]
                if let fallbackCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == owner,
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.parameterTypes.count == 1
                }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: fallbackCallee,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
            }
            }
            sema.bindings.markCollectionExpr(id)
            let resultType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: flattenedElementType
            )
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if interner.resolve(calleeName) == "callRecursive",
           args.count == 1,
           case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(effectiveCallRecursiveReceiverType)),
           let receiverSymbol = sema.symbols.symbol(classType.classSymbol),
           receiverSymbol.fqName.count == 2,
           interner.resolve(receiverSymbol.fqName[0]) == "kotlin",
           interner.resolve(receiverSymbol.fqName[1]) == "DeepRecursiveFunction"
        {
            let parameterType: TypeID = if let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let returnType: TypeID = if classType.args.count > 1 {
                switch classType.args[1] {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: parameterType)
            if let memberSymbol = sema.symbols.lookupAll(fqName: [
                interner.intern("kotlin"),
                interner.intern("DeepRecursiveScope"),
                interner.intern("callRecursive"),
            ]).first(where: { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == "kk_deep_recursive_function_callRecursive"
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: memberSymbol,
                        substitutedTypeArguments: [parameterType, returnType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(memberSymbol))
            }
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        if let boundContinuationCall = tryContinuationSyntheticMemberCall(
            id,
            calleeName: calleeName,
            receiverType: receiverType,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals
        ) {
            return boundContinuationCall
        }

        if let kClassArgumentType = kClassReceiverArgumentType(receiverType, sema: sema, interner: interner) {
            if calleeName == knownNames.isInstanceName, args.count == 1 {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let boolType = sema.types.booleanType
                sema.bindings.bindExprType(id, type: boolType)
                return boolType
            }
            if calleeName == knownNames.kClassCastName, args.count == 1 {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let returnType = kClassCastReturnType(from: kClassArgumentType, sema: sema, interner: interner)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
            if calleeName == knownNames.kClassSafeCastName, args.count == 1 {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let returnType = kClassSafeCastReturnType(from: kClassArgumentType, sema: sema, interner: interner)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
            // STDLIB-REFLECT-060: KClass boolean properties via variable receiver
            let kclassVarBooleanCallees: Set<InternedString> = [
                knownNames.isFinalName, knownNames.isOpenName, knownNames.isAbstractName,
            ]
            if kclassVarBooleanCallees.contains(calleeName), args.isEmpty {
                let boolType = sema.types.booleanType
                sema.bindings.bindExprType(id, type: boolType)
                return boolType
            }
            // STDLIB-REFLECT-060: KClass.visibility via variable receiver -> String?
            if calleeName == knownNames.visibilityName, args.isEmpty {
                let nullableStringType = sema.types.makeNullable(
                    sema.types.make(.primitive(.string, .nonNull))
                )
                sema.bindings.bindExprType(id, type: nullableStringType)
                return nullableStringType
            }
            // STDLIB-REFLECT-065: annotations
            let kclassVarMemberCollectionCallees: Set<InternedString> = [
                knownNames.membersName, knownNames.constructorsName,
                knownNames.propertiesName, knownNames.memberPropertiesName,
                knownNames.declaredMemberPropertiesName,
                knownNames.functionsName, knownNames.memberFunctionsName,
                knownNames.declaredMemberFunctionsName,
                // STDLIB-REFLECT-060: KClass collection properties
                knownNames.typeParametersName, knownNames.supertypesName,
                knownNames.annotationsName,
            ]
            if kclassVarMemberCollectionCallees.contains(calleeName), args.isEmpty {
                let listType = makeSyntheticListType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: sema.types.anyType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: listType)
                return listType
            }
            // STDLIB-REFLECT-065: findAnnotation<T>()
            if calleeName == knownNames.findAnnotationName {
                for arg in args {
                    _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
                }
                let nullableAnyType = sema.types.makeNullable(sema.types.anyType)
                sema.bindings.bindExprType(id, type: nullableAnyType)
                return nullableAnyType
            }
            // STDLIB-REFLECT-079: findAssociatedObject<T>()
            if calleeName == knownNames.findAssociatedObjectName {
                return bindKClassFindAssociatedObjectCall(
                    id,
                    args: args,
                    explicitTypeArgs: explicitTypeArgs,
                    range: range,
                    ctx: ctx,
                    locals: &locals
                )
            }
        }

        if args.isEmpty,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
           locals[receiverName] == nil,
           let ownerSymbol = ctx.cachedScopeLookup(receiverName).first(where: { candidate in
               guard let symbol = sema.symbols.symbol(candidate) else {
                   return false
               }
               switch symbol.kind {
               case .class, .interface, .enumClass:
                   return true
               default:
                   return false
               }
           }),
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           )
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: memberSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }

        // --- Scope functions: let, run, apply, also (STDLIB-004) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct expected type (it vs. receiver this).
        // Skip interception when the receiver type defines a real member
        // with the same name (user-defined members take precedence).
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let scopeKind: ScopeFunctionKind? = switch calleeStr {
            case "let": .scopeLet
            case "run": .scopeRun
            case "apply": .scopeApply
            case "also": .scopeAlso
            case "use" where isCloseableReceiver(receiverType, sema: sema, interner: interner): .scopeUse
            default: nil
            }
            let hasUserDefinedMember = if scopeKind != nil {
                !driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ).isEmpty
            } else {
                false
            }
            if let scopeKind, !hasUserDefinedMember {
                let nonNullReceiverType = safeCall
                    ? sema.types.makeNonNullable(receiverType)
                    : receiverType

                switch scopeKind {
                case .scopeLet:
                    // let: lambda receives `it` parameter typed as T, returns R
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
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
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeRun:
                    // run: lambda has receiver T as `this`, returns R
                    let receiverCtx = ctx.with(implicitReceiverType: nonNullReceiverType)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: nonNullReceiverType,
                        params: [],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: receiverCtx, locals: &locals,
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
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeApply:
                    // apply: lambda has receiver T as `this`, returns T (receiver itself)
                    let receiverCtx = ctx.with(implicitReceiverType: nonNullReceiverType)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: nonNullReceiverType,
                        params: [],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(
                        args[0].expr, ctx: receiverCtx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let finalType = safeCall
                        ? sema.types.makeNullable(nonNullReceiverType)
                        : nonNullReceiverType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    // Propagate collection marking: apply returns receiver unchanged,
                    // so chained member calls (e.g. .let { it.size }) must still see
                    // the collection type. (STDLIB-002-BUG-01)
                    if isCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                        sema.bindings.markCollectionExpr(id)
                    }
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeAlso:
                    // also: lambda receives `it` parameter typed as T, returns T
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let finalType = safeCall
                        ? sema.types.makeNullable(nonNullReceiverType)
                        : nonNullReceiverType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    // Propagate collection marking: also returns receiver unchanged,
                    // so chained member calls (e.g. .let { it.size }) must still see
                    // the collection type. (STDLIB-002-BUG-01)
                    if isCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                        sema.bindings.markCollectionExpr(id)
                    }
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeUse:
                    // use: lambda receives `it` parameter typed as T, returns R.
                    // Semantically equivalent to `let` but wraps in try-finally { close() }.
                    // NOTE: The lambda inference below intentionally duplicates scopeLet logic.
                    // The duplication is deliberate — use and let share the same type inference
                    // semantics (receiver passed as `it`, lambda return type becomes call result)
                    // but differ in lowering (use emits try-finally with close()).
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
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
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeWith:
                    break // with is handled in inferCallExpr (top-level function)

                case .scopeTopLevelRun:
                    break // top-level run is handled in inferCallExpr
                }
            }
        }

        // --- Result member functions (STDLIB-590) ---
        // Result<T>.onSuccess/onFailure/getOrElse/getOrDefault/map/fold/recover
        // These require special handling because the generic type parameter T
        // needs to be extracted from the receiver's Result<out T> type and used
        // to construct the expected lambda parameter types.
        if args.count >= 1, args.count <= 2 {
            let calleeStr = interner.resolve(calleeName)
            let resultMemberNames: Set = [
                "onSuccess", "onFailure", "getOrElse", "getOrDefault", "map", "fold", "recover",
            ]
            if resultMemberNames.contains(calleeStr),
               let resultElementType = extractResultElementType(receiverType, sema: sema, interner: interner)
            {
                let throwableType = driver.helpers.throwableType(sema: sema, interner: interner) ?? sema.types.anyType
                let nonNullReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType

                switch calleeStr {
                case "onSuccess" where args.count == 1:
                    // onSuccess(action: (T) -> Unit): Result<T>
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let onSuccessSymbol = lookupResultMember("onSuccess", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: onSuccessSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "onFailure" where args.count == 1:
                    // onFailure(action: (Throwable) -> Unit): Result<T>
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let onFailureSymbol = lookupResultMember("onFailure", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: onFailureSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "getOrElse" where args.count == 1:
                    // getOrElse(onFailure: (Throwable) -> T): T
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: resultElementType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let getOrElseSymbol = lookupResultMember("getOrElse", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: getOrElseSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultElementType) : resultElementType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "getOrDefault" where args.count == 1:
                    // getOrDefault(defaultValue: T): T
                    let defaultExpectedType = resultElementType
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: defaultExpectedType)
                    if let getOrDefaultSymbol = lookupResultMember("getOrDefault", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: getOrDefaultSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultElementType) : resultElementType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "map" where args.count == 1:
                    // map(transform: (T) -> R): Result<R>
                    // Note: only intercept for Result receiver, not for collections
                    // expectedType is Result<R>, so extract R for the lambda return type
                    let lambdaReturnType = expectedType.flatMap({ extractResultElementType($0, sema: sema, interner: interner) }) ?? sema.types.anyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: lambdaReturnType
                    )))
                    let lambdaType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    let mappedType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    if let mapSymbol = lookupResultMember("map", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: mapSymbol,
                            substitutedTypeArguments: [resultElementType, mappedType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let mappedResultType = makeResultType(elementType: mappedType, sema: sema, interner: interner) ?? sema.types.anyType
                    let finalType = safeCall ? sema.types.makeNullable(mappedResultType) : mappedResultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "recover" where args.count == 1:
                    // recover(transform: (Throwable) -> T): Result<T>
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: resultElementType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let recoverSymbol = lookupResultMember("recover", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: recoverSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "fold" where args.count == 2:
                    // fold(onSuccess: (T) -> R, onFailure: (Throwable) -> R): R
                    let onSuccessExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let onSuccessType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: onSuccessExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    let foldReturnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: onSuccessType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    let onFailureExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: foldReturnType
                    )))
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: onFailureExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    if let foldSymbol = lookupResultMember("fold", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: foldSymbol,
                            substitutedTypeArguments: [resultElementType, foldReturnType],
                            parameterMapping: [0: 0, 1: 1]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(foldReturnType) : foldReturnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                default:
                    break
                }
            }
        }

        // --- takeIf / takeUnless (STDLIB-160) ---
        // T.takeIf((T) -> Boolean): T? / T.takeUnless((T) -> Boolean): T?
        // Inline-expanded by CallLowerer; no runtime call.
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let takeKind: TakeIfTakeUnlessKind? = switch calleeStr {
            case "takeIf": .takeIf
            case "takeUnless": .takeUnless
            default: nil
            }
            let hasUserDefinedMember = if takeKind != nil {
                !driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ).isEmpty
            } else {
                false
            }
            if let takeKind, !hasUserDefinedMember {
                let nonNullReceiverType = safeCall
                    ? sema.types.makeNonNullable(receiverType)
                    : receiverType
                let boolType = sema.types.make(.primitive(.boolean, .nonNull))
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [nonNullReceiverType],
                    returnType: boolType
                )))
                _ = driver.inferExpr(
                    args[0].expr, ctx: ctx, locals: &locals,
                    expectedType: lambdaExpectedType
                )
                let nullableReceiverType = sema.types.makeNullable(nonNullReceiverType)
                let finalType = nullableReceiverType
                sema.bindings.markTakeIfTakeUnlessExpr(id, kind: takeKind)
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // --- File lambda-accepting methods: forEachLine, useLines (STDLIB-322) ---
        // These require the lambda to use the collection HOF closure ABI (closureRaw
        // prepended), and the lambda's implicit `it` must be correctly resolved.
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let isFileReceiver = isFileType(receiverType, sema: sema, interner: interner)
            if isFileReceiver && (calleeStr == "forEachLine" || calleeStr == "useLines") {
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                let lambdaParamType: TypeID
                let lambdaReturnType: TypeID
                let callReturnType: TypeID
                if calleeStr == "forEachLine" {
                    // forEachLine { line: String -> Unit }
                    lambdaParamType = sema.types.stringType
                    lambdaReturnType = sema.types.unitType
                    callReturnType = sema.types.unitType
                } else {
                    // useLines { lines: List<String> -> T }
                    let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                    lambdaParamType = if let listSym = listSymbol {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSym,
                            args: [.out(sema.types.stringType)],
                            nullability: .nonNull
                        )))
                    } else {
                        sema.types.anyType
                    }
                    lambdaReturnType = expectedType ?? sema.types.anyType
                    callReturnType = expectedType ?? sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [lambdaParamType],
                    returnType: lambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let inferredLambdaType = driver.inferExpr(
                    args[0].expr, ctx: ctx, locals: &locals,
                    expectedType: lambdaExpectedType
                )
                // For useLines, extract the actual return type from the lambda
                let finalReturnType: TypeID
                if calleeStr == "useLines" {
                    if case let .functionType(fnType) = sema.types.kind(of: inferredLambdaType) {
                        finalReturnType = fnType.returnType
                    } else {
                        finalReturnType = callReturnType
                    }
                } else {
                    finalReturnType = callReturnType
                }
                let finalType = safeCall ? sema.types.makeNullable(finalReturnType) : finalReturnType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Defer inference of lambda arguments for collection HOFs so that the
        // contextual function type (and thus implicit `it`) is available.
        let collectionHOFNames: Set = [
            "map", "filter", "filterNot", "mapNotNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
            "fold", "foldRight", "reduce", "reduceOrNull", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "foldIndexed", "foldRightIndexed", "reduceIndexed", "reduceIndexedOrNull",
            "scan", "scanIndexed", "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "scanReduce",
            "groupBy", "groupingBy", "reduceTo", "sortedBy", "count", "first", "last", "find",
            "associateBy", "associateWith", "associate", "associateTo", "associateByTo", "associateWithTo", "groupByTo",
            "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo", "mapIndexedTo", "flatMapIndexedTo",
            "mapIndexedNotNullTo", "filterIndexedTo", "filterNotNullTo",
            "forEachIndexed", "mapIndexed",
            "firstNotNullOf",
            "firstNotNullOfOrNull",
            "onEach", "onEachIndexed",
            "sumOf", "sumBy", "maxOrNull", "minOrNull",
            "indexOfFirst", "indexOfLast", "binarySearch", "binarySearchBy",
            "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull",
            "maxOf", "minOf",
            "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
            "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
            "sortedByDescending", "sortedWith", "partition", "takeWhile", "dropWhile", "distinctBy", "zipWithNext",
            "flatten",
            "sort", "sortBy", "sortByDescending",
        ]
        let flowHOFNames: Set = ["map", "filter", "collect"]
        let mapOnlyCollectionHOFNames: Set = ["mapValues", "mapKeys", "filterKeys", "filterValues"]
        let mutableListOnlyCollectionHOFNames: Set = ["sort", "sortBy", "sortByDescending"]
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverID) {
            true
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else {
            false
        }
        let flowElementType: TypeID = if let elementType = sema.bindings.flowElementType(forExpr: receiverID) {
            elementType
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  let elementType = sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else {
            sema.types.anyType
        }
        let isFlowHOF = isFlowReceiver && flowHOFNames.contains(interner.resolve(calleeName))
        let isCollectionReceiver = sema.bindings.isCollectionExpr(receiverID)
            || isCollectionLikeType(receiverType, sema: sema, interner: interner)
        let isArrayReceiver = isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMapReceiver = isMapLikeCollectionType(receiverType, sema: sema, interner: interner)
        let isMutableListReceiver = isMutableListType(receiverType, sema: sema, interner: interner)
        let isSyntheticSequenceReceiver = sema.bindings.isCollectionExpr(receiverID)
            && !isCollectionLikeType(receiverType, sema: sema, interner: interner)
            && !isMapReceiver
        let isSequenceReceiver = isSequenceLikeType(receiverType, sema: sema, interner: interner)
            || isSyntheticSequenceReceiver
        var activeCollectionHOFNames = collectionHOFNames
        if !isMutableListReceiver {
            activeCollectionHOFNames.subtract(mutableListOnlyCollectionHOFNames)
        }
        if !isSequenceReceiver {
            activeCollectionHOFNames.remove("flatMapIndexed")
            activeCollectionHOFNames.remove("firstNotNullOf")
            activeCollectionHOFNames.remove("firstNotNullOfOrNull")
        }
        if isMapReceiver {
            activeCollectionHOFNames.formUnion(mapOnlyCollectionHOFNames)
        }
        let isCollectionHOF = activeCollectionHOFNames.contains(interner.resolve(calleeName))
            && (isCollectionReceiver || isSequenceReceiver)
            && !(interner.resolve(calleeName) == "binarySearch"
                 && isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner))

        if interner.resolve(calleeName) == "asFlow",
           args.isEmpty,
           (isCollectionReceiver || isSequenceReceiver)
        {
            let elementType = if isCollectionReceiver {
                resolvedCollectionElementType(
                    receiverID: receiverID,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner,
                    ctx: ctx,
                    locals: &locals
                )
            } else {
                sema.types.anyType
            }
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(elementType, forExpr: id)
            let resultType = driver.helpers.makeFlowType(
                elementType: elementType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterIsInstance<R>() — reified type parameter, returns List<R> (STDLIB-114)
        if interner.resolve(calleeName) == "filterIsInstance",
           args.isEmpty,
           isCollectionReceiver
        {
            let filterType = explicitTypeArgs.first ?? sema.types.anyType
            if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                let resultType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(filterType)],
                    nullability: .nonNull
                )))
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        if interner.resolve(calleeName) == "toCollection",
           args.count == 1,
           isCollectionReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "filterIsInstanceTo",
           args.count == 1,
           isCollectionReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterNotNullTo(destination) — no lambda, returns destination type (STDLIB-SEQ-021)
        if interner.resolve(calleeName) == "filterNotNullTo",
           args.count == 1,
           isCollectionReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "binarySearch",
           isConcreteListLikeType(receiverType, sema: sema, interner: interner),
           args.count == 1,
           let lambdaExpr = ast.arena.expr(args[0].expr),
           lambdaExpr.isLambdaOrCallableRef
        {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "binarySearch",
           isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        {
            let knownNames = KnownCompilerNames(interner: interner)
            let receiverClassName: InternedString? = {
                guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    return nil
                }
                return symbol.name
            }()
            let isGenericArrayReceiver = receiverClassName == knownNames.array
            if receiverClassName == knownNames.booleanArray {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let arrayElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            if args.count == 4,
               let comparatorSymbol = sema.symbols.lookup(fqName: [
                   interner.intern("kotlin"),
                   interner.intern("Comparator"),
               ])
            {
                guard isGenericArrayReceiver else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                let comparatorExpectedType = sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(arrayElementType)],
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: arrayElementType)
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            } else if !isGenericArrayReceiver {
                if args.indices.contains(0) {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: arrayElementType)
                }
                if args.indices.contains(1) {
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                    if let chosen = sema.bindings.callBinding(for: args[1].expr)?.chosenCallee {
                        let chosenName = sema.symbols.symbol(chosen).map { interner.resolve($0.name) }
                        let externalLinkName = sema.symbols.externalLinkName(for: chosen)
                        let isComparatorFactory = externalLinkName?.hasPrefix("kk_comparator_") == true
                            || ["compareBy", "compareByDescending", "naturalOrder", "reverseOrder"].contains(chosenName ?? "")
                        if isComparatorFactory {
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-0002",
                                "No viable overload found for call.",
                                range: range
                            )
                            sema.bindings.bindExprType(id, type: sema.types.errorType)
                            return sema.types.errorType
                        }
                    }
                }
                if args.indices.contains(2) {
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
            }
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if let groupingType = tryGroupingMemberCall(
            id,
            calleeName: calleeName,
            receiverID: receiverID,
            receiverType: receiverType,
            args: args,
            safeCall: safeCall,
            expectedType: expectedType,
            ast: ast,
            sema: sema,
            ctx: ctx,
            locals: &locals
        ) {
            return groupingType
        }

        let isGroupingReceiver: Bool = {
            let knownNames = KnownCompilerNames(interner: interner)
            guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return knownNames.isGroupingSymbol(symbol)
        }()
        let calleeStr = interner.resolve(calleeName)

        if isGroupingReceiver {
            let groupingTypeInfo: (element: TypeID, key: TypeID) = {
                if let receiverExpr = ast.arena.expr(receiverID),
                   case let .memberCall(innerReceiverID, innerCallee, _, innerArgs, _) = receiverExpr,
                   interner.resolve(innerCallee) == "groupingBy",
                   innerArgs.count == 1
                {
                    let innerReceiverType = sema.bindings.exprType(for: innerReceiverID)
                        ?? driver.inferExpr(innerReceiverID, ctx: ctx, locals: &locals)
                    let sourceElementType = resolvedCollectionElementType(
                        receiverID: innerReceiverID,
                        receiverType: innerReceiverType,
                        sema: sema,
                        interner: interner,
                        ctx: ctx,
                        locals: &locals
                    )
                    let keyType = inferredLambdaReturnType(
                        argExpr: innerArgs[0].expr, ast: ast, sema: sema
                    )
                    return (sourceElementType, keyType)
                }

                let receiverTypeToInspect = sema.bindings.exprType(for: receiverID)
                    ?? driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
                let elementType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverTypeToInspect),
                                                    ct.args.count >= 1
                {
                    switch ct.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let keyType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverTypeToInspect),
                                               ct.args.count >= 2
                {
                    switch ct.args[1] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                return (elementType, keyType)
            }()
            switch calleeStr {
            case "eachCount":
                let groupingKeyType = groupingTypeInfo.key
                if let mapSymbol = sema.symbols.lookupByShortName(interner.intern("Map")).first {
                    let resultType = sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [.invariant(groupingKeyType), .invariant(sema.types.intType)],
                        nullability: .nonNull
                    )))
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType

            case "foldTo":
                guard args.count == 3 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
                let destinationMapKeyType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                       destClassType.args.count >= 2
                {
                    switch destClassType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let destinationMapValueType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                           destClassType.args.count >= 2
                {
                    switch destClassType.args[1] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let groupingElementType = groupingTypeInfo.element
                let groupingKeyType = groupingTypeInfo.key == sema.types.anyType
                    ? destinationMapKeyType
                    : groupingTypeInfo.key
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    let initialValueSelectorType = sema.types.make(.functionType(FunctionType(
                        params: [groupingKeyType, groupingElementType],
                        returnType: destinationMapValueType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: initialValueSelectorType)
                    let initialValueType = destinationMapValueType == sema.types.anyType
                        ? inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                        : destinationMapValueType
                    let operationExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [groupingKeyType, initialValueType, groupingElementType],
                        returnType: initialValueType
                    )))
                    if let operationLambdaExpr = ast.arena.expr(args[2].expr), operationLambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[2].expr)
                    }
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                } else {
                    let initialValueType: TypeID
                    if destinationMapValueType == sema.types.anyType {
                        initialValueType = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
                    } else {
                        initialValueType = driver.inferExpr(
                            args[1].expr, ctx: ctx, locals: &locals, expectedType: destinationMapValueType
                        )
                    }
                    let operationExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [initialValueType, groupingElementType],
                        returnType: initialValueType
                    )))
                    if let operationLambdaExpr = ast.arena.expr(args[2].expr), operationLambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[2].expr)
                    }
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                }
                sema.bindings.bindExprType(id, type: destinationType)
                return destinationType

            default:
                break
            }
        }

        if interner.resolve(calleeName) == "binarySearch",
           isArrayReceiver
        {
            let knownNames = KnownCompilerNames(interner: interner)
            let isGenericArrayReceiver: Bool = {
                guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                return symbol.name == knownNames.array && classType.args.count == 1
            }()
            let arrayElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            if args.count == 4,
               let comparatorSymbol = sema.symbols.lookup(fqName: [
                   interner.intern("kotlin"),
                   interner.intern("Comparator"),
               ])
            {
                guard isGenericArrayReceiver else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                let comparatorExpectedType = sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(arrayElementType)],
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: arrayElementType)
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            } else if !isGenericArrayReceiver {
                if args.indices.contains(0) {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: arrayElementType)
                }
                if args.indices.contains(1) {
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                    if let chosen = sema.bindings.callBinding(for: args[1].expr)?.chosenCallee {
                        let chosenName = sema.symbols.symbol(chosen).map { interner.resolve($0.name) }
                        let externalLinkName = sema.symbols.externalLinkName(for: chosen)
                        let isComparatorFactory = externalLinkName?.hasPrefix("kk_comparator_") == true
                            || ["compareBy", "compareByDescending", "naturalOrder", "reverseOrder"].contains(chosenName ?? "")
                        if isComparatorFactory {
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-0002",
                                "No viable overload found for call.",
                                range: range
                            )
                            sema.bindings.bindExprType(id, type: sema.types.errorType)
                            return sema.types.errorType
                        }
                    }
                }
                if args.indices.contains(2) {
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
            }
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // --- Collection higher-order functions (STDLIB-005) ---
        if isCollectionHOF {
            let calleeStr = interner.resolve(calleeName)
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )

            let resultType: TypeID
            let destinationCollectionHOFs: Set = [
                "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo",
                "mapIndexedTo", "mapIndexedNotNullTo", "flatMapIndexedTo", "associateTo",
                "filterIndexedTo",
            ]
            if destinationCollectionHOFs.contains(calleeStr), args.count == 2 {
                let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
                let destinationElementType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                          destClassType.args.count >= 1
                {
                    switch destClassType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let destinationMapKeyType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                          destClassType.args.count >= 2
                {
                    switch destClassType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let destinationMapValueType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                            destClassType.args.count >= 2
                {
                    switch destClassType.args[1] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let pairReturnType: TypeID = if calleeStr == "associateTo" {
                    if let pairSymbol = lookupStdlibSymbol("Pair", symbols: sema.symbols, interner: interner) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: pairSymbol,
                            args: [.invariant(destinationMapKeyType), .invariant(destinationMapValueType)],
                            nullability: .nonNull
                        )))
                    } else {
                        sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let lambdaExpectedType: TypeID = switch calleeStr {
                case "filterTo", "filterNotTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.booleanType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "filterIndexedTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [sema.types.intType, collectionElementType],
                        returnType: sema.types.booleanType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "mapTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: destinationElementType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "flatMapTo":
                    {
                        if let collectionSymbol = lookupStdlibSymbol("Collection", symbols: sema.symbols, interner: interner) {
                            let iterableType = sema.types.make(.classType(ClassType(
                                classSymbol: collectionSymbol,
                                args: [.invariant(destinationElementType)],
                                nullability: .nonNull
                            )))
                            return sema.types.make(.functionType(FunctionType(
                                params: [collectionElementType],
                                returnType: iterableType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        } else {
                            return sema.types.make(.functionType(FunctionType(
                                params: [collectionElementType],
                                returnType: sema.types.anyType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        }
                    }()
                case "mapNotNullTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.makeNullable(destinationElementType),
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "mapIndexedTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [sema.types.intType, collectionElementType],
                        returnType: destinationElementType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "mapIndexedNotNullTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [sema.types.intType, collectionElementType],
                        returnType: sema.types.makeNullable(destinationElementType),
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "flatMapIndexedTo":
                    {
                        if let collectionSymbol = lookupStdlibSymbol("Collection", symbols: sema.symbols, interner: interner) {
                            let iterableType = sema.types.make(.classType(ClassType(
                                classSymbol: collectionSymbol,
                                args: [.invariant(destinationElementType)],
                                nullability: .nonNull
                            )))
                            return sema.types.make(.functionType(FunctionType(
                                params: [sema.types.intType, collectionElementType],
                                returnType: iterableType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        } else {
                            return sema.types.make(.functionType(FunctionType(
                                params: [sema.types.intType, collectionElementType],
                                returnType: sema.types.anyType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        }
                    }()
                case "associateTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: pairReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                default:
                    sema.types.anyType
                }
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = destinationType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            switch calleeStr {
            case "map", "filter", "filterNot", "filterKeys", "filterValues", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
                 "count", "first", "last", "find", "associateBy", "associateWith", "associate",
                 "mapValues", "mapKeys", "takeWhile", "dropWhile", "onEach":
                // any(), none(), count(), first(), last() can be called with no args
                if args.isEmpty {
                    switch calleeStr {
                    case "any", "none": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last": resultType = sema.types.makeNullable(collectionElementType)
                    default: resultType = sema.types.anyType
                    }
                } else {
                    let lambdaReturnType: TypeID = switch calleeStr {
                    case "filter", "filterNot", "any", "none", "all", "takeWhile", "dropWhile": sema.types.booleanType
                    case "forEach", "onEach": sema.types.unitType
                    case "count": sema.types.booleanType
                    case "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull": sema.types.nullableAnyType
                    default: sema.types.anyType
                    }
                    let lambdaParameterTypes = calleeStr == "flatMapIndexed"
                        ? [sema.types.intType, collectionElementType]
                        : [collectionElementType]
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)

                    switch calleeStr {
                    case "map":
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            fnType.returnType
                        } else {
                            sema.types.anyType
                        }
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: bodyType
                            )
                        } else {
                            if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                                resultType = sema.types.make(.classType(ClassType(
                                    classSymbol: listSymbol,
                                    args: [.invariant(bodyType)],
                                    nullability: .nonNull
                                )))
                            } else {
                                resultType = sema.types.anyType
                            }
                        }
                    case "filter", "filterNot":
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: collectionElementType
                            )
                        } else {
                            resultType = receiverType
                        }
                    case "takeWhile", "dropWhile":
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: collectionElementType
                            )
                        } else {
                            resultType = receiverType
                        }
                    case "forEach": resultType = sema.types.unitType
                    case "onEach":
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: collectionElementType
                            )
                        } else {
                            resultType = receiverType
                        }
                    case "flatMap":
                        let lambdaBodyType = inferredLambdaReturnType(
                            argExpr: args[0].expr, ast: ast, sema: sema
                        )
                        let innerElementType = extractListElementType(
                            lambdaBodyType, sema: sema, interner: interner
                        )
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: innerElementType
                            )
                        } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(innerElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "flatMapIndexed":
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [sema.types.intType, collectionElementType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        let lambdaBodyType = inferredLambdaReturnType(
                            argExpr: args[0].expr, ast: ast, sema: sema
                        )
                        let innerElementType = extractIterableOrSequenceElementType(
                            lambdaBodyType,
                            sema: sema,
                            interner: interner
                        )
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: innerElementType
                            )
                        } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(innerElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "any", "none", "all": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last", "find": resultType = sema.types.makeNullable(collectionElementType)
                    case "associateBy":
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            let keyType = inferredLambdaReturnType(
                                argExpr: args[0].expr, ast: ast, sema: sema
                            )
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(keyType), .invariant(collectionElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "associateWith":
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            let valueType = inferredLambdaReturnType(
                                argExpr: args[0].expr, ast: ast, sema: sema
                            )
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(collectionElementType), .invariant(valueType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "associate":
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            let lambdaBodyType = inferredLambdaReturnType(
                                argExpr: args[0].expr, ast: ast, sema: sema
                            )
                            let nonNullBodyType = sema.types.makeNonNullable(lambdaBodyType)
                            let keyType: TypeID
                            let valueType: TypeID
                            if case let .classType(pairClass) = sema.types.kind(of: nonNullBodyType),
                               pairClass.args.count == 2,
                               let pairSym = sema.symbols.symbol(pairClass.classSymbol),
                               pairSym.name == interner.intern("Pair")
                            {
                                keyType = switch pairClass.args[0] {
                                case let .invariant(id), let .out(id), let .in(id): id
                                case .star: sema.types.anyType
                                }
                                valueType = switch pairClass.args[1] {
                                case let .invariant(id), let .out(id), let .in(id): id
                                case .star: sema.types.anyType
                                }
                            } else {
                                keyType = sema.types.anyType
                                valueType = sema.types.anyType
                            }
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(keyType), .invariant(valueType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "mapValues" where isMapReceiver:
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            fnType.returnType
                        } else {
                            sema.types.anyType
                        }
                        let keyType: TypeID = if case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                 classType.args.count >= 2
                        {
                            switch classType.args[0] {
                            case let .invariant(id), let .out(id), let .in(id): id
                            case .star: sema.types.anyType
                            }
                        } else {
                            sema.types.anyType
                        }
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(keyType), .invariant(bodyType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "mapKeys" where isMapReceiver:
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            fnType.returnType
                        } else {
                            sema.types.anyType
                        }
                        let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                   classType.args.count >= 2
                        {
                            switch classType.args[1] {
                            case let .invariant(id), let .out(id), let .in(id): id
                            case .star: sema.types.anyType
                            }
                        } else {
                            sema.types.anyType
                        }
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(bodyType), .invariant(valueType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "filterKeys" where isMapReceiver:
                        resultType = sema.types.makeNonNullable(receiverType)
                    case "filterValues" where isMapReceiver:
                        resultType = sema.types.makeNonNullable(receiverType)
                    case "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull":
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            sema.types.makeNonNullable(fnType.returnType)
                        } else {
                            sema.types.anyType
                        }
                        if calleeStr == "firstNotNullOf" {
                            resultType = bodyType
                        } else if calleeStr == "firstNotNullOfOrNull" {
                            resultType = sema.types.makeNullable(bodyType)
                        } else if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: bodyType
                            )
                        } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(bodyType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    default: resultType = sema.types.anyType
                    }
                }

            case "fold":
                if let groupingKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) {
                    guard args.count == 2 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let expectedGroupingValueType: TypeID = if let expectedType,
                                                               case let .classType(expectedClassType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
                                                               let expectedSymbol = sema.symbols.symbol(expectedClassType.classSymbol),
                                                               knownNames.isMapLikeSymbol(expectedSymbol),
                                                               expectedClassType.args.count >= 2
                    {
                        switch expectedClassType.args[1] {
                        case let .invariant(id), let .out(id), let .in(id): id
                        case .star: sema.types.anyType
                        }
                    } else {
                        sema.types.anyType
                    }
                    let firstArgLabel = args[0].label.map { interner.resolve($0) }
                    let useInitialValueSelectorOverload = if let firstArgLabel {
                        firstArgLabel == "initialValueSelector"
                    } else if case .lambdaLiteral = ast.arena.expr(args[0].expr) {
                        true
                    } else {
                        ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false
                    }
                    if useInitialValueSelectorOverload {
                        let initialValueSelectorExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [groupingKeyType, collectionElementType],
                            returnType: expectedGroupingValueType
                        )))
                        let initialValueSelectorType = driver.inferExpr(
                            args[0].expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: initialValueSelectorExpectedType
                        )
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        let groupingResultValueType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: initialValueSelectorType) {
                            fnType.returnType
                        } else if expectedGroupingValueType != sema.types.anyType {
                            expectedGroupingValueType
                        } else {
                            sema.types.anyType
                        }
                        let operationExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [groupingKeyType, groupingResultValueType, collectionElementType],
                            returnType: groupingResultValueType
                        )))
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                        }
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(groupingKeyType), .invariant(groupingResultValueType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    } else {
                        let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedGroupingValueType)
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [groupingKeyType, initialType, collectionElementType],
                            returnType: initialType
                        )))
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                        }
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(groupingKeyType), .invariant(initialType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    }
                } else {
                    guard args.count == 2 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [initialType, collectionElementType],
                        returnType: initialType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    }
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultType = initialType
                }

            case "foldIndexed":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, initialType, collectionElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = initialType

            case "foldRight":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, initialType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = initialType

            case "foldRightIndexed":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, initialType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = initialType

            case "reduceRight":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = collectionElementType

            case "reduce":
                if let groupingKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) {
                    guard args.count == 1 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: collectionElementType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(groupingKeyType), .invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                } else {
                    guard args.count == 1 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: collectionElementType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultType = collectionElementType
                }

            case "reduceOrNull":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "reduceOrNull() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let reduceOrNullLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: reduceOrNullLambdaType)
                resultType = sema.types.makeNullable(collectionElementType)

            case "reduceIndexed":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let reduceIndexedLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: reduceIndexedLambdaType)
                resultType = collectionElementType

            case "reduceIndexedOrNull":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let reduceIndexedOrNullLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: reduceIndexedOrNullLambdaType)
                resultType = sema.types.makeNullable(collectionElementType)

            case "scan", "runningFold":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "\(calleeStr)() expects 2 arguments (initial value and a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [initialType, collectionElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(initialType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "runningFoldIndexed", "scanIndexed":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "\(calleeStr)() expects 2 arguments (initial value and a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, initialType, collectionElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(initialType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "runningReduce":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "runningReduce() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "runningReduceIndexed":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "runningReduceIndexed() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "groupBy":
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let keyType = inferredLambdaReturnType(
                    argExpr: args[0].expr, ast: ast, sema: sema
                )
                // Two-lambda variant: groupBy(keySelector, valueTransform)
                var valueElementType = collectionElementType
                if args.count >= 2 {
                    let valueLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.anyType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[1].expr), case .lambdaLiteral = lambdaExpr {
                        sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    }
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: valueLambdaExpectedType)
                    valueElementType = inferredLambdaReturnType(
                        argExpr: args[1].expr, ast: ast, sema: sema
                    )
                }
                if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner),
                   let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner)
                {
                    let listType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(valueElementType)],
                        nullability: .nonNull
                    )))
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [.invariant(keyType), .invariant(listType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "associateByTo", "associateWithTo", "groupByTo":
                // *To(destination, keySelector/valueSelector): returns the destination map
                guard args.count == 2 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                // Infer the destination map argument first
                let destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                // Extract K/V from destination MutableMap<K, V> for stronger lambda return type inference
                let lambdaReturnType: TypeID
                if case let .classType(destClassType) = sema.types.kind(of: sema.types.makeNonNullable(destType)),
                   destClassType.args.count >= 2
                {
                    // For associateWithTo: lambda returns V (value type, args[1])
                    // For associateByTo/groupByTo: lambda returns K (key type, args[0])
                    let targetArgIndex = (calleeStr == "associateWithTo") ? 1 : 0
                    lambdaReturnType = switch destClassType.args[targetArgIndex] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    lambdaReturnType = sema.types.anyType
                }
                let lambdaExpectedType2 = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: lambdaReturnType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType2)
                // Return type is the destination map type
                resultType = destType

            case "groupingBy":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                // Infer key type K from lambda return type
                let keyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                    fnType.returnType
                } else {
                    sema.types.anyType
                }
                // Return Grouping<T, K> type
                if let groupingSymbol = sema.symbols.lookupByShortName(interner.intern("Grouping")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: groupingSymbol,
                        args: [.invariant(collectionElementType), .invariant(keyType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                sema.bindings.markCollectionExpr(id)

            case "eachCount":
                // Called on Grouping, returns Map<K, Int>
                // Extract key type K from receiver's Grouping<T, K> type args
                let eachCountKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) ?? sema.types.anyType
                if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [.invariant(eachCountKeyType), .invariant(sema.types.intType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "reduceTo":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "reduceTo() expects 2 arguments (destination and lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let reduceToKeyType: TypeID
                if case let .classType(ct) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                   ct.args.count >= 2,
                   case let .invariant(k) = ct.args[1] {
                    reduceToKeyType = k
                } else {
                    reduceToKeyType = sema.types.anyType
                }
                let reduceToAccumulatorType: TypeID
                if case let .classType(destCt) = sema.types.kind(of: sema.types.makeNonNullable(destType)),
                   destCt.args.count >= 2 {
                    switch destCt.args[1] {
                    case let .invariant(id), let .out(id), let .in(id):
                        reduceToAccumulatorType = id
                    case .star:
                        reduceToAccumulatorType = collectionElementType
                    }
                } else {
                    reduceToAccumulatorType = collectionElementType
                }
                let reduceToLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [reduceToKeyType, reduceToAccumulatorType, collectionElementType],
                    returnType: reduceToAccumulatorType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: reduceToLambdaType)
                resultType = destType

            case "eachCountTo":
                // Called on Grouping, returns the destination MutableMap<in K, Int>
                // and updates its counts in place.
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let eachCountToKeyType: TypeID
                if case let .classType(ct) = sema.types.kind(of: receiverType),
                   ct.args.count >= 2,
                   case let .invariant(k) = ct.args[1] {
                    eachCountToKeyType = k
                } else {
                    eachCountToKeyType = sema.types.anyType
                }
                let destinationExpectedType: TypeID? = if let mutableMapSymbol = lookupStdlibSymbol("MutableMap", symbols: sema.symbols, interner: interner) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: mutableMapSymbol,
                        args: [.in(eachCountToKeyType), .invariant(sema.types.intType)],
                        nullability: .nonNull
                    )))
                } else {
                    nil
                }
                let destinationType = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: destinationExpectedType
                )
                resultType = destinationType

            case "sortedBy", "sortedByDescending":
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = receiverType

            case "sort":
                resultType = sema.types.unitType

            case "sortBy", "sortByDescending":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.unitType)
                    return sema.types.unitType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.unitType

            case "sortedWith":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    // Lambda argument: infer as (T, T) -> Int comparator function
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: sema.types.intType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                } else {
                    // Non-lambda argument (e.g. compareBy { ... }, reverseOrder(), etc.)
                    // Pass Comparator<T> expected type so factory functions can infer element type.
                    let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                    let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: comparatorSymbol,
                            args: [.invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        nil
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                }
                resultType = receiverType

            case "maxWith", "minWith", "maxWithOrNull", "minWithOrNull":
                guard args.count == 1 else {
                    let failedType = (calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull")
                        ? sema.types.makeNullable(sema.types.errorType)
                        : sema.types.errorType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    let comparatorLambdaType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: sema.types.intType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorLambdaType)
                } else {
                    let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                    let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: comparatorSymbol,
                            args: [.invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        nil
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                }
                resultType = (calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull")
                    ? sema.types.makeNullable(collectionElementType)
                    : collectionElementType

            case "maxOfWith", "minOfWith", "maxOfWithOrNull", "minOfWithOrNull":
                guard args.count == 2 else {
                    let failedType = (calleeStr == "maxOfWithOrNull" || calleeStr == "minOfWithOrNull")
                        ? sema.types.makeNullable(sema.types.errorType)
                        : sema.types.errorType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
                let selectorResultType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[1].expr) {
                    sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                } else if let lambdaExprType = sema.bindings.exprType(for: args[1].expr),
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType) {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    let comparatorLambdaType = sema.types.make(.functionType(FunctionType(
                        params: [selectorResultType, selectorResultType],
                        returnType: sema.types.intType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorLambdaType)
                } else {
                    let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                    let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: comparatorSymbol,
                            args: [.invariant(selectorResultType)],
                            nullability: .nonNull
                        )))
                    } else {
                        nil
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                }
                resultType = (calleeStr == "maxOfWithOrNull" || calleeStr == "minOfWithOrNull")
                    ? sema.types.makeNullable(selectorResultType)
                    : selectorResultType

            case "partition":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.booleanType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                // Pair<List<T>, List<T>>
                if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first,
                   let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                {
                    let listType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.invariant(listType), .invariant(listType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "flatten":
                // Sequence<Iterable<T>> / List<List<T>> etc.: one-level flatten → element type T
                guard args.isEmpty else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let extractedInner = getCollectionElementType(collectionElementType, sema: sema, interner: interner)
                let flattenedElementType = extractedInner != sema.types.anyType
                    ? extractedInner
                    : collectionElementType
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: flattenedElementType
                    )
                } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(flattenedElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "zipWithNext":
                if args.isEmpty {
                    guard explicitTypeArgs.isEmpty else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    // zipWithNext(): List<Pair<T, T>>
                    if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first,
                       let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                    {
                        let pairType = sema.types.make(.classType(ClassType(
                            classSymbol: pairSymbol,
                            args: [.invariant(collectionElementType), .invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(pairType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                } else {
                    // zipWithNext(transform: (T, T) -> R): List<R>
                    guard args.count == 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    guard explicitTypeArgs.count <= 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    let lambdaReturnType = explicitTypeArgs.first ?? sema.types.anyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: lambdaReturnType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let bodyType = explicitTypeArgs.first
                        ?? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                    if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(bodyType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                }

            case "indexOfFirst", "indexOfLast":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.booleanType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.intType

            case "forEachIndexed", "mapIndexed", "onEachIndexed":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaReturnType = calleeStr == "forEachIndexed" || calleeStr == "onEachIndexed"
                    ? sema.types.unitType
                    : sema.types.anyType
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType],
                    returnType: lambdaReturnType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if calleeStr == "forEachIndexed" {
                    resultType = sema.types.unitType
                } else if calleeStr == "onEachIndexed" {
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                    } else {
                        resultType = receiverType
                    }
                } else if isSequenceReceiver {
                    let bodyType = inferredLambdaReturnType(
                        argExpr: args[0].expr, ast: ast, sema: sema
                    )
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: bodyType
                    )
                } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                    let bodyType = inferredLambdaReturnType(
                        argExpr: args[0].expr, ast: ast, sema: sema
                    )
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(bodyType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "sumOf", "sumBy":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.intType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.intType

            case "maxOrNull", "minOrNull":
                guard args.isEmpty else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                    let comparableElementType = sema.types.make(.classType(ClassType(
                        classSymbol: comparableSymbol,
                        args: [.in(collectionElementType)],
                        nullability: .nonNull
                    )))
                    if !sema.types.isSubtype(collectionElementType, comparableElementType) {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: ast.arena.exprRange(id)
                        )
                        let failedType = safeCall ? sema.types.nullableAnyType : sema.types.anyType
                        sema.bindings.bindExprType(id, type: failedType)
                        return failedType
                    }
                }
                resultType = sema.types.makeNullable(collectionElementType)

            case "maxByOrNull", "minByOrNull":
                guard args.count == 1 else {
                    let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let selectorType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
                {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }
                do {
                    let primitiveComparableTypes: Set<TypeID> = [
                        sema.types.intType,
                        sema.types.longType,
                        sema.types.floatType,
                        sema.types.doubleType,
                        sema.types.charType,
                        sema.types.stringType,
                        sema.types.make(.primitive(.uint, .nonNull)),
                        sema.types.make(.primitive(.ulong, .nonNull)),
                    ]
                    let isPrimitiveComparable = primitiveComparableTypes.contains(selectorType)
                    let isNominalComparable: Bool
                    if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                        let comparableSelectorType = sema.types.make(.classType(ClassType(
                            classSymbol: comparableSymbol,
                            args: [.in(selectorType)],
                            nullability: .nonNull
                        )))
                        isNominalComparable = sema.types.isSubtype(selectorType, comparableSelectorType)
                    } else {
                        isNominalComparable = false
                    }
                    if selectorType != sema.types.anyType && !isPrimitiveComparable && !isNominalComparable {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: ast.arena.exprRange(id)
                        )
                        let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                        sema.bindings.bindExprType(id, type: failedType)
                        return failedType
                    }
                }
                resultType = sema.types.makeNullable(collectionElementType)

            case "maxOf", "minOf":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType) {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }

            case "maxOfOrNull", "minOfOrNull":
                guard args.count == 1 else {
                    let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let selectorType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
                {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }
                let selectorKind = sema.types.kind(of: selectorType)
                if case .typeParam = selectorKind {} else {
                    do {
                        let primitiveComparableTypes: Set<TypeID> = [
                            sema.types.intType,
                            sema.types.longType,
                            sema.types.floatType,
                            sema.types.doubleType,
                            sema.types.charType,
                            sema.types.stringType,
                            sema.types.make(.primitive(.uint, .nonNull)),
                            sema.types.make(.primitive(.ulong, .nonNull)),
                        ]
                        let isPrimitiveComparable = primitiveComparableTypes.contains(selectorType)
                        let isNominalComparable: Bool
                        if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                            let comparableSelectorType = sema.types.make(.classType(ClassType(
                                classSymbol: comparableSymbol,
                                args: [.in(selectorType)],
                                nullability: .nonNull
                            )))
                            isNominalComparable = sema.types.isSubtype(selectorType, comparableSelectorType)
                        } else {
                            isNominalComparable = false
                        }
                        if selectorType != sema.types.anyType && !isPrimitiveComparable && !isNominalComparable {
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-BOUND",
                                "Type argument does not satisfy upper bound constraint.",
                                range: ast.arena.exprRange(id)
                            )
                            let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                            sema.bindings.bindExprType(id, type: failedType)
                            return failedType
                        }
                    }
                 }
                 resultType = sema.types.makeNullable(selectorType)
            case "binarySearch":
                // STDLIB-547: binarySearch(comparison: (T) -> Int) overload.
                // STDLIB-COL-BSEARCH-002: binarySearch(element, comparator, fromIndex, toIndex).
                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    nil
                }
                if args.count == 1 {
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.intType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    } else {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                    }
                    resultType = sema.types.intType
                } else if (2...4).contains(args.count) {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                    if let comparatorLambdaExpr = ast.arena.expr(args[1].expr),
                       comparatorLambdaExpr.isLambdaOrCallableRef
                    {
                        let comparatorLambdaType = sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType, collectionElementType],
                            returnType: sema.types.intType
                        )))
                        sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: comparatorLambdaType)
                    } else {
                        _ = driver.inferExpr(
                            args[1].expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: comparatorExpectedType
                        )
                    }
                    if args.count >= 3 {
                        _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                    }
                    if args.count >= 4 {
                        _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                    }
                    resultType = sema.types.intType
                } else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }

            case "binarySearchBy":
                guard (2...4).contains(args.count) else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
                let keyType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                if args.count >= 3 {
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                if args.count == 4 {
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                let selectorReturnType: TypeID = if keyType == sema.types.errorType {
                    sema.types.nullableAnyType
                } else {
                    switch sema.types.kind(of: keyType) {
                    case .nothing:
                        sema.types.nullableAnyType
                    default:
                        sema.types.makeNullable(keyType)
                    }
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: selectorReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[args.count - 1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[args.count - 1].expr)
                }
                _ = driver.inferExpr(args[args.count - 1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.intType

                let knownNames = KnownCompilerNames(interner: interner)
                let memberFQName = knownNames.kotlinCollectionsListFQName + [calleeName]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                    return signature.parameterTypes.count == args.count
                }) {
                    let keySubstitution: TypeID = if keyType == sema.types.errorType {
                        sema.types.nullableAnyType
                    } else {
                        switch sema.types.kind(of: keyType) {
                        case .nothing:
                            sema.types.nullableAnyType
                        default:
                            keyType
                        }
                    }
                    let substitutedTypeArguments = [collectionElementType, keySubstitution]
                    let parameterMapping = Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: substitutedTypeArguments,
                        parameterMapping: parameterMapping
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }

            case "distinctBy":
                 guard args.count == 1 else {
                     sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                // Match the synthetic stub: selector is (T) -> Any (non-null, non-suspend).
                // KNOWN LIMITATION: nullable keys are not supported; see stub comment.
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = receiverType

            default:
                resultType = sema.types.anyType
            }

            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            if isSyntheticSequenceReceiver,
               ["map", "filter", "flatMap", "flatMapIndexed", "flatten", "sortedBy", "sortedByDescending", "takeWhile", "dropWhile", "onEach", "onEachIndexed", "distinctBy"].contains(calleeStr)
            {
                sema.bindings.markCollectionExpr(id)
            }
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if isFlowHOF,
           let lambdaArg = args.first?.expr,
           let lambdaExpr = ast.arena.expr(lambdaArg),
           lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(lambdaArg)
        }

        if isFlowReceiver,
           let builtinFlowType = tryBuiltinFlowMemberCall(
               id,
               calleeName: calleeName,
               receiverElementType: flowElementType,
               args: args,
               safeCall: safeCall,
               ast: ast,
               sema: sema,
               ctx: ctx,
               locals: &locals
           )
        {
            return builtinFlowType
        }

        // Early range HOF fallback: range forEach/map need lambda inference with
        // expectedType so the implicit `it` parameter gets bound correctly.
        // Must run before argument pre-inference below to avoid resolving
        // lambdas without the expected function type.
        if sema.bindings.isRangeExpr(receiverID),
           !args.isEmpty
        {
            if let fallbackType = tryRangeMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: false,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
        }

        let stringHOFReceiverType = safeCall
            ? sema.types.makeNonNullable(receiverType)
            : receiverType
        if let boundType = tryBindStringChunkedSequenceTransform(
            id,
            calleeName: calleeName,
            receiverType: stringHOFReceiverType,
            args: args,
            safeCall: safeCall,
            ast: ast,
            ctx: ctx,
            locals: &locals,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return boundType
        }
        if let boundType = tryBindStringWindowedSequenceTransform(
            id,
            calleeName: calleeName,
            receiverType: stringHOFReceiverType,
            args: args,
            safeCall: safeCall,
            ast: ast,
            ctx: ctx,
            locals: &locals,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return boundType
        }

        // Early String HOF fallback: String HOF members need lambda inference with
        // expected types so the implicit `it` parameter (Char) gets bound correctly.
        // lambda inference with expectedType so the implicit `it` parameter (Char)
        // gets bound correctly.  Must run before argument pre-inference below.
        if args.count == 1 {
            let stringHOFCalleeStr = interner.resolve(calleeName)
            let isStringHOFReceiver = sema.types.isSubtype(stringHOFReceiverType, sema.types.stringType)
                || ((stringHOFCalleeStr == "ifBlank" || stringHOFCalleeStr == "ifEmpty" || stringHOFCalleeStr == "zipWithNext" || stringHOFCalleeStr == "sumBy" || stringHOFCalleeStr == "sumByDouble")
                    && isSyntheticStringLikeType(stringHOFReceiverType, sema: sema))
            if isStringHOFReceiver,
               [
                   "filter", "map", "count", "any", "all", "none",
                   "indexOfFirst", "indexOfLast",
                   "mapIndexed", "mapNotNull", "filterIndexed", "filterNot",
                   "takeWhile", "dropWhile", "find", "findLast", "splitToSequence",
                   "trim", "trimStart", "trimEnd",
                   "zipWithNext",
                   "partition",
                   "ifBlank",
                   "ifEmpty",
                   "sumBy",
                   "sumByDouble",
               ].contains(stringHOFCalleeStr)
            {
                let charType = sema.types.make(.primitive(.char, .nonNull))
                let intType = sema.types.intType
                if stringHOFCalleeStr != "splitToSequence" && stringHOFCalleeStr != "zipWithNext" {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    let lambdaExpectedType: TypeID = switch stringHOFCalleeStr {
                    case "mapIndexed":
                        sema.types.make(.functionType(FunctionType(
                            params: [intType, charType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "filterIndexed":
                        sema.types.make(.functionType(FunctionType(
                            params: [intType, charType],
                            returnType: sema.types.booleanType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "mapNotNull":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.nullableAnyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "zipWithNext":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType, charType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "ifBlank", "ifEmpty":
                        sema.types.make(.functionType(FunctionType(
                            params: [],
                            returnType: sema.types.stringType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "sumBy":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.intType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "sumByDouble":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.doubleType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "map":
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    default:
                        sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: sema.types.booleanType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                }
                let resolvedArgTypes = args.map { arg in
                    sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                }
                if stringHOFCalleeStr == "zipWithNext" {
                    // Re-run inference with the transform overload so the result type
                    // comes from the lambda body rather than the placeholder `Any`.
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    guard explicitTypeArgs.count <= 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    let lambdaReturnType = explicitTypeArgs.first ?? sema.types.anyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [charType, charType],
                        returnType: lambdaReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let bodyType = explicitTypeArgs.first
                        ?? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                    if let chosen = sema.symbols.lookupAll(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        calleeName,
                    ]).first(where: { candidate in
                        isSyntheticStringMemberCandidate(
                            candidate,
                            named: calleeName,
                            receiverType: stringHOFReceiverType,
                            sema: sema,
                            interner: interner
                        )
                            && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [bodyType],
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    let resultType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: bodyType
                    )
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                if stringHOFCalleeStr == "splitToSequence" || stringHOFCalleeStr == "partition" {
                    bindSyntheticStringMemberDirectlyIfAvailable(
                        id,
                        calleeName: calleeName,
                        argumentCount: args.count,
                        receiverType: stringHOFReceiverType,
                        sema: sema,
                        interner: interner
                    )
                } else if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: stringHOFReceiverType,
                    args: args,
                    argTypes: resolvedArgTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                bindSyntheticStringMemberDirectlyIfAvailable(
                    id,
                    calleeName: calleeName,
                    argumentCount: args.count,
                    receiverType: stringHOFReceiverType,
                    sema: sema,
                    interner: interner
                )
                let sequenceStringType: TypeID = {
                    let knownNames = KnownCompilerNames(interner: interner)
                    guard let sequenceSymbol = sema.symbols.lookupAll(fqName: knownNames.kotlinSequenceFQName).first else {
                        return sema.types.anyType
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: sequenceSymbol,
                        args: [.out(sema.types.stringType)],
                        nullability: .nonNull
                    )))
                }()
                let pairStringStringTypeEarly: TypeID = {
                    let pairFQName: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("Pair"),
                    ]
                    guard let pairSymbol = sema.symbols.lookup(fqName: pairFQName) else {
                        return sema.types.anyType
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.out(sema.types.stringType), .out(sema.types.stringType)],
                        nullability: .nonNull
                    )))
                }()
                let resultType: TypeID = switch stringHOFCalleeStr {
                case "filter": sema.types.stringType
                case "map": sema.types.anyType  // Kotlin String.map returns List<R>
                case "mapIndexed", "mapNotNull": sema.types.anyType
                case "count": sema.types.intType
                case "indexOfFirst", "indexOfLast": sema.types.intType
                case "any", "all", "none": sema.types.booleanType
                case "filterIndexed", "filterNot", "takeWhile", "dropWhile",
                     "trim", "trimStart", "trimEnd": sema.types.stringType
                case "find", "findLast": sema.types.make(.primitive(.char, .nullable))
                case "splitToSequence": sequenceStringType
                case "partition": pairStringStringTypeEarly
                case "ifBlank", "ifEmpty": sema.types.stringType
                case "sumBy": sema.types.intType
                case "sumByDouble": sema.types.doubleType
                default: sema.types.anyType
                }
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        if let durationComponentsType = tryDurationToComponentsMemberCall(
            id,
            calleeName: calleeName,
            receiverType: receiverType,
            args: args,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: expectedType,
            safeCall: safeCall,
            ast: ast,
            sema: sema,
            ctx: ctx,
            locals: &locals
        ) {
            return durationComponentsType
        }

        // Comparator member HOFs (STDLIB-176): thenBy/thenByDescending/thenDescending/thenComparator.
        // These need the Comparator<T> receiver type so the lambda gets the correct
        // contextual function signature before the general resolution path runs.
        if args.count == 2,
           ["thenBy", "thenByDescending"].contains(interner.resolve(calleeName)),
           let comparatorElementType = resolvedComparatorElementType(
               of: receiverType,
               sema: sema,
               interner: interner
            )
        {
            let keyComparatorType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            if let keyType = resolvedComparatorElementType(of: keyComparatorType, sema: sema, interner: interner) {
                if let lambdaExpr = ast.arena.expr(args[1].expr),
                   lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [comparatorElementType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            }
        }
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if let comparatorElementType = resolvedComparatorElementType(
                of: receiverType,
                sema: sema,
                interner: interner
            ) {
                if let lambdaExpr = ast.arena.expr(args[0].expr),
                   lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                switch calleeStr {
                case "thenBy", "thenByDescending":
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [comparatorElementType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                case "thenComparator", "thenDescending":
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [comparatorElementType, comparatorElementType],
                        returnType: sema.types.intType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                default:
                    break
                }
            }
        }

        // Infer argument types for the normal resolution path (scope functions,
        // collection HOFs, and comparator HOFs infer their lambda args with
        // expected type above and return).
        // Skip lambda literals and callable refs so that their first inference
        // happens inside prepareCallArguments with a contextual expected type,
        // preventing a stale no-expectedType binding from poisoning the cache.
        let argTypes = args.enumerated().map { _, arg -> TypeID in
            if let expr = ast.arena.expr(arg.expr) {
                switch expr {
                case .lambdaLiteral, .callableRef:
                    return sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                default:
                    break
                }
            }
            return sema.bindings.exprType(for: arg.expr) ?? driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }

        let hasLeadingLocaleArgument = calleeName == interner.intern("format")
            && argTypes.first.map { isJavaUtilLocaleType($0, sema: sema, interner: interner) } == true
        let lookupReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType
        // Primitive member function: Int/Long/UInt/ULong.inv() → same type (P5-103, TYPE-005)
        if interner.resolve(calleeName) == "inv",
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            if lookupReceiverType == intType || lookupReceiverType == longType || lookupReceiverType == uintType || lookupReceiverType == ulongType || lookupReceiverType == ubyteType || lookupReceiverType == ushortType {
                let resultType = lookupReceiverType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Primitive arithmetic/infix member functions on numeric receivers
        // (e.g. Int.times(Int), Long.plus(Long), UInt.shl(Int)).
        if args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let charType = sema.types.charType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let rawRhsType = argTypes[0]
            let isPrimitiveReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType
            let isShiftReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType
            // Helper: whether a type is a small unsigned type (UByte/UShort).
            // In Kotlin stdlib, small unsigned types promote to UInt for most
            // arithmetic (plus/minus/times/div/rem).  `mod` keeps the operand type.
            let isSmallUnsigned = { (t: TypeID) -> Bool in t == ubyteType || t == ushortType }
            let isUnsignedInteger = { (t: TypeID) -> Bool in
                t == uintType || t == ulongType || t == ubyteType || t == ushortType
            }
            let isSignedInteger = { (t: TypeID) -> Bool in t == intType || t == longType }
            // Use non-nullable RHS for arithmetic promotion checks
            let rhsType = sema.types.makeNonNullable(rawRhsType)
            switch interner.resolve(calleeName) {
            case "plus":
                let resultType: TypeID?
                if receiverForCheck == charType && rawRhsType == intType {
                    resultType = charType
                } else if receiverForCheck == doubleType || rhsType == doubleType {
                    resultType = doubleType
                } else if receiverForCheck == floatType || rhsType == floatType {
                    resultType = floatType
                } else if receiverForCheck == longType || rhsType == longType {
                    resultType = longType
                } else if receiverForCheck == ulongType || rhsType == ulongType {
                    resultType = ulongType
                } else if receiverForCheck == uintType || rhsType == uintType || isSmallUnsigned(receiverForCheck) || isSmallUnsigned(rhsType) {
                    // UByte/UShort arithmetic promotes to UInt in Kotlin stdlib
                    resultType = uintType
                } else if receiverForCheck == intType || rhsType == intType || receiverForCheck == charType {
                    resultType = intType
                } else {
                    resultType = nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "minus":
                let resultType: TypeID?
                if receiverForCheck == charType && rawRhsType == charType {
                    resultType = intType
                } else if receiverForCheck == charType && rawRhsType == intType {
                    resultType = charType
                } else if receiverForCheck == doubleType || rhsType == doubleType {
                    resultType = doubleType
                } else if receiverForCheck == floatType || rhsType == floatType {
                    resultType = floatType
                } else if receiverForCheck == longType || rhsType == longType {
                    resultType = longType
                } else if receiverForCheck == ulongType || rhsType == ulongType {
                    resultType = ulongType
                } else if receiverForCheck == uintType || rhsType == uintType || isSmallUnsigned(receiverForCheck) || isSmallUnsigned(rhsType) {
                    resultType = uintType
                } else if receiverForCheck == intType {
                    resultType = intType
                } else {
                    resultType = nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "times", "div", "rem":
                // times/div/rem: small unsigned types promote to UInt (Kotlin stdlib)
                let resultType: TypeID?
                if receiverForCheck == doubleType || rhsType == doubleType {
                    resultType = doubleType
                } else if receiverForCheck == floatType || rhsType == floatType {
                    resultType = floatType
                } else if receiverForCheck == longType || rhsType == longType {
                    resultType = longType
                } else if receiverForCheck == ulongType || rhsType == ulongType {
                    resultType = ulongType
                } else if receiverForCheck == uintType || rhsType == uintType || isSmallUnsigned(receiverForCheck) || isSmallUnsigned(rhsType) {
                    resultType = uintType
                } else if receiverForCheck == intType {
                    resultType = intType
                } else {
                    resultType = nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "floorDiv":
                let resultType: TypeID?
                if isSignedInteger(receiverForCheck), isSignedInteger(rhsType) {
                    resultType = receiverForCheck == longType || rhsType == longType ? longType : intType
                } else if isUnsignedInteger(receiverForCheck), isUnsignedInteger(rhsType) {
                    resultType = receiverForCheck == ulongType || rhsType == ulongType ? ulongType : uintType
                } else {
                    resultType = nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "mod":
                // mod: keeps the operand type for small unsigned (UByte.mod(UByte) -> UByte)
                let resultType: TypeID?
                if receiverForCheck == doubleType || rhsType == doubleType {
                    resultType = doubleType
                } else if receiverForCheck == floatType || rhsType == floatType {
                    resultType = floatType
                } else if receiverForCheck == longType || rhsType == longType {
                    resultType = longType
                } else if receiverForCheck == ulongType || rhsType == ulongType {
                    resultType = ulongType
                } else if receiverForCheck == uintType || rhsType == uintType {
                    resultType = uintType
                } else if isSmallUnsigned(receiverForCheck) && isSmallUnsigned(rhsType) {
                    // mod keeps the receiver type for same-width small unsigned
                    resultType = receiverForCheck
                } else if isSmallUnsigned(receiverForCheck) || isSmallUnsigned(rhsType) {
                    resultType = uintType
                } else if receiverForCheck == intType {
                    resultType = intType
                } else {
                    resultType = nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "and", "or", "xor":
                if isPrimitiveReceiver,
                   rawRhsType == receiverForCheck
                {
                    let resultType = receiverForCheck
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "shl", "shr", "ushr":
                if isShiftReceiver,
                   rawRhsType == intType
                {
                    // shift amount must be Int; receiver can be Int/Long/UInt/ULong
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            default:
                break
            }
        }

        // Stdlib infix function: Any.to(Any) → Pair<LHS, RHS> (FUNC-002)
        if calleeName == knownNames.to,
           args.count == 1
        {
            let rhsType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let resultType = makeSyntheticPairType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                firstType: receiverType,
                secondType: rhsType
            )
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // STDLIB-NUM-130 (previous fast-path) removed:
        // isNaN / isInfinite / isFinite / toBits / toRawBits / ulp / nextUp / nextDown
        // are registered as real extension functions with external link names
        // (kk_{double,float}_*) in HeaderHelpers+SyntheticCoercionStubs.swift. Letting
        // them flow through the normal extension-function resolution path carries the
        // link name into codegen; the old early-return bound only the result type, so
        // the linker saw raw "_isNaN"/"_nextUp" symbols.

        // Int/Long/Byte/Short/UByte/UShort/UInt/ULong.coerceIn(min, max) (STDLIB-150, STDLIB-500)
        if interner.resolve(calleeName) == "coerceIn", args.count == 2 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let ubyteType = sema.types.ubyteType
            let ushortType = sema.types.ushortType
            let uintType = sema.types.uintType
            let ulongType = sema.types.ulongType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType
                || receiverForCheck == doubleType || receiverForCheck == floatType
                || receiverForCheck == ubyteType || receiverForCheck == ushortType
                || receiverForCheck == uintType || receiverForCheck == ulongType {
                _ = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals, expectedType: receiverForCheck) }
                let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Int/Long/UInt/ULong.coerceIn(range) (STDLIB-525)
        if interner.resolve(calleeName) == "coerceIn", args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.uintType
            let ulongType = sema.types.ulongType
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let supportsRangeCoercion = receiverForCheck == intType || receiverForCheck == longType
                || receiverForCheck == uintType || receiverForCheck == ulongType
            if supportsRangeCoercion {
                let inferredArgType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let nominalRangeElementType = nominalRangeElementType(
                    for: inferredArgType,
                    sema: sema,
                    interner: interner
                )
                let isRangeArg = sema.bindings.isRangeExpr(args[0].expr)
                if isRangeArg || nominalRangeElementType == receiverForCheck {
                    if isRangeArg {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: receiverForCheck)
                    }
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Int/Long/Byte/Short/UByte/UShort/UInt/ULong.coerceAtLeast(min) / coerceAtMost(max) (STDLIB-150, STDLIB-500)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "coerceAtLeast" || calleeStr == "coerceAtMost" {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                let longType = sema.types.make(.primitive(.long, .nonNull))
                let doubleType = sema.types.make(.primitive(.double, .nonNull))
                let floatType = sema.types.make(.primitive(.float, .nonNull))
                let ubyteType = sema.types.ubyteType
                let ushortType = sema.types.ushortType
                let uintType = sema.types.uintType
                let ulongType = sema.types.ulongType
                let receiverForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let isRangeArg = sema.bindings.isRangeExpr(args[0].expr)
                let supportsRangeCoercion = receiverForCheck == intType || receiverForCheck == longType
                    || receiverForCheck == doubleType || receiverForCheck == floatType
                let supportsValueCoercion = supportsRangeCoercion
                    || receiverForCheck == ubyteType || receiverForCheck == ushortType
                    || receiverForCheck == uintType || receiverForCheck == ulongType
                if (!isRangeArg && supportsValueCoercion) || (isRangeArg && supportsRangeCoercion) {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: receiverForCheck)
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Int.countOneBits() / countLeadingZeroBits() / countTrailingZeroBits() → Int (STDLIB-501)
        // STDLIB-BIT-007: Additional bit manipulation functions
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "countOneBits" || calleeStr == "countLeadingZeroBits" || calleeStr == "countTrailingZeroBits" ||
               calleeStr == "highestOneBit" || calleeStr == "lowestOneBit" || calleeStr == "takeHighestOneBit" || calleeStr == "takeLowestOneBit" {
                let intType = sema.types.intType
                let longType = sema.types.longType
                let receiverForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverForCheck == intType || receiverForCheck == longType {
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Int.rotateLeft() / rotateRight() → Int (STDLIB-BIT-007)
        // Long.rotateLeft() / rotateRight() → Long (STDLIB-BIT-007)
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "rotateLeft" || calleeStr == "rotateRight" {
                let intType = sema.types.intType
                let longType = sema.types.longType
                let receiverForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverForCheck == intType || receiverForCheck == longType {
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Primitive member function: Int/Long.toString() / toString(radix: Int) → String (EXPR-003)
        if interner.resolve(calleeName) == "toString",
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let stringType = sema.types.make(.primitive(.string, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType {
                if args.isEmpty || argTypes[0] == intType {
                    let finalType = safeCall ? sema.types.makeNullable(stringType) : stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // STDLIB-NUM-130: Double/Float extension functions - Direct resolution (moved earlier, removed duplicate)

        let anyFallbackReceiverType = safeCall
            ? sema.types.makeNonNullable(lookupReceiverType)
            : lookupReceiverType
        let allowsAnyFallback: Bool = switch sema.types.kind(of: anyFallbackReceiverType) {
        case .primitive(.string, _):
            false
        case .primitive:
            true
        case .typeParam:
            // All type parameters have an implicit upper bound of Any? in Kotlin,
            // so Any methods (toString, hashCode, equals) are always available on
            // type parameter receivers (STDLIB-GEN-055).
            true
        default:
            anyFallbackReceiverType == sema.types.anyType || anyFallbackReceiverType == sema.types.nullableAnyType
        }

        // Any.hashCode(): Int (STDLIB-306)
        if interner.resolve(calleeName) == "hashCode", args.isEmpty, allowsAnyFallback {
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Any.toString(): String (STDLIB-306)
        if interner.resolve(calleeName) == "toString", args.isEmpty, allowsAnyFallback {
            let stringType = sema.types.make(.primitive(.string, .nonNull))
            let finalType = safeCall ? sema.types.makeNullable(stringType) : stringType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Any.equals(other: Any?): Boolean (STDLIB-306)
        if interner.resolve(calleeName) == "equals", args.count == 1, allowsAnyFallback {
            let finalType = safeCall ? sema.types.makeNullable(sema.types.booleanType) : sema.types.booleanType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toDouble(), toByte(), toShort() (TYPE-005, STDLIB-151)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.ubyteType
            let ushortType = sema.types.ushortType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = interner.resolve(calleeName)
            let (targetType, matches): (TypeID, Bool) = switch calleeStr {
            case "toInt": (intType, receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == sema.types.charType)
            case "toUInt": (uintType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == sema.types.charType)
            case "toLong": (longType, receiverForCheck == intType || receiverForCheck == uintType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == longType || receiverForCheck == ulongType || receiverForCheck == floatType || receiverForCheck == doubleType || receiverForCheck == sema.types.charType)
            case "toULong": (ulongType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == ubyteType || receiverForCheck == ushortType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == sema.types.charType)
            case "toFloat": (floatType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == doubleType || receiverForCheck == floatType)
            case "toDouble": (doubleType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == floatType || receiverForCheck == doubleType)
            case "toByte", "toShort": (intType, receiverForCheck == intType || receiverForCheck == longType)
            case "toUByte": (sema.types.ubyteType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
            case "toUShort": (sema.types.ushortType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
            case "toChar": (sema.types.charType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == ubyteType || receiverForCheck == ushortType)
            default: (sema.types.errorType, false)
            }
            if matches {
                let finalType = safeCall ? sema.types.makeNullable(targetType) : targetType
                driver.helpers.checkBuiltinDeprecation(
                    calleeName: calleeName,
                    receiverType: receiverForCheck,
                    sema: sema,
                    interner: interner,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        var isSuperCall = false
        var supertypeSymbols: Set<SymbolID> = []
        var qualifiedSuperType: SymbolID? = nil
        if !safeCall {
            if let superExpr = ast.arena.expr(receiverID), case let .superRef(interfaceQualifier, _) = superExpr {
                isSuperCall = true
                if let currentReceiverType = ctx.implicitReceiverType,
                   let classSymbol = driver.helpers.nominalSymbol(of: currentReceiverType, types: sema.types) {
                    
                    // Handle qualified super: super<Interface>
                    if let qualifier = interfaceQualifier {
                        let qualifierStr = ctx.interner.resolve(qualifier)
                        let directSupertypes = sema.symbols.directSupertypes(for: classSymbol)
                        
                        // Find the specified interface in direct supertypes
                        for superID in directSupertypes {
                            guard let superSym = sema.symbols.symbol(superID) else { continue }
                            if superSym.kind == .interface && ctx.interner.resolve(superSym.name) == qualifierStr {
                                qualifiedSuperType = superID
                                supertypeSymbols.insert(superID)
                                break
                            }
                        }
                        
                        if qualifiedSuperType == nil {
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-0054",
                                "No type '\(qualifierStr)' found in direct supertypes for qualified 'super'.",
                                range: ast.arena.exprRange(receiverID)
                            )
                        }
                    } else {
                        // Handle unqualified super: search all supertypes
                        var queue = sema.symbols.directSupertypes(for: classSymbol)
                        var visited: Set<SymbolID> = [classSymbol]
                        while !queue.isEmpty {
                            let next = queue.removeFirst()
                            if visited.insert(next).inserted {
                                supertypeSymbols.insert(next)
                                queue.append(contentsOf: sema.symbols.directSupertypes(for: next))
                            }
                        }
                    }
                }
            }
        }

        let memberLookupType = (isSuperCall ? ctx.implicitReceiverType : nil) ?? lookupReceiverType

        // Detect class-name receiver: when the receiver is a name reference to
        // a class/interface/enumClass symbol, only companion members should be
        // accessible (not instance methods).  This prevents `Foo.instanceMethod()`
        // from resolving when there is no companion with that name.
        let classNameReceiverNominalSymbol: SymbolID? = {
            if let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverID),
               let receiverSymbol = sema.symbols.symbol(receiverSymbolID)
            {
                switch receiverSymbol.kind {
                case .class, .interface, .enumClass:
                    return receiverSymbolID
                default:
                    break
                }
            }
            if case let .nameRef(receiverName, _) = ast.arena.expr(receiverID) {
                return ctx.cachedScopeLookup(receiverName).first { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .interface, .enumClass:
                        return true
                    default:
                        return false
                    }
                }
            }
            return nil
        }()
        let isClassNameReceiver = classNameReceiverNominalSymbol != nil

        if isClassNameReceiver,
           args.isEmpty,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           )
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }

        if isClassNameReceiver,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let owner = sema.symbols.symbol(ownerSymbol)
        {
            let staticMethodFQName = owner.fqName + [calleeName]
            var staticMethodCandidates = sema.symbols.lookupAll(fqName: staticMethodFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.receiverType == nil
            }
            if staticMethodCandidates.isEmpty {
                staticMethodCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.receiverType == nil
                }
            }
            if !staticMethodCandidates.isEmpty {
                let (visibleStaticMethods, invisibleStaticMethods) = ctx.filterByVisibility(staticMethodCandidates)
                if let firstInvisible = invisibleStaticMethods.first {
                    driver.helpers.emitVisibilityError(
                        for: firstInvisible,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleStaticMethods.isEmpty {
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: callArgs,
                        explicitTypeArgs: explicitTypeArgs
                    )
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleStaticMethods,
                        call: call,
                        expectedType: expectedType,
                        ctx: sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
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
                        sema.bindings.bindIdentifier(id, symbol: chosen)
                        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }

            let nestedOwnerFQName = owner.fqName + [calleeName]
            var nestedOwnerSymbols = sema.symbols.lookupAll(fqName: nestedOwnerFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                    return false
                }
                switch symbol.kind {
                case .class, .enumClass, .object:
                    return true
                default:
                    return false
                }
            }
            if nestedOwnerSymbols.isEmpty {
                let shortNameNestedOwners = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .enumClass, .object:
                        return true
                    default:
                        return false
                    }
                }
                if shortNameNestedOwners.count == 1 {
                    nestedOwnerSymbols = shortNameNestedOwners
                }
            }
            let nestedCtorFQName = owner.fqName + [calleeName, interner.intern("<init>")]
            var nestedCtorCandidates = sema.symbols.lookupAll(fqName: nestedCtorFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                return symbol.kind == .constructor
            }
            if nestedCtorCandidates.isEmpty {
                if !nestedOwnerSymbols.isEmpty {
                    let initName = interner.intern("<init>")
                    nestedCtorCandidates = sema.symbols.lookupByShortName(initName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .constructor
                        else {
                            return false
                        }
                        guard let parent = sema.symbols.parentSymbol(for: candidate) else {
                            return false
                        }
                        return nestedOwnerSymbols.contains(parent)
                    }
                }
            }
            if !nestedCtorCandidates.isEmpty {
                let (visibleNested, invisibleNested) = ctx.filterByVisibility(nestedCtorCandidates)
                if let firstInvisible = invisibleNested.first {
                    driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleNested.isEmpty {
                    if args.isEmpty {
                        let zeroArgNested = visibleNested.first { candidate in
                            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                                return false
                            }
                            return signature.parameterTypes.isEmpty
                        }
                        if let zeroArgNested,
                           let signature = sema.symbols.functionSignature(for: zeroArgNested)
                        {
                            sema.bindings.bindCall(
                                id,
                                binding: CallBinding(
                                    chosenCallee: zeroArgNested,
                                    substitutedTypeArguments: [],
                                    parameterMapping: [:]
                                )
                            )
                            let resultType = signature.returnType
                            sema.bindings.bindExprType(id, type: resultType)
                            return resultType
                        }
                    }
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(range: range, calleeName: calleeName, args: callArgs, explicitTypeArgs: explicitTypeArgs)
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleNested,
                        call: call,
                        expectedType: expectedType,
                        ctx: sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
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
                        let resultType = signature.returnType
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }
            if args.isEmpty,
               let nestedOwner = nestedOwnerSymbols.first
            {
                let nestedType = sema.types.make(.classType(ClassType(
                    classSymbol: nestedOwner,
                    args: [],
                    nullability: .nonNull
                )))
                sema.bindings.bindIdentifier(id, symbol: nestedOwner)
                sema.bindings.bindExprType(id, type: nestedType)
                return nestedType
            }
        }

        if !isClassNameReceiver,
           args.isEmpty,
           let propResult = driver.helpers.lookupMemberProperty(
               named: calleeName,
               receiverType: memberLookupType,
               sema: sema
           )
        {
            if let propSymbol = sema.symbols.symbol(propResult.symbol),
               !ctx.visibilityChecker.isAccessible(
                   propSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: propSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
            let finalType = safeCall ? sema.types.makeNullable(propResult.type) : propResult.type
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           args.isEmpty,
           let extensionPropertyType = resolveExtensionPropertyGetter(
               id: id,
               calleeName: calleeName,
               range: range,
               receiverType: memberLookupType,
               expectedType: expectedType,
               ctx: ctx
           )
        {
            let finalType = safeCall ? sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Track the companion type so we can pass it (not the owner class type)
        // as the implicit receiver when resolving the call.
        var companionReceiverType: TypeID?

        let allCandidates: [SymbolID]
        if isClassNameReceiver {
            // Class-name receiver: only companion members are valid targets.
            // Skip collectMemberFunctionCandidates which would find instance
            // methods and shadow companion members of the same name.
            if let ownerNominal = classNameReceiverNominalSymbol,
               let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerNominal),
               let companionSym = sema.symbols.symbol(companionSymbol)
            {
                let companionMemberFQName = companionSym.fqName + [calleeName]

                // Try companion property access when no arguments are provided
                // (e.g. Foo.MAX_COUNT).  When args are present this is a function
                // call, so skip the property short-circuit to avoid shadowing a
                // companion function of the same name.
                if args.isEmpty {
                    let propertyCandidate = sema.symbols.lookupAll(fqName: companionMemberFQName).first(where: { cid in
                        guard let sym = sema.symbols.symbol(cid),
                              sym.kind == .property,
                              sema.symbols.parentSymbol(for: cid) == companionSymbol
                        else {
                            return false
                        }
                        return true
                    })
                    if let propSymbol = propertyCandidate,
                       let propType = sema.symbols.propertyType(for: propSymbol)
                    {
                        // Check visibility before returning the property.
                        if let propSym = sema.symbols.symbol(propSymbol),
                           !ctx.visibilityChecker.isAccessible(
                               propSym,
                               fromFile: ctx.currentFileID,
                               enclosingClass: ctx.enclosingClassSymbol
                           )
                        {
                            driver.helpers.emitVisibilityError(for: propSym, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                        }
                        driver.helpers.checkDeprecation(
                            for: propSymbol,
                            sema: sema,
                            interner: interner,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: propSymbol,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        // Re-bind receiver to companion type for correct KIR lowering
                        let compType = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                        sema.bindings.bindExprType(receiverID, type: compType)
                        sema.bindings.bindIdentifier(id, symbol: propSymbol)
                        sema.bindings.bindExprType(id, type: propType)
                        return propType
                    }
                }

                // Then try companion function candidates
                var companionCandidates: [SymbolID] = []
                for candidate in sema.symbols.lookupAll(fqName: companionMemberFQName) {
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == companionSymbol,
                          sema.symbols.functionSignature(for: candidate) != nil
                    else {
                        continue
                    }
                    companionCandidates.append(candidate)
                }
                if !companionCandidates.isEmpty {
                    companionReceiverType = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                    // Re-bind receiver expression to companion type so KIR
                    // lowering passes the companion singleton (not the owner
                    // class) as the first argument to the companion function.
                    sema.bindings.bindExprType(receiverID, type: companionReceiverType!)
                }
                allCandidates = companionCandidates
            } else {
                allCandidates = []
            }
        } else {
            // Normal instance receiver: use standard member lookup with
            // companion fallback via collectMemberFunctionCandidates.
            let allowedOwnerSymbols = isSuperCall && !supertypeSymbols.isEmpty ? 
                (qualifiedSuperType != nil ? [qualifiedSuperType!] : supertypeSymbols) : nil
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                allowedOwnerSymbols: allowedOwnerSymbols,
                interner: interner
            )
            if !memberCandidates.isEmpty {
                // Check if the found candidates belong to a companion object so we
                // can supply the correct implicit receiver type later.
                if let first = memberCandidates.first,
                   let parentSymbol = sema.symbols.parentSymbol(for: first),
                   let ownerNominal = driver.helpers.nominalSymbol(of: memberLookupType, types: sema.types),
                   parentSymbol != ownerNominal,
                   sema.symbols.companionObjectSymbol(for: ownerNominal) == parentSymbol
                {
                    companionReceiverType = sema.types.make(.classType(ClassType(classSymbol: parentSymbol, args: [], nullability: .nonNull)))
                }
                allCandidates = memberCandidates
            } else {
                // Try inner class constructor resolution: outer.Inner() → Inner's <init>
                let innerCtorCandidates = driver.helpers.collectInnerClassConstructorCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    interner: interner
                )
                if !innerCtorCandidates.isEmpty {
                    allCandidates = innerCtorCandidates
                } else {
                    let nonNullReceiverForScope = sema.types.makeNonNullable(memberLookupType)
                    var scopeCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                        guard let symbol = ctx.cachedSymbol(candidate),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                        guard let recv = signature.receiverType else { return false }
                        guard extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: nonNullReceiverForScope,
                            declaredReceiver: recv,
                            sema: sema
                        ) else { return false }
                        if isSuperCall, !supertypeSymbols.isEmpty {
                            return sema.symbols.parentSymbol(for: candidate).map { supertypeSymbols.contains($0) } ?? false
                        }
                        return true
                    }
                    // Extension functions are excluded from scope by the scope
                    // builder so they don't shadow top-level calls.  Fall back
                    // to a direct symbol-table lookup by short name to find
                    // synthetic extension functions (e.g. Double.pow, roundToInt).
                    if scopeCandidates.isEmpty {
                        let nonNullReceiver = sema.types.makeNonNullable(memberLookupType)
                        scopeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                            guard let symbol = sema.symbols.symbol(candidate),
                                  symbol.kind == .function,
                                  symbol.flags.contains(.synthetic),
                                  let signature = sema.symbols.functionSignature(for: candidate),
                                  let recvType = signature.receiverType
                            else { return false }
                            return extensionSyntheticFallbackReceiverMatches(
                                callSiteReceiver: nonNullReceiver,
                                declaredReceiver: recvType,
                                sema: sema
                            )
                        }
                    }
                    allCandidates = scopeCandidates
                }
            }
        }
        if allCandidates.isEmpty,
           let boundType = tryBindSyntheticBigIntegerMemberFallback(
               id,
               calleeName: calleeName,
               receiverType: memberLookupType,
               args: args,
               argTypes: argTypes,
               range: range,
               ctx: ctx,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs,
               safeCall: safeCall
           )
        {
            return boundType
        }
        let isNullLiteralReceiver = if case let .nameRef(name, _) = ast.arena.expr(receiverID) {
            name == KnownCompilerNames(interner: interner).null
        } else {
            false
        }

        let isChannelReceiver = isChannelReceiverType(
            lookupReceiverType,
            sema: sema,
            interner: interner
        )
        if !isClassNameReceiver, isChannelReceiver {
            let memberName = interner.resolve(calleeName)
            switch (memberName, args.count) {
            case ("send", 1), ("close", 0):
                let resultType = sema.types.unitType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            case ("receive", 0):
                let resultType = sema.types.nullableAnyType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            case ("isClosedForReceive", 0), ("isClosedForSend", 0):
                let resultType = sema.types.booleanType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            default:
                break
            }
        }

        // Prefer the concrete kotlin.text String.compareTo overloads over the
        // generic Comparable<T>.compareTo member, which otherwise leaves
        // String.compareTo(String) ambiguous after both surfaces are available.
        if !isClassNameReceiver,
           interner.resolve(calleeName) == "compareTo",
           args.count == 1 || args.count == 2
        {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let stringArgMatches = sema.types.isSubtype(arg0Type, sema.types.stringType)
            let boolArgMatches = args.count == 1
                || sema.types.isSubtype(sema.types.makeNonNullable(argTypes[1]), sema.types.booleanType)
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               stringArgMatches,
               boolArgMatches
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall
                    ? sema.types.makeNullable(sema.types.intType)
                    : sema.types.intType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        let (visible, invisible) = ctx.filterByVisibility(allCandidates)
        var candidates = visible
        if hasLeadingLocaleArgument {
            candidates.removeAll { candidate in
                isSyntheticStringFormatCandidate(candidate, sema: sema, interner: interner)
            }
        }
        if interner.resolve(calleeName) == "trimMargin" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                if !explicitTypeArgs.isEmpty {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                let trimMarginFQName = [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    calleeName,
                ]
                let chosen = sema.symbols.lookupAll(fqName: trimMarginFQName).first(where: { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType == sema.types.stringType
                    else {
                        return false
                    }
                    switch args.count {
                    case 0:
                        return signature.parameterTypes.isEmpty
                    case 1:
                        return signature.parameterTypes.count == 1
                            && sema.types.isSubtype(sema.types.makeNonNullable(argTypes[0]), signature.parameterTypes[0])
                    default:
                        return false
                    }
                })
                if let chosen {
                    let returnType = bindCallAndResolveReturnType(
                        id,
                        chosen: chosen,
                        resolved: ResolvedCall(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [:],
                            parameterMapping: args.isEmpty ? [:] : [0: 0],
                            diagnostic: nil
                        ),
                        sema: sema
                    )
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        if candidates.isEmpty {
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if args.isEmpty,
               interner.resolve(calleeName) == "length"
            {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let resultType = sema.types.intType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if args.isEmpty,
               interner.resolve(calleeName) == "code"
            {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverTypeForCheck == sema.types.charType {
                    let resultType = sema.types.intType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if args.isEmpty {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverTypeForCheck == sema.types.charType {
                    let calleeStr = interner.resolve(calleeName)
                    if let member = syntheticCharMemberSpec(named: calleeStr) {
                        let resultType = member.returnKind.typeID(
                            in: sema.types,
                            symbols: sema.symbols,
                            interner: interner
                        )
                        let kotlinTextFQName = [
                            interner.intern("kotlin"),
                            interner.intern("text"),
                            calleeName,
                        ]
                        if let chosen = sema.symbols.lookupAll(fqName: kotlinTextFQName).first(where: { symbolID in
                            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                                return false
                            }
                            return signature.receiverType == sema.types.charType
                                && signature.parameterTypes.isEmpty
                        }) {
                            _ = bindCallAndResolveReturnType(
                                id,
                                chosen: chosen,
                                resolved: ResolvedCall(
                                    chosenCallee: chosen,
                                    substitutedTypeArguments: [:],
                                    parameterMapping: [:],
                                    diagnostic: nil
                                ),
                                sema: sema
                            )
                        }
                        switch calleeStr {
                        case "toList", "toCharArray", "lines", "lineSequence", "toByteArray", "encodeToByteArray":
                            sema.bindings.markCollectionExpr(id)
                        default:
                            break
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // STDLIB-003-ABI-001: Char.digitToInt(radix: Int) — 1-arg overload
            if args.count == 1, interner.resolve(calleeName) == "digitToInt" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverTypeForCheck == sema.types.charType {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                    let intType = sema.types.intType
                    let finalType = safeCall ? sema.types.makeNullable(intType) : intType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // Boolean.not() / Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
            do {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.booleanType) {
                    let calleeStr = interner.resolve(calleeName)
                    if calleeStr == "not" && args.isEmpty {
                        let resultType = sema.types.booleanType
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    if (calleeStr == "and" || calleeStr == "or" || calleeStr == "xor") && args.count == 1 {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
                        let resultType = sema.types.booleanType
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // STDLIB-574 / STDLIB-TEXT-EDGE-006: ByteArray.decodeToString overloads.
            do {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let byteArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
                if let baSymbol = sema.symbols.lookup(fqName: byteArrayFQName),
                   case .classType(let ct) = sema.types.kind(of: receiverTypeForCheck),
                   ct.classSymbol == baSymbol
                {
                    let calleeStr = interner.resolve(calleeName)
                    if calleeStr == "decodeToString" && args.count <= 3 {
                        let resultType = sema.types.stringType
                        let charsetExpectedType: TypeID? = {
                            let charsetFQName: [InternedString] = [
                                interner.intern("kotlin"),
                                interner.intern("text"),
                                interner.intern("Charset"),
                            ]
                            guard let charsetSym = sema.symbols.lookup(fqName: charsetFQName) else { return nil }
                            return sema.types.make(.classType(ClassType(
                                classSymbol: charsetSym,
                                args: [],
                                nullability: .nonNull
                            )))
                        }()
                        func isCharsetType(_ type: TypeID) -> Bool {
                            guard let charsetExpectedType else { return false }
                            return sema.types.isSubtype(type, charsetExpectedType)
                        }
                        func receiverMatches(_ signature: FunctionSignature) -> Bool {
                            guard let receiverType = signature.receiverType else { return false }
                            return receiverType == receiverTypeForCheck
                                || sema.types.isSubtype(receiverTypeForCheck, receiverType)
                        }
                        func parameterShapeMatches(_ signature: FunctionSignature) -> Bool {
                            let params = signature.parameterTypes
                            guard receiverMatches(signature), params.count == args.count else { return false }
                            switch args.count {
                            case 0:
                                return true
                            case 1:
                                return params.first.map(isCharsetType) ?? false
                            case 2:
                                return params == [sema.types.intType, sema.types.intType]
                            case 3:
                                return params == [sema.types.intType, sema.types.intType, sema.types.booleanType]
                            default:
                                return false
                            }
                        }
                        // Try to bind to the synthetic extension function symbol.
                        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
                        let decodeToStringFQName = kotlinTextPkg + [interner.intern("decodeToString")]
                        let candidates = sema.symbols.lookupAll(fqName: decodeToStringFQName)
                        if let chosen = candidates.first(where: { candidate in
                            guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                            return parameterShapeMatches(sig)
                        }) {
                            _ = bindCallAndResolveReturnType(
                                id,
                                chosen: chosen,
                                resolved: ResolvedCall(
                                    chosenCallee: chosen,
                                    substitutedTypeArguments: [:],
                                    parameterMapping: [:],
                                    diagnostic: nil
                                ),
                                sema: sema
                            )
                        }
                        // Infer arguments with overload-specific expected types.
                        if args.count == 1 {
                            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: charsetExpectedType)
                        } else if args.count >= 2 {
                            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                            if args.count == 3 {
                                _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
                            }
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // STDLIB-HEX-001: HexFormat extension methods with default format parameter.
            do {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let calleeStr = interner.resolve(calleeName)
                let isSupportedHexReceiver =
                    (calleeStr == "toHexString" && (receiverTypeForCheck == sema.types.intType || receiverTypeForCheck == sema.types.longType))
                    || (calleeStr == "hexToInt" && receiverTypeForCheck == sema.types.stringType)
                if isSupportedHexReceiver, args.count <= 1 {
                    let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
                    let functionFQName = kotlinTextPkg + [calleeName]
                    let hexFormatFQName = kotlinTextPkg + [interner.intern("HexFormat")]
                    let hexFormatType: TypeID? = {
                        guard let hexFormatSymbol = sema.symbols.lookup(fqName: hexFormatFQName) else { return nil }
                        return sema.types.make(.classType(ClassType(classSymbol: hexFormatSymbol, args: [], nullability: .nonNull)))
                    }()
                    if let chosen = sema.symbols.lookupAll(fqName: functionFQName).first(where: { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate),
                              signature.receiverType == receiverTypeForCheck
                        else {
                            return false
                        }
                        guard args.count <= signature.parameterTypes.count else {
                            return false
                        }
                        if args.count < signature.parameterTypes.count {
                            let remainingDefaults = signature.valueParameterHasDefaultValues.dropFirst(args.count)
                            guard remainingDefaults.allSatisfy({ $0 }) else {
                                return false
                            }
                        }
                        if args.count == 1,
                           let expectedType = hexFormatType,
                           signature.parameterTypes.first != expectedType
                        {
                            return false
                        }
                        return true
                    }) {
                        if args.count == 1, let expectedType = hexFormatType {
                            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
                        }
                        driver.helpers.checkOptIn(
                            for: chosen,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        let returnType = bindCallAndResolveReturnType(
                            id,
                            chosen: chosen,
                            resolved: ResolvedCall(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [:],
                                parameterMapping: args.count == 1 ? [0: 0] : [:],
                                diagnostic: nil
                            ),
                            sema: sema
                        )
                        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: nullable-receiver 0-arg methods (NULL-002)
            // isNullOrEmpty/isNullOrBlank accept String? receiver directly (no safe-call needed).
            if args.isEmpty {
                let calleeStr = interner.resolve(calleeName)
                if !isNullLiteralReceiver,
                   calleeStr == "isNullOrEmpty" || calleeStr == "isNullOrBlank"
                {
                    // Strip nullability so that String? and String both match.
                    let baseType = sema.types.makeNonNullable(lookupReceiverType)
                    if sema.types.isSubtype(baseType, sema.types.stringType) {
                        let resultType = sema.types.booleanType
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }
            // String stdlib: 0-arg methods (STDLIB-006)
            let listCharType = makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.make(.primitive(.char, .nonNull))
            )
            let charArrayType = makeSyntheticNominalType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                fqName: [interner.intern("kotlin"), interner.intern("CharArray")]
            )
            if args.isEmpty {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "trim":
                        sema.types.stringType
                    case "trimIndent", "trimMargin":
                        sema.types.stringType
                    case "lowercase", "uppercase":
                        sema.types.stringType
                    case "toInt":
                        sema.types.intType
                    case "toIntOrNull":
                        sema.types.make(.primitive(.int, .nullable))
                    case "toDouble":
                        sema.types.make(.primitive(.double, .nonNull))
                    case "toDoubleOrNull":
                        sema.types.make(.primitive(.double, .nullable))
                    case "toBigDecimal":
                        makeSyntheticNominalType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            fqName: [interner.intern("java"), interner.intern("math"), interner.intern("BigDecimal")]
                        )
                    case "toBigInteger":
                        makeSyntheticNominalType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            fqName: [interner.intern("java"), interner.intern("math"), interner.intern("BigInteger")]
                        )
                    case "reversed", "trimStart", "trimEnd":
                        sema.types.stringType
                    case "prependIndent", "replaceIndent", "replaceIndentByMargin":
                        sema.types.stringType
                    case "toList":
                        listCharType
                    case "toCharArray":
                        charArrayType
                    case "toBoolean", "toBooleanStrict":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "toBooleanStrictOrNull":
                        sema.types.make(.primitive(.boolean, .nullable))
                    case "toShort", "toByte":
                        sema.types.intType
                    case "toShortOrNull", "toByteOrNull":
                        sema.types.make(.primitive(.int, .nullable))
                    case "isEmpty", "isNotEmpty", "isBlank", "isNotBlank":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "first", "last", "single":
                        sema.types.make(.primitive(.char, .nonNull))
                    case "firstOrNull", "lastOrNull", "singleOrNull":
                        sema.types.make(.primitive(.char, .nullable))
                    case "lines":
                        makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.stringType
                        )
                    case "lineSequence":
                        makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.stringType
                        )
                    case "asSequence":
                        makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.make(.primitive(.char, .nonNull))
                        )
                    case "toByteArray", "encodeToByteArray":
                        makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.intType
                        )
                    default:
                        nil
                    }
                    if let resultType {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // CharSequence stdlib: removePrefix / removeSuffix / removeSurrounding (STDLIB-185)
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                let calleeStr = interner.resolve(calleeName)
                if ["removePrefix", "removeSuffix", "removeSurrounding"].contains(calleeStr),
                   isSyntheticStringLikeType(receiverTypeForCheck, sema: sema),
                   isSyntheticStringLikeType(arg0Type, sema: sema)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: 1-arg methods (STDLIB-006)
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.stringType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "startsWith", "endsWith", "contains":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "split":
                        sema.types.anyType
                    case "indexOf", "lastIndexOf", "compareTo":
                        sema.types.make(.primitive(.int, .nonNull))
                    case "substringBefore", "substringAfter", "substringBeforeLast", "substringAfterLast":
                        sema.types.stringType
                    case "prependIndent", "replaceIndent", "replaceIndentByMargin":
                        sema.types.stringType
                    case "commonPrefixWith", "commonSuffixWith":
                        sema.types.stringType
                    default:
                        nil
                    }
                    if let resultType {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   isJavaUtilLocaleType(arg0Type, sema: sema, interner: interner)
                {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "lowercase", "uppercase":
                        sema.types.stringType
                    default:
                        nil
                    }
                    if let resultType {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "normalize":
                        sema.types.stringType
                    case "isNormalized":
                        sema.types.booleanType
                    default:
                        nil
                    }
                    if let resultType {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // STDLIB-581: String.toByteArray(charset: Charset)
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                // Only match when the argument is NOT a String or Int to avoid
                // shadowing other toByteArray overloads (e.g. toByteArray(Int)).
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   interner.resolve(calleeName) == "toByteArray",
                   !sema.types.isSubtype(arg0Type, sema.types.stringType),
                   !sema.types.isSubtype(arg0Type, sema.types.intType)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        sema.bindings.markCollectionExpr(id)
                        return boundType
                    }
                    let resultType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: sema.types.intType
                    )
                    sema.bindings.markCollectionExpr(id)
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // CharSequence stdlib: 2-arg removeSurrounding(prefix, suffix) (STDLIB-185)
            if args.count == 2 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                let arg1Type = sema.types.makeNonNullable(argTypes[1])
                if isSyntheticStringLikeType(receiverTypeForCheck, sema: sema),
                   isSyntheticStringLikeType(arg0Type, sema: sema),
                   isSyntheticStringLikeType(arg1Type, sema: sema),
                   interner.resolve(calleeName) == "removeSurrounding"
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: 2-arg commonPrefixWith/commonSuffixWith(other, ignoreCase) (STDLIB-575/576)
            if args.count == 2 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                let arg1Type = sema.types.makeNonNullable(argTypes[1])
                let boolType = sema.types.make(.primitive(.boolean, .nonNull))
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.stringType),
                   sema.types.isSubtype(arg1Type, boolType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    if calleeStr == "commonPrefixWith" || calleeStr == "commonSuffixWith" {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String.replaceIndentByMargin(newIndent, marginPrefix)
            if args.count == 2 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                let arg1Type = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.stringType),
                   sema.types.isSubtype(arg1Type, sema.types.stringType),
                   interner.resolve(calleeName) == "replaceIndentByMargin"
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if args.count == 2 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                let arg1Type = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.intType),
                   sema.types.isSubtype(arg1Type, sema.types.intType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    if calleeStr == "encodeToByteArray" || calleeStr == "toByteArray" {
                        let resultType = makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.intType
                        )
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.intType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "repeat", "drop", "take", "takeLast", "dropLast",
                         "padStart", "padEnd":
                        sema.types.stringType
                    case "toInt":
                        sema.types.intType
                    case "get":
                        sema.types.make(.primitive(.char, .nonNull))
                    case "encodeToByteArray", "toByteArray":
                        makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: sema.types.intType
                        )
                    default:
                        nil
                    }
                    if let resultType {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        switch calleeStr {
                        case "encodeToByteArray", "toByteArray":
                            sema.bindings.markCollectionExpr(id)
                        default:
                            break
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: 1-arg substring overload (STDLIB-009)
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let startType = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(startType, sema.types.intType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    if calleeStr == "substring" {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: equals(other: String?) / equals(other, ignoreCase) (STDLIB-192)
            if interner.resolve(calleeName) == "equals" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let nullableStringType = sema.types.make(.primitive(.string, .nullable))
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    if args.count == 1,
                       sema.types.isSubtype(argTypes[0], nullableStringType)
                    {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(sema.types.booleanType) : sema.types.booleanType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    if args.count == 2,
                       sema.types.isSubtype(argTypes[0], nullableStringType),
                       sema.types.isSubtype(sema.types.makeNonNullable(argTypes[1]), sema.types.booleanType)
                    {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(sema.types.booleanType) : sema.types.booleanType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: 2-arg compareTo(String, Boolean) (STDLIB-141)
            if args.count == 2, interner.resolve(calleeName) == "compareTo" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let finalType = safeCall
                        ? sema.types.makeNullable(sema.types.intType)
                        : sema.types.intType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: 2-arg commonPrefixWith/commonSuffixWith(other, ignoreCase) (STDLIB-575/576)
            if args.count == 2 {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "commonPrefixWith" || calleeStr == "commonSuffixWith" {
                    let receiverTypeForCheck = safeCall
                        ? sema.types.makeNonNullable(lookupReceiverType)
                        : lookupReceiverType
                    if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: replaceFirst(oldValue, newValue) (STDLIB-188)
            if args.count == 2, interner.resolve(calleeName) == "replaceFirst" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let oldType = sema.types.makeNonNullable(argTypes[0])
                let newType = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(oldType, sema.types.stringType),
                   sema.types.isSubtype(newType, sema.types.stringType)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: replaceRange(range, replacement) (STDLIB-188)
            if args.count == 2, interner.resolve(calleeName) == "replaceRange" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let rangeType = sema.types.makeNonNullable(argTypes[0])
                let replacementType = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(rangeType, sema.types.intType),
                   sema.types.isSubtype(replacementType, sema.types.stringType)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: removeRange(startIndex, endIndex) (STDLIB-TEXT-EDGE-008)
            if args.count == 2, interner.resolve(calleeName) == "removeRange" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let startType = sema.types.makeNonNullable(argTypes[0])
                let endType = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(startType, sema.types.intType),
                   sema.types.isSubtype(endType, sema.types.intType)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: removeRange(range) (STDLIB-TEXT-EDGE-008)
            if args.count == 1, interner.resolve(calleeName) == "removeRange" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let rangeType = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(rangeType, sema.types.intType)
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            let stringHOFReceiverType = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if let boundType = tryBindStringChunkedSequenceTransform(
                id,
                calleeName: calleeName,
                receiverType: stringHOFReceiverType,
                args: args,
                safeCall: safeCall,
                ast: ast,
                ctx: ctx,
                locals: &locals,
                explicitTypeArgs: explicitTypeArgs
            ) {
                return boundType
            }
            if let boundType = tryBindStringWindowedSequenceTransform(
                id,
                calleeName: calleeName,
                receiverType: stringHOFReceiverType,
                args: args,
                safeCall: safeCall,
                ast: ast,
                ctx: ctx,
                locals: &locals,
                explicitTypeArgs: explicitTypeArgs
            ) {
                return boundType
            }
            // String stdlib: HOF filter/map/count/any/all/none (STDLIB-189)
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let calleeStr = interner.resolve(calleeName)
                let isStringHOFReceiver = sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType)
                    || ((calleeStr == "ifBlank" || calleeStr == "ifEmpty" || calleeStr == "zipWithNext" || calleeStr == "sumBy" || calleeStr == "sumByDouble")
                        && isSyntheticStringLikeType(receiverTypeForCheck, sema: sema))
                if isStringHOFReceiver,
                   [
                       "filter", "map", "count", "any", "all", "none",
                       "indexOfFirst", "indexOfLast",
                       "mapIndexed", "mapNotNull", "filterIndexed", "filterNot",
                       "takeWhile", "dropWhile", "find", "findLast", "splitToSequence",
                       "trim", "trimStart", "trimEnd",
                       "zipWithNext",
                       "partition",
                       "ifBlank",
                       "ifEmpty",
                       "firstNotNullOf",
                       "firstNotNullOfOrNull",
                       "reduceRightIndexed",
                       "reduceRightIndexedOrNull",
                       "reduceRightOrNull",
                       "sumBy",
                       "sumByDouble",
                   ].contains(calleeStr)
                {
                    let charType = sema.types.make(.primitive(.char, .nonNull))
                    let intType = sema.types.intType
                    if calleeStr != "splitToSequence" && calleeStr != "zipWithNext" {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        let lambdaParamTypes: [TypeID]
                        switch calleeStr {
                        case "mapIndexed", "filterIndexed":
                            lambdaParamTypes = [intType, charType]
                        case "reduceRightIndexed", "reduceRightIndexedOrNull":
                            lambdaParamTypes = [intType, charType, charType]
                        case "reduceRightOrNull":
                            lambdaParamTypes = [charType, charType]
                        case "zipWithNext":
                            lambdaParamTypes = [charType, charType]
                        case "ifBlank", "ifEmpty":
                            lambdaParamTypes = []
                        default:
                            lambdaParamTypes = [charType]
                        }
                        let lambdaReturnType: TypeID
                        switch calleeStr {
                        case "map", "mapIndexed":
                            lambdaReturnType = sema.types.anyType
                        case "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull":
                            lambdaReturnType = sema.types.nullableAnyType
                        case "reduceRightIndexed", "reduceRightIndexedOrNull":
                            lambdaReturnType = charType
                        case "reduceRightOrNull":
                            lambdaReturnType = charType
                        case "zipWithNext":
                            lambdaReturnType = sema.types.anyType
                        case "ifBlank", "ifEmpty":
                            lambdaReturnType = sema.types.stringType
                        case "sumBy":
                            lambdaReturnType = sema.types.intType
                        case "sumByDouble":
                            lambdaReturnType = sema.types.doubleType
                        default:
                            lambdaReturnType = sema.types.booleanType
                        }
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: lambdaParamTypes,
                            returnType: lambdaReturnType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    }
                    if calleeStr == "zipWithNext" {
                        // Re-run inference with the transform overload so the result type
                        // comes from the lambda body rather than the placeholder `Any`.
                        guard explicitTypeArgs.count <= 1 else {
                            sema.bindings.bindExprType(id, type: sema.types.anyType)
                            return sema.types.anyType
                        }
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [charType, charType],
                            returnType: explicitTypeArgs.first ?? sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        let bodyType = explicitTypeArgs.first
                            ?? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                        if let chosen = sema.symbols.lookupAll(fqName: [
                            interner.intern("kotlin"),
                            interner.intern("text"),
                            calleeName,
                        ]).first(where: { candidate in
                            isSyntheticStringMemberCandidate(
                                candidate,
                                named: calleeName,
                                receiverType: receiverTypeForCheck,
                                sema: sema,
                                interner: interner
                            )
                                && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                        }) {
                            sema.bindings.bindCall(
                                id,
                                binding: CallBinding(
                                    chosenCallee: chosen,
                                    substitutedTypeArguments: [bodyType],
                                    parameterMapping: [0: 0]
                                )
                            )
                            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        }
                        let resultType = makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: bodyType
                        )
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    if calleeStr == "firstNotNullOf" {
                        guard explicitTypeArgs.count <= 1 else {
                            sema.bindings.bindExprType(id, type: sema.types.anyType)
                            return sema.types.anyType
                        }
                        let lambdaExpectedReturn = explicitTypeArgs.first.map { sema.types.makeNullable($0) }
                            ?? sema.types.nullableAnyType
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: lambdaExpectedReturn,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        let bodyType = explicitTypeArgs.first
                            ?? sema.types.makeNonNullable(inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema))
                        if let chosen = sema.symbols.lookupAll(fqName: [
                            interner.intern("kotlin"),
                            interner.intern("text"),
                            calleeName,
                        ]).first(where: { candidate in
                            isSyntheticStringMemberCandidate(
                                candidate,
                                named: calleeName,
                                receiverType: receiverTypeForCheck,
                                sema: sema,
                                interner: interner
                            )
                                && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                        }) {
                            sema.bindings.bindCall(
                                id,
                                binding: CallBinding(
                                    chosenCallee: chosen,
                                    substitutedTypeArguments: [bodyType],
                                    parameterMapping: [0: 0]
                                )
                            )
                            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        }
                        let finalType = safeCall ? sema.types.makeNullable(bodyType) : bodyType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    if calleeStr == "firstNotNullOfOrNull" {
                        guard explicitTypeArgs.count <= 1 else {
                            sema.bindings.bindExprType(id, type: sema.types.nullableAnyType)
                            return sema.types.nullableAnyType
                        }
                        let lambdaExpectedReturn = explicitTypeArgs.first.map { sema.types.makeNullable($0) }
                            ?? sema.types.nullableAnyType
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: lambdaExpectedReturn,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        let bodyType = explicitTypeArgs.first
                            ?? sema.types.makeNonNullable(inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema))
                        if let chosen = sema.symbols.lookupAll(fqName: [
                            interner.intern("kotlin"),
                            interner.intern("text"),
                            calleeName,
                        ]).first(where: { candidate in
                            isSyntheticStringMemberCandidate(
                                candidate,
                                named: calleeName,
                                receiverType: receiverTypeForCheck,
                                sema: sema,
                                interner: interner
                            )
                                && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
                        }) {
                            sema.bindings.bindCall(
                                id,
                                binding: CallBinding(
                                    chosenCallee: chosen,
                                    substitutedTypeArguments: [bodyType],
                                    parameterMapping: [0: 0]
                                )
                            )
                            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        }
                        let resultType = sema.types.makeNullable(bodyType)
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    let sequenceStringType: TypeID = {
                        let knownNames = KnownCompilerNames(interner: interner)
                        guard let sequenceSymbol = sema.symbols.lookupAll(fqName: knownNames.kotlinSequenceFQName).first else {
                            return sema.types.anyType
                        }
                        return sema.types.make(.classType(ClassType(
                            classSymbol: sequenceSymbol,
                            args: [.out(sema.types.stringType)],
                            nullability: .nonNull
                        )))
                    }()
                    bindSyntheticStringMemberDirectlyIfAvailable(
                        id,
                        calleeName: calleeName,
                        argumentCount: args.count,
                        receiverType: receiverTypeForCheck,
                        sema: sema,
                        interner: interner
                    )
                    let pairStringStringType: TypeID = {
                        let pairFQName: [InternedString] = [
                            interner.intern("kotlin"),
                            interner.intern("Pair"),
                        ]
                        guard let pairSymbol = sema.symbols.lookup(fqName: pairFQName) else {
                            return sema.types.anyType
                        }
                        return sema.types.make(.classType(ClassType(
                            classSymbol: pairSymbol,
                            args: [.out(sema.types.stringType), .out(sema.types.stringType)],
                            nullability: .nonNull
                        )))
                    }()
                    let resultType: TypeID = switch calleeStr {
                    case "filter": sema.types.stringType
                    case "map": sema.types.anyType
                    case "mapIndexed", "mapNotNull": sema.types.anyType
                    case "count": sema.types.intType
                    case "indexOfFirst", "indexOfLast": sema.types.intType
                    case "any", "all", "none": sema.types.booleanType
                    case "filterIndexed", "filterNot", "takeWhile", "dropWhile": sema.types.stringType
                    case "find", "findLast": sema.types.make(.primitive(.char, .nullable))
                    case "splitToSequence": sequenceStringType
                    case "partition": pairStringStringType
                    case "ifBlank", "ifEmpty": sema.types.stringType
                    case "reduceRightIndexed": charType
                    case "reduceRightIndexedOrNull": sema.types.make(.primitive(.char, .nullable))
                    case "reduceRightOrNull": sema.types.make(.primitive(.char, .nullable))
                    case "sumBy": sema.types.intType
                    case "sumByDouble": sema.types.doubleType
                    default: sema.types.anyType
                    }
                    // For "partition", skip the fallback resolver (which may fail due to
                    // lambda argType mismatch) and bind the synthetic symbol directly.
                    if calleeStr == "partition" {
                        bindSyntheticStringMemberDirectlyIfAvailable(
                            id,
                            calleeName: calleeName,
                            argumentCount: args.count,
                            receiverType: receiverTypeForCheck,
                            sema: sema,
                            interner: interner
                        )
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    switch calleeStr {
                    case "map":
                        sema.bindings.markCollectionExpr(id)
                    default:
                        break
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: replaceFirstChar(transform) (STDLIB-315)
            if args.count == 1, interner.resolve(calleeName) == "replaceFirstChar" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    let charType = sema.types.make(.primitive(.char, .nonNull))
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [charType],
                        returnType: charType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let resolvedArgTypes = zip(args.indices, argTypes).map { index, originalType in
                        sema.bindings.exprTypes[args[index].expr] ?? originalType
                    }
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: resolvedArgTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let stringMemberFQName = [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        calleeName,
                    ]
                    if let chosen = sema.symbols.lookup(fqName: stringMemberFQName) {
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
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: 2-arg methods (STDLIB-006)
            if args.count == 2, interner.resolve(calleeName) == "replace" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let oldType = sema.types.makeNonNullable(argTypes[0])
                let newType = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(oldType, sema.types.stringType),
                   sema.types.isSubtype(newType, sema.types.stringType)
                {
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if args.count == 2 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                let arg1Type = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.stringType),
                   isJavaUtilLocaleType(arg1Type, sema: sema, interner: interner),
                   interner.resolve(calleeName) == "compareTo"
                {
                    if let boundType = tryBindSyntheticStringMemberFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: 2-arg substring overload (STDLIB-009)
            if args.count == 2 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let startType = sema.types.makeNonNullable(argTypes[0])
                let arg1Type = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(startType, sema.types.intType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "indexOf" where sema.types.isSubtype(arg1Type, sema.types.intType):
                        sema.types.intType
                    case "substring" where sema.types.isSubtype(arg1Type, sema.types.intType):
                        sema.types.stringType
                    case "padStart" where arg1Type == sema.types.charType:
                        sema.types.stringType
                    case "padEnd" where arg1Type == sema.types.charType:
                        sema.types.stringType
                    default:
                        nil
                    }
                    if let resultType {
                        if let boundType = tryBindSyntheticStringMemberFallback(
                            id,
                            calleeName: calleeName,
                            receiverType: receiverTypeForCheck,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            ctx: ctx,
                            expectedType: expectedType,
                            explicitTypeArgs: explicitTypeArgs,
                            safeCall: safeCall
                        ) {
                            return boundType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: format(vararg args) (STDLIB-006)
            if calleeName == interner.intern("format"), !hasLeadingLocaleArgument {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    if let boundType = tryBindSyntheticStringFormatFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                }
            }
            // For non-empty-arg member calls, try member property/field lookup.
            // This handles callable property syntax (e.g. `receiver.f(...)`).
            // Skip this for class-name receivers — only companion members are
            // accessible via `ClassName.member`, not instance properties.
            if !isClassNameReceiver,
               !args.isEmpty,
               let propResult = driver.helpers.lookupMemberProperty(
                   named: calleeName,
                   receiverType: memberLookupType,
                   sema: sema
               )
            {
                // Check visibility before trying callable-style resolution.
                if let propSymbol = sema.symbols.symbol(propResult.symbol),
                   !ctx.visibilityChecker.isAccessible(propSymbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol)
                {
                    driver.helpers.emitVisibilityError(for: propSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }

                // Property value call with function type (`receiver.f(...)`).
                if let callableType = inferFunctionTypeOrError(from: propResult.type, sema: sema) {
                    if let callableResult = inferCallableValueInvocation(
                        id,
                        calleeType: callableType,
                        callableTarget: .localValue(propResult.symbol),
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType
                    ) {
                        let finalType = safeCall ? sema.types.makeNullable(callableResult) : callableResult
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }

                // Property value call through `operator fun invoke(...)`.
                let invokeName = interner.intern("invoke")
                let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: invokeName,
                    receiverType: propResult.type,
                    sema: sema,
                    interner: interner
                ).filter { candidateID in
                    guard let sym = sema.symbols.symbol(candidateID) else { return false }
                    return sym.flags.contains(.operatorFunction)
                }

                if !invokeCandidates.isEmpty {
                    let resolvedArgs = zip(args, argTypes).map { argument, type in
                        CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                    }
                    let resolved = ctx.resolver.resolveCall(
                        candidates: invokeCandidates,
                        call: CallExpr(
                            range: range,
                            calleeName: invokeName,
                            args: resolvedArgs,
                            explicitTypeArgs: explicitTypeArgs
                        ),
                        expectedType: expectedType,
                        implicitReceiverType: propResult.type,
                        ctx: ctx.semaCtx
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee {
                        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                        sema.bindings.markInvokeOperatorCall(id)
                        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }

            if lookupReceiverType == sema.types.errorType {
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            // Kotlin infix `to` is effectively a universal extension used by
            // destructuring-friendly literals (e.g. `1 to "a"`). Keep a
            // lightweight fallback when no symbol candidate was discovered.
            if !isClassNameReceiver,
               args.count == 1,
               calleeName == knownNames.to
            {
                let resultType = sema.types.anyType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if let firstInvisible = invisible.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryRegexMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryKFunctionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryStringMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryFileMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryCollectionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryArrayMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRangeMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            // Flow member access fallback (CORO-003): allow flow chain calls
            // only when receiver provenance is known as Flow.
            if !isClassNameReceiver, isFlowReceiver {
                let memberName = interner.resolve(calleeName)
                let flowMembers: Set = ["map", "filter", "take", "collect", "single", "catch", "retry", "retryWhen"]
                if flowMembers.contains(memberName) {
                    let acceptsArity = memberName == "single" ? args.isEmpty : args.count == 1
                    if memberName == "single", acceptsArity {
                        let resultType = safeCall ? sema.types.makeNullable(flowElementType) : flowElementType
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                    if acceptsArity,
                       memberName == "map" || memberName == "filter" || memberName == "collect" ||
                        memberName == "catch" || memberName == "retryWhen"
                    {
                        let expectsLambdaTypeConstraint = switch ast.arena.expr(args[0].expr) {
                        case .callableRef:
                            false
                        default:
                            true
                        }
                        let lambdaReturnType: TypeID = switch memberName {
                        case "filter":
                            sema.types.make(.primitive(.boolean, .nonNull))
                        case "collect":
                            sema.types.unitType
                        case "catch":
                            sema.types.unitType
                        case "retryWhen":
                            sema.types.booleanType
                        default:
                            sema.types.anyType
                        }
                        let lambdaParameterTypes: [TypeID] = switch memberName {
                        case "catch":
                            [sema.types.anyType]
                        case "retryWhen":
                            [sema.types.anyType, sema.types.longType]
                        default:
                            [flowElementType]
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
                    }

                    if acceptsArity {
                        if memberName == "map" || memberName == "filter" || memberName == "take" ||
                            memberName == "catch" || memberName == "retry" || memberName == "retryWhen"
                        {
                            sema.bindings.markFlowExpr(id)
                            let resultElementType: TypeID = switch memberName {
                            case "map":
                                if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr),
                                   let mappedType = sema.bindings.exprType(for: bodyExpr)
                                {
                                    mappedType
                                } else {
                                    sema.types.anyType
                                }
                            case "filter", "take", "catch", "retry", "retryWhen":
                                flowElementType
                            default:
                                sema.types.anyType
                            }
                            sema.bindings.bindFlowElementType(resultElementType, forExpr: id)
                        }
                        let resultType: TypeID
                        if memberName == "collect" {
                            resultType = sema.types.unitType
                        } else {
                            let resultElement = sema.bindings.flowElementType(forExpr: id) ?? flowElementType
                            resultType = driver.helpers.makeFlowType(
                                elementType: resultElement, sema: sema, interner: interner
                            ) ?? sema.types.anyType
                        }
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }

            let isCoroutineHandleReceiver = isCoroutineHandleReceiverType(
                lookupReceiverType,
                sema: sema,
                interner: interner
            )
            if !isClassNameReceiver, args.isEmpty, isCoroutineHandleReceiver {
                let memberName = interner.resolve(calleeName)
                switch memberName {
                case "cancel":
                    let resultType = sema.types.unitType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "join":
                    let resultType = sema.types.unitType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "await":
                    let resultType = sema.types.nullableAnyType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "isActive", "isCompleted", "isCancelled", "isClosedForReceive", "isClosedForSend":
                    let resultType = sema.types.booleanType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                default:
                    break
                }
            }
            // Builder DSL member functions (STDLIB-002).
            if ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
                let name = interner.resolve(calleeName)
                let isBuilderMember: Bool = switch activeBuilderKind {
                case .buildString:
                    (name == "append" && args.count == 1)
                        || (name == "appendLine" && args.count <= 1)
                        || (name == "appendRange" && args.count == 3)
                case .buildList, .buildSet: name == "add" && args.count == 1
                case .buildMap: name == "put" && args.count == 2
                }
                if isBuilderMember {
                    _ = args.map { argument in
                        driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                    }
                    sema.bindings.markBuilderDSLExpr(id, kind: activeBuilderKind)
                    sema.bindings.bindExprType(id, type: sema.types.unitType)
                    return sema.types.unitType
                }
            }

            // STDLIB-532/533/534, STDLIB-SEQ-011: orEmpty() on nullable receivers
            if interner.resolve(calleeName) == "orEmpty", args.isEmpty {
                let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
                let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                    let resultType = sema.types.stringType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                if isListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    let resultType = nonNullReceiverType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                if isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                    let resultType = nonNullReceiverType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                let knownNames = KnownCompilerNames(interner: interner)
                if case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
                   let symbol = sema.symbols.symbol(classType.classSymbol),
                   knownNames.isMapLikeSymbol(symbol) {
                    let resultType = nonNullReceiverType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }

            // Collection fallback needs to run before the generic overload resolver
            // so synthetic collection members can use their specialized lambda
            // expectations without type-variable noise from the general path.
            if let fallbackType = tryCollectionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryBindThreadLocalGetOrSetFallback(
                id,
                calleeName: calleeName,
                safeCall: safeCall,
                receiverType: lookupReceiverType,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryBindMapGetOrElseFallback(
                id,
                calleeName: calleeName,
                safeCall: safeCall,
                receiverType: lookupReceiverType,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryBindReadWriteLockReadFallback(
                id,
                calleeName: calleeName,
                safeCall: safeCall,
                receiverType: lookupReceiverType,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryBindComparatorMemberFallback(
                id,
                calleeName: calleeName,
                safeCall: safeCall,
                receiverType: lookupReceiverType,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }

            // Receiver-lambda invocation: `receiver.localVar()` where localVar
            // has a function-with-receiver type matching the receiver.
            // e.g. `sb.action()` where action: StringBuilder.() -> Unit
            if let local = locals[calleeName] {
                let localType = local.type
                if case let .functionType(fnType) = sema.types.kind(of: localType),
                   fnType.receiver != nil
                {
                    let argTypes = args.map { argument in
                        driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                    }
                    _ = argTypes // suppress unused warning
                    let resultType = fnType.returnType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    // Mark as callable-value call so KIR emits an indirect call
                    // through the closure pointer with the receiver prepended.
                    sema.bindings.bindCallableValueCall(
                        id,
                        binding: CallableValueCallBinding(
                            target: .localValue(local.symbol),
                            functionType: localType,
                            parameterMapping: [:]
                        )
                    )
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                // Support function values that were represented as a regular
                // function type where the first parameter is the receiver.
                // Example: `val f: StringBuilder.() -> Unit` may be encoded as
                // `(StringBuilder) -> Unit` in some contexts.
                if case let .functionType(fnType) = sema.types.kind(of: localType),
                   !fnType.params.isEmpty,
                   args.count == fnType.params.count - 1,
                   sema.types.isSubtype(
                       sema.types.makeNonNullable(receiverType),
                       fnType.params[0]
                   )
                {
                    for (index, argument) in args.enumerated() {
                        let expectedArgumentType = fnType.params[index + 1]
                        _ = driver.inferExpr(
                            argument.expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: expectedArgumentType
                        )
                    }
                    let boundFunctionType = sema.types.make(.functionType(FunctionType(
                        receiver: fnType.params[0],
                        params: Array(fnType.params.dropFirst()),
                        returnType: fnType.returnType,
                        isSuspend: fnType.isSuspend,
                        nullability: fnType.nullability
                    )))
                    let resultType = fnType.returnType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindCallableValueCall(
                        id,
                        binding: CallableValueCallBinding(
                            target: .localValue(local.symbol),
                            functionType: boundFunctionType,
                            parameterMapping: [:]
                        )
                    )
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }

            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // Use the companion type as implicit receiver when the candidates were
        // redirected from the owner class to its companion object.
        let effectiveReceiverType = companionReceiverType ?? lookupReceiverType
        // Synthetic collection members need to short-circuit before the generic
        // overload resolver so their trailing-lambda expectations stay concrete.
        if let fallbackType = tryCollectionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindThreadLocalGetOrSetFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindMapGetOrElseFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindReadWriteLockReadFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindComparatorMemberFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral, .callableRef:
                continue
            default:
                cachedNonLambdaArgTypes[index] = argTypes[index]
            }
        }
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: effectiveReceiverType,
            ctx: ctx,
            locals: &locals
        )
        let resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: range,
            calleeName: calleeName,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: expectedType,
            implicitReceiverType: effectiveReceiverType,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            ctx: ctx
        )
        if let diagnostic = resolved.diagnostic {
            if diagnostic.code == "KSWIFTK-SEMA-BOUND" {
                let callee = interner.resolve(calleeName)
                if callee == "sorted" || callee == "sortedDescending" {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
            }
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryRegexMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryKFunctionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryStringMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryFileMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryArrayMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRangeMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
            } else {
                ctx.semaCtx.diagnostics.emit(diagnostic)
            }
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        guard let chosen = resolved.chosenCallee else {
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryCollectionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRegexMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryKFunctionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryStringMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryFileMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryArrayMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRangeMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: ctx,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        // P5-112: Prohibit super.foo() calls to abstract members.
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(SymbolFlags.abstractType),
           chosenSym.kind == SymbolKind.function || chosenSym.kind == SymbolKind.property
        {
            let memberName = interner.resolve(calleeName)
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-ABSTRACT",
                "Cannot call abstract member '\(memberName)' via super.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // --- Use-site variance projection check ---
        // When the receiver has projected type arguments (e.g. MutableList<out Number>),
        // check that the member access respects variance constraints.
        if let signature = sema.symbols.functionSignature(for: chosen),
           let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
               receiverType: lookupReceiverType,
               signature: signature,
               symbols: sema.symbols
           )
        {
            // Check if any parameter uses a write-forbidden type parameter
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: sema, interner: interner),
               let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
               )
            {
                let paramType = sema.types.renderType(signature.parameterTypes[violatingParamIndex])
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: range
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }

            // For projected types, merge the solver's substitution with the
            // variance projection (projection overrides receiver type params).
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let mergedSubstitution = resolved.substitutedTypeArguments.merging(
                varianceResult.covariantSubstitution,
                uniquingKeysWith: { _, projected in projected }
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: mergedSubstitution
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            let projectedReturnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: mergedSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if isSuperCall { sema.bindings.markSuperCall(id) }
            let finalType = safeCall ? sema.types.makeNullable(projectedReturnType) : projectedReturnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        if isSuperCall { sema.bindings.markSuperCall(id) }
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isJavaUtilLocaleType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbolID = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(type),
            types: sema.types
        ),
            let symbol = sema.symbols.symbol(symbolID)
        else {
            return false
        }
        return symbol.fqName == [
            interner.intern("java"),
            interner.intern("util"),
            interner.intern("Locale"),
        ]
    }

    private func isMutableListType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let symbolID = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(type),
            types: sema.types
        ),
            let symbol = sema.symbols.symbol(symbolID)
        else {
            return false
        }
        return symbol.name == knownNames.mutableList
            || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
    }

    private func isSyntheticStringFormatCandidate(
        _ symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.fqName == [
                  interner.intern("kotlin"),
                  interner.intern("text"),
                  interner.intern("format"),
              ],
              let signature = sema.symbols.functionSignature(for: symbolID)
        else {
            return false
        }
        return signature.receiverType == sema.types.stringType
    }

    private func makeSyntheticListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticNominalType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner _: StringInterner,
        fqName: [InternedString]
    ) -> TypeID {
        guard let symbol = symbols.lookup(fqName: fqName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func tryBindSyntheticStringFormatFallback(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID? {
        tryBindSyntheticStringMemberFallback(
            id,
            calleeName: calleeName,
            receiverType: receiverType,
            args: args,
            argTypes: argTypes,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall
        )
    }

    private func tryBindSyntheticStringMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        var candidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
            isSyntheticStringMemberCandidate(
                candidate,
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            )
        }
        if candidates.isEmpty {
            let stringMemberFQName = [
                interner.intern("kotlin"),
                interner.intern("text"),
                calleeName,
            ]
            candidates = sema.symbols.lookupAll(fqName: stringMemberFQName).filter { candidate in
                isSyntheticStringMemberCandidate(
                    candidate,
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                )
            }
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: resolvedArgs,
                explicitTypeArgs: explicitTypeArgs
            ),
            expectedType: expectedType,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func tryBindSyntheticBigIntegerMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let normalizedReceiverType = sema.types.makeNonNullable(receiverType)
        let bigIntegerFQName = [
            interner.intern("java"),
            interner.intern("math"),
            interner.intern("BigInteger"),
        ]
        guard let bigIntegerSymbol = sema.symbols.lookup(fqName: bigIntegerFQName),
              case let .classType(receiverClass) = sema.types.kind(of: normalizedReceiverType),
              receiverClass.classSymbol == bigIntegerSymbol
        else {
            return nil
        }

        let extensionFQName = [
            interner.intern("kotlin"),
            calleeName,
        ]
        let candidates = sema.symbols.lookupAll(fqName: extensionFQName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.receiverType == normalizedReceiverType &&
                signature.parameterTypes == [normalizedReceiverType]
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: resolvedArgs,
                explicitTypeArgs: explicitTypeArgs
            ),
            expectedType: expectedType,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSyntheticStringMemberCandidate(
        _ symbolID: SymbolID,
        named calleeName: InternedString,
        receiverType actualReceiverType: TypeID? = nil,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.fqName == [
                  interner.intern("kotlin"),
                  interner.intern("text"),
                  calleeName,
              ],
              let signature = sema.symbols.functionSignature(for: symbolID)
        else {
            return false
        }
        guard let candidateReceiverType = signature.receiverType else {
            return false
        }
        guard isSyntheticStringLikeType(candidateReceiverType, sema: sema) else {
            return false
        }
        if let actualReceiverType {
            return sema.types.isSubtype(
                sema.types.makeNonNullable(actualReceiverType),
                sema.types.makeNonNullable(candidateReceiverType)
            )
        }
        return true
    }

    private func bindSyntheticStringMemberDirectlyIfAvailable(
        _ id: ExprID,
        calleeName: InternedString,
        argumentCount: Int,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let normalizedReceiverType = sema.types.makeNonNullable(receiverType)
        guard isSyntheticStringLikeType(normalizedReceiverType, sema: sema) else {
            return
        }
        let stringMemberFQName = [
            interner.intern("kotlin"),
            interner.intern("text"),
            calleeName,
        ]
        guard let chosen = sema.symbols.lookupAll(fqName: stringMemberFQName).first(where: { candidate in
                  isSyntheticStringMemberCandidate(
                      candidate,
                      named: calleeName,
                      receiverType: normalizedReceiverType,
                      sema: sema,
                      interner: interner
                  )
                      && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == argumentCount
              })
        else {
            return
        }
        let mapping = Dictionary(uniqueKeysWithValues: (0..<argumentCount).map { ($0, $0) })
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [],
                parameterMapping: mapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
    }

    private func syntheticCharSequenceType(sema: SemaModule) -> TypeID? {
        guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func tryBindStringChunkedSequenceTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 2,
              interner.resolve(calleeName) == "chunkedSequence",
              isSyntheticStringLikeType(receiverType, sema: sema)
        else {
            return nil
        }
        guard let lambdaArgIndex = args.indices.first(where: { index in
            ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
        }) else {
            return nil
        }
        guard let sizeArgIndex = args.indices.first(where: { index in
            index != lambdaArgIndex
        }) else {
            return nil
        }
        guard explicitTypeArgs.count <= 1 else {
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }
        let charSequenceType = syntheticCharSequenceType(sema: sema) ?? sema.types.stringType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: explicitTypeArgs.first ?? sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(args[sizeArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
        _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let bodyType = explicitTypeArgs.first
            ?? inferredLambdaReturnType(argExpr: args[lambdaArgIndex].expr, ast: ast, sema: sema)
        guard let chosen = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            calleeName,
        ]).first(where: { candidate in
            isSyntheticStringMemberCandidate(
                candidate,
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            )
                && sema.symbols.externalLinkName(for: candidate) == "kk_string_chunkedSequence_transform"
        }) else {
            return nil
        }
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [bodyType],
                parameterMapping: [sizeArgIndex: 0, lambdaArgIndex: 1]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let resultType = makeSyntheticSequenceType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            elementType: bodyType
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func tryBindStringWindowedSequenceTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 4,
              interner.resolve(calleeName) == "windowedSequence",
              isSyntheticStringLikeType(receiverType, sema: sema)
        else {
            return nil
        }
        guard let lambdaArgIndex = args.indices.first(where: { index in
            ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
        }) else {
            return nil
        }
        let scalarArgIndices = args.indices.filter { $0 != lambdaArgIndex }
        guard scalarArgIndices.count == 3 else {
            return nil
        }
        func scalarArgIndex(named name: String, fallbackPosition: Int) -> Int? {
            if let labeled = scalarArgIndices.first(where: { index in
                guard let label = args[index].label else { return false }
                return interner.resolve(label) == name
            }) {
                return labeled
            }
            guard fallbackPosition < scalarArgIndices.count else {
                return nil
            }
            return scalarArgIndices[fallbackPosition]
        }
        guard let sizeArgIndex = scalarArgIndex(named: "size", fallbackPosition: 0),
              let stepArgIndex = scalarArgIndex(named: "step", fallbackPosition: 1),
              let partialArgIndex = scalarArgIndex(named: "partialWindows", fallbackPosition: 2)
        else {
            return nil
        }
        guard explicitTypeArgs.count <= 1 else {
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }
        let charSequenceType = syntheticCharSequenceType(sema: sema) ?? sema.types.stringType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: explicitTypeArgs.first ?? sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(args[sizeArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        _ = driver.inferExpr(args[stepArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        _ = driver.inferExpr(args[partialArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
        sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
        _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let bodyType = explicitTypeArgs.first
            ?? inferredLambdaReturnType(argExpr: args[lambdaArgIndex].expr, ast: ast, sema: sema)
        guard let chosen = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            calleeName,
        ]).first(where: { candidate in
            isSyntheticStringMemberCandidate(
                candidate,
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            )
                && sema.symbols.externalLinkName(for: candidate) == "kk_string_windowedSequence_transform"
        }) else {
            return nil
        }
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [bodyType],
                parameterMapping: [
                    sizeArgIndex: 0,
                    stepArgIndex: 1,
                    partialArgIndex: 2,
                    lambdaArgIndex: 3,
                ]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let resultType = makeSyntheticSequenceType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            elementType: bodyType
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSyntheticStringLikeType(_ type: TypeID, sema: SemaModule) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        if nonNullType == sema.types.stringType {
            return true
        }
        guard let charSequenceType = syntheticCharSequenceType(sema: sema) else {
            return false
        }
        return nonNullType == charSequenceType
    }

    private func getCollectionElementType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType) else {
            return sema.types.anyType
        }

        if let symbol = sema.symbols.symbol(classType.classSymbol),
           knownNames.isMapLikeSymbol(symbol),
           classType.args.count == 2
        {
            let keyType = switch classType.args[0] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
            let valueType = switch classType.args[1] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
            let entryFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Map"),
                interner.intern("Entry"),
            ]
            if let entrySymbol = sema.symbols.lookup(fqName: entryFQName) ?? sema.symbols.lookupByShortName(interner.intern("Entry")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: entrySymbol,
                    args: [.out(keyType), .out(valueType)],
                    nullability: .nonNull
                )))
            }
            return makeSyntheticPairType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                firstType: keyType,
                secondType: valueType
            )
        }

        if let firstArg = classType.args.first {
            return switch firstArg {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        }
        return sema.types.anyType
    }

    private func resolvedGroupingKeyType(
        of type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              knownNames.isGroupingSymbol(symbol),
              classType.args.count >= 2
        else {
            return nil
        }
        return switch classType.args[1] {
        case let .invariant(id), let .out(id), let .in(id):
            id
        case .star:
            sema.types.anyType
        }
    }

    func tryGroupingMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverID: ExprID,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        expectedType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        guard let groupingKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) else {
            return nil
        }
        let groupingElementType = resolvedCollectionElementType(
            receiverID: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner,
            ctx: ctx,
            locals: &locals
        )
        let calleeStr = interner.resolve(calleeName)
        let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner)

        func makeMapType(valueType: TypeID) -> TypeID {
            guard let mapSymbol else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(groupingKeyType), .invariant(valueType)],
                nullability: .nonNull
            )))
        }

        func memberTypeArgument(_ type: TypeID, index: Int) -> TypeID? {
            guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
                  classType.args.indices.contains(index)
            else {
                return nil
            }
            return switch classType.args[index] {
            case let .invariant(id), let .out(id), let .in(id):
                id
            case .star:
                nil
            }
        }

        func lookupGroupingMember(named name: String, externalLinkName: String, parameterCount: Int) -> SymbolID? {
            let memberFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Grouping"),
                interner.intern(name),
            ]
            return sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return sema.symbols.externalLinkName(for: candidate) == externalLinkName
                    && signature.parameterTypes.count == parameterCount
                    && sema.symbols.symbol(candidate)?.flags.contains(.synthetic) == true
            })
        }

        func bindGroupingMemberCall(
            chosen: SymbolID,
            substitutedTypeArguments: [TypeID],
            parameterMapping: [Int: Int]
        ) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: substitutedTypeArguments,
                    parameterMapping: parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        }

        switch calleeStr {
        case "eachCount":
            guard args.isEmpty else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let resultType = makeMapType(valueType: sema.types.intType)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "aggregate":
            guard args.count == 1 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let expectedAggregateValueType = memberTypeArgument(expectedType ?? sema.types.anyType, index: 1)
                ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [
                    groupingKeyType,
                    sema.types.makeNullable(expectedAggregateValueType),
                    groupingElementType,
                    sema.types.booleanType,
                ],
                returnType: expectedAggregateValueType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let aggregateValueType = expectedAggregateValueType == sema.types.anyType
                ? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                : expectedAggregateValueType
            let resultType = makeMapType(valueType: aggregateValueType)
            if let chosen = lookupGroupingMember(named: "aggregate", externalLinkName: "kk_grouping_aggregate", parameterCount: 1) {
                bindGroupingMemberCall(
                    chosen: chosen,
                    substitutedTypeArguments: [groupingElementType, groupingKeyType, aggregateValueType],
                    parameterMapping: [0: 0]
                )
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "aggregateTo":
            guard args.count == 2 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let destinationValueType = memberTypeArgument(destinationType, index: 1) ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [
                    groupingKeyType,
                    sema.types.makeNullable(destinationValueType),
                    groupingElementType,
                    sema.types.booleanType,
                ],
                returnType: destinationValueType
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            if let chosen = lookupGroupingMember(named: "aggregateTo", externalLinkName: "kk_grouping_aggregateTo", parameterCount: 2) {
                bindGroupingMemberCall(
                    chosen: chosen,
                    substitutedTypeArguments: [groupingElementType, groupingKeyType, destinationValueType],
                    parameterMapping: [0: 0, 1: 1]
                )
            }
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "fold":
            guard args.count == 2 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let expectedGroupingValueType: TypeID = if let expectedType,
                                                       case let .classType(expectedClassType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
                                                       let expectedSymbol = sema.symbols.symbol(expectedClassType.classSymbol),
                                                       knownNames.isMapLikeSymbol(expectedSymbol),
                                                       expectedClassType.args.count >= 2
            {
                switch expectedClassType.args[1] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let firstArgLabel = args[0].label.map { interner.resolve($0) }
            let useInitialValueSelectorOverload = if let firstArgLabel {
                firstArgLabel == "initialValueSelector"
            } else if case .lambdaLiteral = ast.arena.expr(args[0].expr) {
                true
            } else {
                ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false
            }
            if useInitialValueSelectorOverload {
                let initialValueSelectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [groupingKeyType, groupingElementType],
                    returnType: expectedGroupingValueType
                )))
                let initialValueSelectorType = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initialValueSelectorExpectedType
                )
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                let groupingResultValueType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: initialValueSelectorType) {
                    fnType.returnType
                } else if expectedGroupingValueType != sema.types.anyType {
                    expectedGroupingValueType
                } else {
                    sema.types.anyType
                }
                let operationExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [groupingKeyType, groupingResultValueType, groupingElementType],
                    returnType: groupingResultValueType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                let resultType = makeMapType(valueType: groupingResultValueType)
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            } else {
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedGroupingValueType)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [groupingKeyType, initialType, groupingElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let resultType = makeMapType(valueType: initialType)
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }

        case "reduce":
            guard args.count == 1 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [groupingElementType, groupingElementType],
                returnType: groupingElementType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let resultType = makeMapType(valueType: groupingElementType)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        default:
            return nil
        }
    }

    private func tryDurationToComponentsMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let interner = ctx.interner
        guard interner.resolve(calleeName) == "toComponents",
              args.count == 1,
              explicitTypeArgs.count <= 1,
              isKotlinDurationType(receiverType, sema: sema, interner: interner),
              let lambdaExpr = ast.arena.expr(args[0].expr),
              lambdaExpr.isLambdaOrCallableRef
        else {
            return nil
        }

        let lambdaArity: Int
        if case let .lambdaLiteral(params, _, _, _) = lambdaExpr, !params.isEmpty {
            lambdaArity = params.count
        } else {
            lambdaArity = 5
        }

        let actionParameterTypes: [TypeID]
        let externalLinkName: String
        switch lambdaArity {
        case 2:
            actionParameterTypes = [sema.types.longType, sema.types.intType]
            externalLinkName = "kk_duration_toComponents_seconds"
        case 3:
            actionParameterTypes = [sema.types.longType, sema.types.intType, sema.types.intType]
            externalLinkName = "kk_duration_toComponents_minutes"
        case 4:
            actionParameterTypes = [sema.types.longType, sema.types.intType, sema.types.intType, sema.types.intType]
            externalLinkName = "kk_duration_toComponents_hours"
        case 5:
            actionParameterTypes = [
                sema.types.longType,
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
            ]
            externalLinkName = "kk_duration_toComponents_days"
        default:
            return nil
        }

        let expectedReturnType = explicitTypeArgs.first ?? expectedType ?? sema.types.anyType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: actionParameterTypes,
            returnType: expectedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        let inferredActionType = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: lambdaExpectedType
        )

        let resultType: TypeID = if let explicit = explicitTypeArgs.first {
            explicit
        } else if expectedType != nil, expectedReturnType != sema.types.anyType {
            expectedReturnType
        } else if case let .functionType(functionType) = sema.types.kind(
            of: sema.types.makeNonNullable(inferredActionType)
        ) {
            functionType.returnType
        } else {
            inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
        }

        let durationMemberFQName = [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("Duration"),
            calleeName,
        ]
        if let chosen = sema.symbols.lookupAll(fqName: durationMemberFQName).first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == externalLinkName
        }) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [resultType],
                    parameterMapping: [0: 0]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        }

        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isKotlinDurationType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.fqName == [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("Duration"),
        ]
    }

    /// Extract the inferred return type from a lambda argument.
    /// Checks the lambda body expression first, then falls back to the function
    /// type of the argument expression. Returns `anyType` if neither is available.
    private func inferredLambdaReturnType(
        argExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID {
        if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(argExpr) {
            return sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
        } else if case let .functionType(fnType) = sema.types.kind(
            of: sema.bindings.exprType(for: argExpr) ?? sema.types.anyType
        ) {
            return fnType.returnType
        } else {
            return sema.types.anyType
        }
    }

    /// Extract the element type from a List type.
    /// If the type is List<R> (or similar single-type-arg list), returns R.
    /// Returns `anyType` for non-list types to avoid mis-inferring element types
    /// from unrelated generic types (e.g., Pair<K,V>).
    private func extractListElementType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              knownNames.isConcreteListLikeSymbol(symbol),
              classType.args.count == 1,
              let firstArg = classType.args.first
        else {
            return sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
    }

    /// Extract the element type from flattenable Iterable/Sequence-like return types.
    private func extractIterableOrSequenceElementType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              classType.args.count == 1,
              let firstArg = classType.args.first
        else {
            return sema.types.anyType
        }
        let symbolName = interner.resolve(symbol.name)
        let isFlattenable = knownNames.isConcreteListLikeSymbol(symbol)
            || knownNames.isSetLikeSymbol(symbol)
            || knownNames.isSequenceSymbol(symbol)
            || symbolName == "Iterable"
            || symbolName == "Collection"
        guard isFlattenable else {
            return sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
    }

    /// Extract the element type T from a Comparator<T> receiver type.
    /// Returns `nil` if the receiver does not resolve to Comparator.
    private func resolvedComparatorElementType(
        of type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let comparatorFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Comparator"),
        ]
        var visited: Set<SymbolID> = []
        return resolvedComparatorElementType(
            of: type,
            comparatorFQName: comparatorFQName,
            sema: sema,
            visited: &visited
        )
    }

    private func resolvedComparatorElementType(
        of type: TypeID,
        comparatorFQName: [InternedString],
        sema: SemaModule,
        visited: inout Set<SymbolID>
    ) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(type)
        switch sema.types.kind(of: nonNullType) {
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol),
                  symbol.fqName == comparatorFQName,
                  let firstArg = classType.args.first
            else {
                return nil
            }
            return switch firstArg {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }

        case let .intersection(parts):
            for part in parts {
                if let elementType = resolvedComparatorElementType(
                    of: part,
                    comparatorFQName: comparatorFQName,
                    sema: sema,
                    visited: &visited
                ) {
                    return elementType
                }
            }
            return nil

        case let .typeParam(typeParam):
            guard visited.insert(typeParam.symbol).inserted else {
                return nil
            }
            for bound in sema.symbols.typeParameterUpperBounds(for: typeParam.symbol) {
                if let elementType = resolvedComparatorElementType(
                    of: bound,
                    comparatorFQName: comparatorFQName,
                    sema: sema,
                    visited: &visited
                ) {
                    return elementType
                }
            }
            return nil

        default:
            return nil
        }
    }

    private func resolvedCollectionElementType(
        receiverID: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let directElementType = getCollectionElementType(receiverType, sema: sema, interner: interner)
        if directElementType != sema.types.anyType {
            return directElementType
        }
        guard let receiverExpr = ctx.ast.arena.expr(receiverID) else {
            return directElementType
        }
        switch receiverExpr {
        case let .call(calleeExpr, _, args, _):
            guard let callee = ctx.ast.arena.expr(calleeExpr),
                  case let .nameRef(name, _) = callee
            else {
                return directElementType
            }
            let sequenceOfName = interner.intern("sequenceOf")
            if name == sequenceOfName {
                let elementTypes = args.map { argument in
                    driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: nil)
                }
                guard !elementTypes.isEmpty else {
                    return sema.types.anyType
                }
                let hasNullableElement = elementTypes.contains { inferredType in
                    inferredType == sema.types.nullableNothingType
                        || sema.types.makeNonNullable(inferredType) != inferredType
                }
                let concreteTypes = elementTypes.compactMap { inferredType -> TypeID? in
                    if inferredType == sema.types.nullableNothingType {
                        return nil
                    }
                    return sema.types.makeNonNullable(inferredType)
                }
                let baseType = concreteTypes.isEmpty ? sema.types.anyType : sema.types.lub(concreteTypes)
                return hasNullableElement ? sema.types.makeNullable(baseType) : baseType
            }
            let generateSequenceName = interner.intern("generateSequence")
            if name == generateSequenceName, let firstArg = args.first {
                let firstArgType = driver.inferExpr(firstArg.expr, ctx: ctx, locals: &locals, expectedType: nil)
                if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(firstArgType)),
                   functionType.params.isEmpty
                {
                    return sema.types.makeNonNullable(functionType.returnType)
                }
                return firstArgType
            }
            return directElementType
        default:
            return directElementType
        }
    }

    private func isMapLikeCollectionType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol) && classType.args.count == 2
    }

    private func isConcreteListLikeType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && classType.args.count == 1
    }

    private func makeSyntheticPairType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        firstType: TypeID,
        secondType: TypeID
    ) -> TypeID {
        let pairFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Pair"),
        ]
        let pairSymbol = symbols.lookup(fqName: pairFQName) ?? symbols.lookupByShortName(interner.intern("Pair")).first
        guard let pairSym = pairSymbol else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: pairSym,
            args: [.invariant(firstType), .invariant(secondType)],
            nullability: .nonNull
        )))
    }

    // MARK: - Numeric companion static functions (STDLIB-NUM-130)

    /// Returns `(returnType, externalLinkName)` for built-in primitive companion static functions
    /// like `Double.fromBits(bits: Long)` and `Float.fromBits(bits: Int)`.
    private func numericCompanionFunction(
        typeName: String,
        memberName: String,
        sema: SemaModule
    ) -> (TypeID, String)? {
        let types = sema.types
        switch (typeName, memberName) {
        case ("Double", "fromBits"):
            return (types.doubleType, "kk_double_fromBits")
        case ("Float", "fromBits"):
            return (types.floatType, "kk_float_fromBits")
        default:
            return nil
        }
    }

    // MARK: - Numeric companion constants (STDLIB-153)

    private func numericCompanionConstant(
        typeName: String,
        memberName: String,
        sema: SemaModule
    ) -> (TypeID, KIRExprKind)? {
        let types = sema.types
        switch (typeName, memberName) {
        // Int (32-bit in Kotlin)
        case ("Int", "MAX_VALUE"): return (types.intType, .intLiteral(Int64(Int32.max)))
        case ("Int", "MIN_VALUE"): return (types.intType, .intLiteral(Int64(Int32.min)))
        case ("Int", "SIZE_BITS"): return (types.intType, .intLiteral(32))
        case ("Int", "SIZE_BYTES"): return (types.intType, .intLiteral(4))
        // Long (64-bit)
        case ("Long", "MAX_VALUE"): return (types.longType, .longLiteral(Int64.max))
        case ("Long", "MIN_VALUE"): return (types.longType, .longLiteral(Int64.min))
        case ("Long", "SIZE_BITS"): return (types.intType, .intLiteral(64))
        case ("Long", "SIZE_BYTES"): return (types.intType, .intLiteral(8))
        // Short
        case ("Short", "MAX_VALUE"): return (types.intType, .intLiteral(Int64(Int16.max)))
        case ("Short", "MIN_VALUE"): return (types.intType, .intLiteral(Int64(Int16.min)))
        // Byte
        case ("Byte", "MAX_VALUE"): return (types.intType, .intLiteral(Int64(Int8.max)))
        case ("Byte", "MIN_VALUE"): return (types.intType, .intLiteral(Int64(Int8.min)))
        // Float
        case ("Float", "MAX_VALUE"): return (types.floatType, .floatLiteral(Double(Float.greatestFiniteMagnitude)))
        case ("Float", "MIN_VALUE"): return (types.floatType, .floatLiteral(Double(Float.leastNonzeroMagnitude)))
        case ("Float", "NaN"): return (types.floatType, .floatLiteral(Double(Float.nan)))
        case ("Float", "POSITIVE_INFINITY"): return (types.floatType, .floatLiteral(Double(Float.infinity)))
        case ("Float", "NEGATIVE_INFINITY"): return (types.floatType, .floatLiteral(Double(-Float.infinity)))
        // Double
        case ("Double", "MAX_VALUE"): return (types.doubleType, .doubleLiteral(Double.greatestFiniteMagnitude))
        case ("Double", "MIN_VALUE"): return (types.doubleType, .doubleLiteral(Double.leastNonzeroMagnitude))
        case ("Double", "NaN"): return (types.doubleType, .doubleLiteral(Double.nan))
        case ("Double", "POSITIVE_INFINITY"): return (types.doubleType, .doubleLiteral(Double.infinity))
        case ("Double", "NEGATIVE_INFINITY"): return (types.doubleType, .doubleLiteral(-Double.infinity))
        default: return nil
        }
    }

    /// Returns true if `receiverType` conforms to Closeable,
    /// so that `.use {}` is only treated as a scope function on Closeable receivers.
    /// Note: AutoCloseable is registered as a typealias to Closeable (see
    /// HeaderHelpers+SyntheticCloseableStubs.swift), so checking Closeable alone
    /// covers both Closeable and AutoCloseable receivers.
    ///
    /// As a fallback for synthetic IO types (BufferedReader, BufferedWriter, InputStream,
    /// OutputStream) that implement Closeable through the nominal supertype chain registered
    /// by registerSyntheticFileIOStubs, we also accept any class type whose class symbol
    /// has a `close()` member function registered with no parameters — this ensures that
    /// `file.bufferedReader().use { }` and similar patterns resolve correctly.
    private func isCloseableReceiver(_ receiverType: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let closeableType = sema.types.closeableTypeID else {
            return false
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        if sema.types.isSubtype(nonNullReceiver, closeableType) {
            return true
        }
        // STDLIB-030-BUG-01: When the receiver is a type parameter (e.g. `T` in
        // `fun <T : AutoCloseable> useIt(t: T)`), the general isSubtype now traverses
        // upper bounds (see Subtyping.swift). As an explicit fallback, also check directly:
        // if any registered upper bound of T is a subtype of Closeable, accept it.
        if case let .typeParam(typeParam) = sema.types.kind(of: nonNullReceiver) {
            let upperBounds = sema.symbols.typeParameterUpperBounds(for: typeParam.symbol)
            for bound in upperBounds {
                let nonNullBound = sema.types.makeNonNullable(bound)
                if sema.types.isSubtype(nonNullBound, closeableType) {
                    return true
                }
            }
        }
        // Fallback: check if the class explicitly declares Closeable or AutoCloseable
        // in its registered supertype list.  This handles synthetic IO types
        // (BufferedReader, BufferedWriter, InputStream, OutputStream) whose supertypes
        // are registered via registerSyntheticFileIOStubs / setDirectSupertypes, without
        // accidentally treating every class that happens to define close() as Closeable.
        guard let closeableSymbol = sema.types.closeableInterfaceSymbol,
              case let .classType(classType) = sema.types.kind(of: nonNullReceiver)
        else {
            return false
        }
        let directSupertypes = sema.symbols.directSupertypes(for: classType.classSymbol)
        return directSupertypes.contains(closeableSymbol)
    }

    // MARK: - Result helpers (STDLIB-590)

    /// Extract the element type T from a Result<out T> receiver type.
    private func extractResultElementType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNull),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.fqName == knownNames.kotlinResultFQName,
              let firstArg = classType.args.first
        else {
            return nil
        }
        switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            return type
        case .star:
            return sema.types.anyType
        }
    }

    /// Look up a synthetic Result member function by name.
    private func lookupResultMember(
        _ name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let memberFQName = knownNames.kotlinResultFQName + [interner.intern(name)]
        return sema.symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let sym = sema.symbols.symbol(symbolID) else { return false }
            return sym.kind == .function && sym.flags.contains(.synthetic)
        })
    }

    /// Construct a Result<T> type from an element type.
    private func makeResultType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let resultClassSymbol = sema.symbols.lookup(fqName: knownNames.kotlinResultFQName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: resultClassSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func tryBindThreadLocalGetOrSetFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard interner.resolve(calleeName) == "getOrSet",
              args.count == 1,
              let threadLocalSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("java"),
                  interner.intern("lang"),
                  interner.intern("ThreadLocal"),
              ]),
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              receiverClassType.classSymbol == threadLocalSymbol
        else {
            return nil
        }

        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard let chosen = visibleCandidates.first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_thread_local_getOrSet"
        }),
        let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        let elementType: TypeID = if let arg = receiverClassType.args.first {
            switch arg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                inner
            case .star:
                sema.types.nullableAnyType
            }
        } else {
            sema.types.nullableAnyType
        }

        let defaultLambdaType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: elementType,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: defaultLambdaType
        )

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution: [TypeVarID: TypeID] = if let typeParameterSymbol = signature.typeParameterSymbols.first,
                                                   let typeVar = typeVarBySymbol[typeParameterSymbol]
        {
            [typeVar: elementType]
        } else {
            [:]
        }

        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: ResolvedCall(
                chosenCallee: chosen,
                substitutedTypeArguments: substitution,
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func tryBindMapGetOrElseFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        guard calleeName == knownNames.getOrElse,
              args.count == 2,
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol),
              knownNames.isMapLikeSymbol(receiverSymbol),
              receiverClassType.args.count >= 2
        else {
            return nil
        }

        let valueType: TypeID = switch receiverClassType.args[1] {
        case let .invariant(inner), let .out(inner), let .in(inner):
            inner
        case .star:
            sema.types.anyType
        }

        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        let defaultLambdaType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: valueType,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(
            args[1].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: defaultLambdaType
        )

        let fallbackCallee = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
            knownNames.getOrElse,
        ]).first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_map_getOrElse"
        })

        if let fallbackCallee {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: fallbackCallee,
                    substitutedTypeArguments: [],
                    parameterMapping: [0: 0, 1: 1]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
        }

        let finalType = safeCall ? sema.types.makeNullable(valueType) : valueType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func tryBindReadWriteLockReadFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard interner.resolve(calleeName) == "read",
              args.count == 1,
              let lockSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("java"),
                  interner.intern("util"),
                  interner.intern("concurrent"),
                  interner.intern("locks"),
                  interner.intern("ReentrantReadWriteLock"),
              ]),
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              receiverClassType.classSymbol == lockSymbol
        else {
            return nil
        }

        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        let chosen = visibleCandidates.first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_reentrant_read_write_lock_read"
        }) ?? sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("concurrent"),
            interner.intern("read"),
        ]).first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_reentrant_read_write_lock_read"
        })

        guard let chosen,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        let inferredActionType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        let resultElementType: TypeID
        if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(inferredActionType)) {
            resultElementType = functionType.returnType
        } else {
            resultElementType = sema.types.anyType
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution: [TypeVarID: TypeID] = if let typeParameterSymbol = signature.typeParameterSymbols.first,
                                                   let typeVar = typeVarBySymbol[typeParameterSymbol]
        {
            [typeVar: resultElementType]
        } else {
            [:]
        }

        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: ResolvedCall(
                chosenCallee: chosen,
                substitutedTypeArguments: substitution,
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func tryBindComparatorMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard let comparatorElementType = resolvedComparatorElementType(
                  of: receiverType,
                  sema: sema,
                  interner: interner
              )
        else {
            return nil
        }

        let calleeStr = interner.resolve(calleeName)
        if args.count == 2, ["thenBy", "thenByDescending"].contains(calleeStr) {
            let keyComparatorType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            guard let keyType = resolvedComparatorElementType(
                of: keyComparatorType,
                sema: sema,
                interner: interner
            ) else {
                return nil
            }
            let expectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [comparatorElementType],
                returnType: keyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedLambdaType
            )

            let comparatorMemberFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("Comparator"),
                calleeName,
            ]
            let externalLinkName = switch calleeStr {
            case "thenBy":
                "kk_comparator_then_by_comparator_selector"
            default:
                "kk_comparator_then_by_descending_comparator_selector"
            }
            guard let chosen = sema.symbols.lookupAll(fqName: comparatorMemberFQName).first(where: { candidate in
                sema.symbols.externalLinkName(for: candidate) == externalLinkName
            }) else {
                return nil
            }

            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [comparatorElementType, keyType],
                    parameterMapping: [0: 0, 1: 1]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))

            let resultType = sema.types.makeNonNullable(receiverType)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        guard args.count == 1 else {
            return nil
        }

        let expectedLambdaType: TypeID
        switch calleeStr {
        case "thenBy", "thenByDescending":
            expectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [comparatorElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
        case "thenComparator", "thenDescending":
            expectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [comparatorElementType, comparatorElementType],
                returnType: sema.types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
        default:
            return nil
        }

        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedLambdaType
        )

        let comparatorMemberFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Comparator"),
            calleeName,
        ]
        guard let chosen = sema.symbols.lookupAll(fqName: comparatorMemberFQName).first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return sema.symbols.symbol(candidate)?.flags.contains(.synthetic) == true
                && signature.parameterTypes.count == 1
        }) else {
            return nil
        }

        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))

        let resultType = sema.types.makeNonNullable(receiverType)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func bindKClassFindAssociatedObjectCall(
        _ id: ExprID,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        for arg in args {
            _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }

        let functionFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("findAssociatedObject"),
        ]
        if let chosen = sema.symbols.lookupAll(fqName: functionFQName).first(where: { candidate in
            sema.symbols.symbol(candidate)?.kind == .function
        }) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: explicitTypeArgs,
                    parameterMapping: [:]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }

        let nullableAnyType = sema.types.makeNullable(sema.types.anyType)
        sema.bindings.bindExprType(id, type: nullableAnyType)
        return nullableAnyType
    }
}
