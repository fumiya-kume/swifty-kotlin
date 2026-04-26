import Foundation

extension CallTypeChecker {
    func tryRegexMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver else {
            return nil
        }
        let regexSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Regex"),
        ])
        let matchResultSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("MatchResult"),
        ])
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let memberName = interner.resolve(calleeName)

        if let regexSymbol {
            let regexType = sema.types.make(.classType(ClassType(
                classSymbol: regexSymbol,
                args: [],
                nullability: .nonNull
            )))
            if nonNullReceiverType == regexType {
                let listMatchResultType: TypeID
                if let listSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]), let matchResultSymbol {
                    let matchResultType = sema.types.make(.classType(ClassType(
                        classSymbol: matchResultSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    listMatchResultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.out(matchResultType)],
                        nullability: .nonNull
                    )))
                } else {
                    listMatchResultType = sema.types.anyType
                }
                let resultType: TypeID? = switch (memberName, args.count) {
                case ("find", 1):
                    matchResultSymbol.map {
                        sema.types.makeNullable(sema.types.make(.classType(ClassType(
                            classSymbol: $0,
                            args: [],
                            nullability: .nonNull
                        ))))
                    } ?? sema.types.anyType
                case ("findAll", 1):
                    listMatchResultType
                case ("pattern", 0):
                    sema.types.stringType
                default:
                    nil
                }
                if let resultType {
                    if args.indices.contains(0) {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        if let matchResultSymbol {
            let matchResultType = sema.types.make(.classType(ClassType(
                classSymbol: matchResultSymbol,
                args: [],
                nullability: .nonNull
            )))
            if nonNullReceiverType == matchResultType {
                let nullableMatchResultType = sema.types.makeNullable(matchResultType)
                let resultType: TypeID? = switch (memberName, args.count) {
                case ("value", 0):
                    sema.types.stringType
                case ("groupValues", 0):
                    if let listSymbol = sema.symbols.lookup(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("List"),
                    ]) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.out(sema.types.stringType)],
                            nullability: .nonNull
                        )))
                    } else {
                        sema.types.anyType
                    }
                // STDLIB-REGEX-095: MatchResult complete implementation
                case ("component1", 0), ("component2", 0):
                    sema.types.stringType
                case ("next", 0):
                    nullableMatchResultType
                default:
                    nil
                }
                if let resultType {
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        return nil
    }

    func tryStringMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver else {
            return nil
        }
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard sema.types.isSubtype(sema.types.makeNonNullable(receiverType), sema.types.stringType) else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        let regexType = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Regex"),
        ]).map {
            sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
        }
        let listStringType: TypeID = if let listSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]) {
            sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(sema.types.stringType)],
                nullability: .nonNull
            )))
        } else {
            sema.types.anyType
        }

        let resultType: TypeID? = switch (memberName, args.count) {
        case ("toRegex", 0):
            regexType ?? sema.types.anyType
        case ("indexOf", 1), ("indexOf", 2), ("lastIndexOf", 1):
            sema.types.intType
        case ("indexOfFirst", 1), ("indexOfLast", 1):
            sema.types.intType
        case ("lines", 0):
            listStringType
        case ("lineSequence", 0):
            makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.stringType
            )
        case ("asSequence", 0):
            makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.charType
            )
        case ("replaceFirstChar", 1),
             ("trim", 1),
             ("trimStart", 1),
             ("trimEnd", 1):
            sema.types.stringType
        case ("ifBlank", 1), ("ifEmpty", 1):
            sema.types.stringType
        case ("zipWithNext", 1): {
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [charType, charType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ctx.ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            let lambdaType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let bodyType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            let listType: TypeID = if let listSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ]) {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(bodyType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let fqName = [
                interner.intern("kotlin"),
                interner.intern("text"),
                calleeName,
            ]
            if let chosen = sema.symbols.lookupAll(fqName: fqName).first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 1
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
            return listType
        }()
        case ("matches", 1), ("contains", 1):
            sema.types.booleanType
        case ("split", 1):
            listStringType
        case ("replace", 2):
            sema.types.stringType
        // STDLIB-REGEX-094: String.replaceFirst(Regex, String) -> String
        case ("replaceFirst", 2):
            sema.types.stringType
        case ("chunked", 1):
            listStringType
        case ("windowed", 1):
            listStringType
        case ("windowed", 2):
            listStringType
        case ("windowed", 3):
            listStringType
        default:
            nil
        }
        guard let resultType else {
            return nil
        }

        if memberName == "toRegex" {
            sema.bindings.bindExprType(id, type: resultType)
            return safeCall ? sema.types.makeNullable(resultType) : resultType
        }
        let charType = sema.types.charType
        func stringSearchNeedleExpectedType(for argID: ExprID) -> TypeID? {
            if let boundType = sema.bindings.exprTypes[argID] {
                let nonNullBoundType = sema.types.makeNonNullable(boundType)
                if sema.types.isSubtype(nonNullBoundType, charType) {
                    return charType
                }
                if sema.types.isSubtype(nonNullBoundType, sema.types.stringType) {
                    return sema.types.stringType
                }
            }
            guard let expr = ctx.ast.arena.expr(argID) else {
                return nil
            }
            switch expr {
            case .charLiteral:
                return charType
            case .stringLiteral:
                return sema.types.stringType
            default:
                return nil
            }
        }
        if memberName == "indexOf", args.indices.contains(0),
           let expectedType = stringSearchNeedleExpectedType(for: args[0].expr)
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
        }
        if memberName == "indexOf", args.indices.contains(1) {
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        }
        if memberName == "lastIndexOf", args.indices.contains(0),
           let expectedType = stringSearchNeedleExpectedType(for: args[0].expr)
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
        }
        if args.indices.contains(0), let regexType {
            let expectedType = memberName == "replace" || memberName == "replaceFirst"
                || memberName == "contains" || memberName == "matches" || memberName == "split"
                ? regexType
                : nil
            if let expectedType {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            }
        }
        if memberName == "indexOfFirst" || memberName == "indexOfLast"
            || memberName == "trim" || memberName == "trimStart" || memberName == "trimEnd"
        {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [charType],
                returnType: sema.types.booleanType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if args.indices.contains(0) {
                if let lambdaExpr = ctx.ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            }
        }
        if (memberName == "replace" || memberName == "replaceFirst"), args.indices.contains(1) {
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
        }
        if memberName == "replaceFirstChar", args.indices.contains(0) {
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [charType],
                returnType: charType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ctx.ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            let fqName = [
                interner.intern("kotlin"),
                interner.intern("text"),
                calleeName,
            ]
            if let chosen = sema.symbols.lookup(fqName: fqName) {
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
        }
        if (memberName == "ifBlank" || memberName == "ifEmpty"), args.indices.contains(0) {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.stringType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ctx.ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
        }
        if memberName == "chunked", args.indices.contains(0) {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        }
        if memberName == "windowed" {
            if args.indices.contains(0) {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            }
            if args.indices.contains(1) {
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            }
            if args.indices.contains(2) {
                _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
            }
        }

        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryFileMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver else {
            return nil
        }
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
              let owner = sema.symbols.symbol(classType.classSymbol),
              owner.fqName.count == 3,
              interner.resolve(owner.fqName[0]) == "java",
              interner.resolve(owner.fqName[1]) == "io",
              interner.resolve(owner.fqName[2]) == "File"
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        guard memberName == "appendText", args.count == 1 else {
            return nil
        }

        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
        let finalType = safeCall ? sema.types.makeNullable(sema.types.unitType) : sema.types.unitType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryCollectionMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        let memberName = interner.resolve(calleeName)
        let isArrayReceiver = isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isIterableWindowedTransformCall: Bool = {
            guard memberName == "windowed",
                  (2...4).contains(args.count),
                  isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner),
                  let lastArgExpr = args.last?.expr,
                  let lastArgExprNode = ctx.ast.arena.expr(lastArgExpr)
            else {
                return false
            }
            return lastArgExprNode.isLambdaOrCallableRef
        }()
        let isIterableChunkedTransformCall: Bool = {
            guard memberName == "chunked",
                  args.count == 2,
                  isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner),
                  let lastArgExpr = args.last?.expr,
                  let lastArgExprNode = ctx.ast.arena.expr(lastArgExpr)
            else {
                return false
            }
            return lastArgExprNode.isLambdaOrCallableRef
        }()
        // Allow arrays to fall through to collection fallback only when
        // tryArrayMemberFallback does not handle the member (isSupportedArrayMember returns false).
        guard !isClassNameReceiver,
              !(isArrayReceiver && isSupportedArrayMember(memberName)),
              isCollectionLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
                || isIterableWindowedTransformCall
                || isIterableChunkedTransformCall
        else {
            return nil
        }

        let isMapReceiver = isMapLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isSetReceiver = isSetLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableListReceiver = isMutableListCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableSetReceiver = isMutableSetCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableMapReceiver = isMutableMapCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isListReceiver = isConcreteListLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isSequenceReceiver = isSequenceLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        guard isSupportedCollectionFallbackMember(
            calleeName,
            isListReceiver: isListReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isMutableListReceiver: isMutableListReceiver,
            isMutableSetReceiver: isMutableSetReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            interner: interner
        ),
        isValidCollectionFallbackArity(
            calleeName,
            argCount: args.count,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            isMutableSetReceiver: isMutableSetReceiver,
            isMutableListReceiver: isMutableListReceiver,
            interner: interner
        )
        else {
            return nil
        }

        // Provide contextual function type for collection HOF lambda inference.
        let receiverElementType = collectionFallbackElementType(receiverID: receiverID, sema: sema, interner: interner)
        if let expectation = collectionFallbackLambdaExpectation(
            memberName: calleeName,
            argCount: args.count,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            args: args,
            ctx: ctx,
            interner: interner,
            sema: sema
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }

        if isCollectionReturningMember(
            calleeName,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            interner: interner
        ) {
            sema.bindings.markCollectionExpr(id)
        }

        if let fallbackCallee = resolveCollectionFallbackCallee(
            memberName: calleeName,
            receiverID: receiverID,
            argExprs: args.map(\.expr),
            argCount: args.count,
            ctx: ctx,
            sema: sema,
            interner: interner
        ) {
            if let invalidFallbackType = validateCollectionFallbackCallee(
                fallbackCallee,
                exprID: id,
                calleeName: calleeName,
                safeCall: safeCall,
                receiverID: receiverID,
                ctx: ctx
            ) {
                return invalidFallbackType
            }
            let parameterMapping = buildCollectionFallbackParameterMapping(
                memberName: calleeName,
                args: args,
                fallbackCallee: fallbackCallee,
                sema: sema,
                interner: interner
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: fallbackCallee,
                    substitutedTypeArguments: [],
                    parameterMapping: parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
        }

        var resultType = collectionFallbackResultType(
            memberName: calleeName,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isSequenceReceiver: isSequenceReceiver,
            args: args,
            ctx: ctx,
            sema: sema,
            interner: interner
        )
        // When the receiver is Sequence, sequence-returning operations (map,
        // filter, etc.) should return Sequence<E> so the KIR builder's
        // sequence HOF handler recognises chained calls (STDLIB-471).
        if isSequenceReceiver,
           isCollectionReturningMember(calleeName, isMapReceiver: false, isSetReceiver: false, interner: interner),
           resultType == sema.types.anyType
        {
            resultType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func validateCollectionFallbackCallee(
        _ fallbackCallee: SymbolID,
        exprID: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverID: ExprID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let diagnosticRange = ctx.ast.arena.exprRange(exprID) ?? ctx.ast.arena.exprRange(receiverID)

        if let diagnosticRange,
           let projectionDiagnostic = makeProjectionViolationDiagnostic(
            candidates: [fallbackCallee],
            receiverType: receiverType,
            calleeName: calleeName,
            range: diagnosticRange,
            sema: sema,
            interner: interner
        ) {
            ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
            let invalidType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
            sema.bindings.bindExprType(exprID, type: invalidType)
            return invalidType
        }

        guard let signature = sema.symbols.functionSignature(for: fallbackCallee),
              signature.classTypeParameterCount > 0,
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        else {
            return nil
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        let receiverTypeParamCount = min(
            signature.classTypeParameterCount,
            receiverClassType.args.count,
            signature.typeParameterSymbols.count
        )

        for index in 0 ..< receiverTypeParamCount {
            let concreteType: TypeID = switch receiverClassType.args[index] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let typeParamSymbol = signature.typeParameterSymbols[index]
            if let typeVar = typeVarBySymbol[typeParamSymbol] {
                substitution[typeVar] = concreteType
            }
        }

        for index in 0 ..< receiverTypeParamCount {
            let typeParamSymbol = signature.typeParameterSymbols[index]
            guard let typeVar = typeVarBySymbol[typeParamSymbol],
                  let substitutedType = substitution[typeVar]
            else {
                continue
            }

            let signatureUpperBounds: [TypeID] = if index < signature.typeParameterUpperBoundsList.count {
                signature.typeParameterUpperBoundsList[index]
            } else {
                []
            }
            let symbolUpperBounds = sema.symbols.typeParameterUpperBounds(for: typeParamSymbol)
            let upperBounds = signatureUpperBounds + symbolUpperBounds.filter { bound in
                !signatureUpperBounds.contains(bound)
            }

            for bound in upperBounds {
                let substitutedBound = sema.types.substituteTypeParameters(
                    in: bound,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                if !sema.types.isSubtype(substitutedType, substitutedBound) {
                    if let diagnosticRange {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: diagnosticRange
                        )
                    }
                    let invalidType = safeCall ? sema.types.makeNullable(sema.types.anyType) : sema.types.anyType
                    sema.bindings.bindExprType(exprID, type: invalidType)
                    return invalidType
                }
            }
        }

        return nil
    }

    private func buildCollectionFallbackParameterMapping(
        memberName: InternedString,
        args: [CallArgument],
        fallbackCallee: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [Int: Int] {
        // Build a parameter mapping so that user-provided arguments are correctly
        // assigned to the right parameter slots. Without this, normalizedCallArguments
        // treats all parameters with hasDefault=true as using their default values,
        // ignoring user-provided args entirely.
        guard !args.isEmpty else {
            return [:]
        }
        guard let signature = sema.symbols.functionSignature(for: fallbackCallee) else {
            return [:]
        }
        let paramCount = signature.parameterTypes.count
        // Build a name->index map from the parameter symbols.
        var paramNameToIndex: [InternedString: Int] = [:]
        for (paramIndex, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            if let paramSymbolInfo = sema.symbols.symbol(paramSymbol) {
                let paramName = paramSymbolInfo.name
                if paramName != .invalid {
                    paramNameToIndex[paramName] = paramIndex
                }
            }
        }
        var mapping: [Int: Int] = [:]
        var positionalParamIndex = 0
        for (argIndex, arg) in args.enumerated() {
            if let label = arg.label, let paramIndex = paramNameToIndex[label] {
                // Named argument: map to the named parameter
                mapping[argIndex] = paramIndex
            } else {
                // Positional argument: advance to next unoccupied parameter index
                // (skip any params that are already claimed by named args)
                while positionalParamIndex < paramCount
                    && mapping.values.contains(positionalParamIndex)
                {
                    positionalParamIndex += 1
                }
                if positionalParamIndex < paramCount {
                    mapping[argIndex] = positionalParamIndex
                    positionalParamIndex += 1
                }
            }
        }
        return mapping
    }

    private func resolveCollectionFallbackCallee(
        memberName: InternedString,
        receiverID: ExprID,
        argExprs: [ExprID] = [],
        argCount: Int,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard let root = driver.helpers.nominalSymbol(of: sema.types.makeNonNullable(receiverType), types: sema.types) else {
            return nil
        }
        var queue: [SymbolID] = [root]
        var visited: Set<SymbolID> = []
        while !queue.isEmpty {
            let owner = queue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [memberName]
            var allCandidates = sema.symbols.lookupAll(fqName: memberFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sema.symbols.functionSignature(for: candidate) != nil
                else {
                    return false
                }
                return true
            }
            for candidate in sema.symbols.lookupByShortName(memberName) {
                guard !allCandidates.contains(candidate),
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sema.symbols.functionSignature(for: candidate) != nil
                else {
                    continue
                }
                allCandidates.append(candidate)
            }
            // STDLIB-214: For slice(IntRange) vs slice(Iterable<Int>), prefer the
            // IntRange overload (kk_list_slice) when the first argument is a range expression,
            // and the Iterable overload (kk_list_slice_iterable) otherwise.
            if argCount == 1,
               allCandidates.count > 1,
               let firstArgExpr = argExprs.first,
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_list_slice" }),
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_list_slice_iterable" })
            {
                let isRangeArg = sema.bindings.isRangeExpr(firstArgExpr)
                let targetLinkName = isRangeArg ? "kk_list_slice" : "kk_list_slice_iterable"
                if let sliceMatch = allCandidates.first(where: { candidate in
                    sema.symbols.externalLinkName(for: candidate) == targetLinkName
                }) {
                    return sliceMatch
                }
            }
            if memberName == interner.intern("binarySearch") {
                let hasLambdaArg = argExprs.first.map { sema.bindings.isCollectionHOFLambdaExpr($0) } ?? false
                if argCount == 1,
                   hasLambdaArg,
                   let compareMatch = allCandidates.first(where: { candidate in
                       sema.symbols.externalLinkName(for: candidate) == "kk_list_binarySearch_compare"
                   })
                {
                    return compareMatch
                }
                if argCount >= 2,
                   let comparatorMatch = allCandidates.first(where: { candidate in
                       sema.symbols.externalLinkName(for: candidate) == "kk_list_binarySearch_comparator"
                   })
                {
                    return comparatorMatch
                }
            }

        let lastArgIsFunctionLike: Bool = if let lastExpr = argExprs.last,
                                             let lastExprNode = ctx.ast.arena.expr(lastExpr) {
            lastExprNode.isLambdaOrCallableRef
        } else {
            false
        }
        if lastArgIsFunctionLike,
           let lambdaMatch = allCandidates.first(where: { candidate in
               guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
               guard sig.parameterTypes.count == argCount,
                     let lastParamType = sig.parameterTypes.last
               else {
                   return false
               }
               switch sema.types.kind(of: sema.types.makeNonNullable(lastParamType)) {
               case .functionType:
                   return true
               default:
                   return false
               }
           }) {
            return lambdaMatch
        }
        // Prefer the overload whose parameter count matches the call-site
        // argument count so that e.g. windowed(3, 2, true) resolves to the
        // 3-param overload (kk_list_windowed_partial) instead of the 2-param
        // one (kk_list_windowed).
        if let exactMatch = allCandidates.first(where: { candidate in
            guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
            return sig.parameterTypes.count == argCount
        }) {
            return exactMatch
        }
        if let first = allCandidates.first {
            return first
        }
        queue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }

    func isSupportedCollectionFallbackMember(
        _ memberName: InternedString,
        isListReceiver: Bool,
        isSequenceReceiver: Bool,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isMutableListReceiver: Bool,
        isMutableSetReceiver: Bool = false,
        isMutableMapReceiver: Bool,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let collectionMembers: Set = [
            knownNames.size,
            knownNames.isEmpty,
            interner.intern("get"),
            interner.intern("contains"),
            interner.intern("containsAll"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("indexOf"),
            interner.intern("lastIndexOf"),
            interner.intern("indexOfFirst"),
            interner.intern("indexOfLast"),
            interner.intern("count"),
            interner.intern("iterator"),
            interner.intern("map"),
            interner.intern("filter"),
            interner.intern("filterNot"),
            interner.intern("mapNotNull"),
            interner.intern("filterNotNull"),
            interner.intern("filterTo"),
            interner.intern("filterNotTo"),
            interner.intern("mapTo"),
            interner.intern("flatMapTo"),
            interner.intern("mapNotNullTo"),
            interner.intern("mapIndexedTo"),
            interner.intern("mapIndexedNotNullTo"),
            interner.intern("flatMapIndexedTo"),
            interner.intern("filterIsInstanceTo"),
            interner.intern("filterIndexedTo"),
            interner.intern("filterNotNullTo"),
            interner.intern("forEach"),
            interner.intern("flatMap"),
            interner.intern("any"),
            interner.intern("none"),
            interner.intern("all"),
            interner.intern("fold"),
            interner.intern("foldRight"),
            interner.intern("foldIndexed"),
            interner.intern("foldRightIndexed"),
            interner.intern("reduce"),
            interner.intern("reduceRight"),
            interner.intern("reduceOrNull"),
            interner.intern("reduceIndexed"),
            interner.intern("reduceIndexedOrNull"),
            interner.intern("scan"),
            interner.intern("scanIndexed"),
            interner.intern("runningFold"),
            interner.intern("runningFoldIndexed"),
            interner.intern("runningReduce"),
            interner.intern("runningReduceIndexed"),
            interner.intern("scanReduce"),
            interner.intern("groupBy"),
            interner.intern("groupingBy"),
            interner.intern("sortedBy"),
            interner.intern("find"),
            interner.intern("associateBy"),
            interner.intern("associateWith"),
            interner.intern("associate"),
            interner.intern("associateTo"),
            interner.intern("associateByTo"),
            interner.intern("associateWithTo"),
            interner.intern("groupByTo"),
            interner.intern("zip"),
            interner.intern("unzip"),
            interner.intern("withIndex"),
            interner.intern("forEachIndexed"),
            interner.intern("mapIndexed"),
            interner.intern("sumOf"),
            interner.intern("maxOrNull"),
            interner.intern("minOrNull"),
            interner.intern("onEach"),
            interner.intern("onEachIndexed"),
            interner.intern("asSequence"),
            interner.intern("asIterable"),
            interner.intern("toList"),
            interner.intern("toCollection"),
            interner.intern("toTypedArray"),
            interner.intern("toIntArray"),
            interner.intern("toLongArray"),
            interner.intern("toByteArray"),
            interner.intern("toUByteArray"),
            interner.intern("toUShortArray"),
            interner.intern("toUIntArray"),
            interner.intern("toULongArray"),
            interner.intern("take"),
            interner.intern("drop"),
            interner.intern("reversed"),
            interner.intern("asReversed"),
            interner.intern("sorted"),
            interner.intern("shuffled"),
            interner.intern("distinct"),
            interner.intern("distinctBy"),
            interner.intern("flatten"),
            interner.intern("chunked"),
            interner.intern("windowed"),
            interner.intern("sortedDescending"),
            interner.intern("sortedByDescending"),
            interner.intern("sortedWith"),
            interner.intern("partition"),
            interner.intern("filterIsInstance"),
            interner.intern("takeWhile"),
            interner.intern("dropWhile"),
            interner.intern("firstOrNull"),
            interner.intern("lastOrNull"),
            interner.intern("singleOrNull"),
            interner.intern("joinToString"),
            interner.intern("elementAt"),
            interner.intern("single"),
            interner.intern("toMutableList"),
            interner.intern("sum"),
            interner.intern("average"),
        ]
        let setOnlyMembers: Set = [
            interner.intern("intersect"),
            interner.intern("union"),
            interner.intern("subtract"),
        ]
        let listOnlyMembers: Set = [
            interner.intern("subList"),
            interner.intern("slice"),
            interner.intern("getOrNull"),
            interner.intern("elementAtOrNull"),
            interner.intern("binarySearch"),
            interner.intern("binarySearchBy"),
        ]
        let collectionSpecificMembers: Set = [
            interner.intern("firstOrNull"),
            interner.intern("lastOrNull"),
            interner.intern("singleOrNull"),
        ]
        let mutableListOnlyMembers: Set = [
            interner.intern("sort"),
            interner.intern("sortBy"),
            interner.intern("sortByDescending"),
        ]
        let mutableCollectionMembers: Set = [
            interner.intern("addAll"),
            interner.intern("removeAll"),
            interner.intern("retainAll"),
        ]
        let mapOnlyMembers: Set = [
            interner.intern("containsKey"),
            interner.intern("containsValue"),
            interner.intern("mapValues"),
            interner.intern("mapKeys"),
            interner.intern("filterKeys"),
            interner.intern("filterValues"),
            knownNames.getValue,
            knownNames.getOrDefault,
            interner.intern("plus"),
            interner.intern("minus"),
        ]
        if listOnlyMembers.contains(memberName) {
            return isListReceiver
        }
        if collectionSpecificMembers.contains(memberName) {
            return isListReceiver || isSetReceiver || isSequenceReceiver
        }
        if memberName == knownNames.getOrElse {
            return isListReceiver || isMapReceiver
        }
        if memberName == interner.intern("elementAtOrElse") {
            return isListReceiver
        }
        if mapOnlyMembers.contains(memberName) {
            return isMapReceiver
        }
        if setOnlyMembers.contains(memberName) {
            return isSetReceiver
        }
        if mutableListOnlyMembers.contains(memberName) {
            return isMutableListReceiver
        }
        if mutableCollectionMembers.contains(memberName) {
            return isMutableListReceiver || isMutableSetReceiver
        }
        if memberName == knownNames.getOrPut || memberName == knownNames.putAll {
            return isMutableMapReceiver
        }
        if memberName == interner.intern("flatMapIndexed") {
            return isSequenceReceiver
        }
        if memberName == interner.intern("requireNoNulls") {
            return isSequenceReceiver
        }
        return collectionMembers.contains(memberName)
    }

    func isCollectionReturningMember(
        _ memberName: InternedString,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        interner: StringInterner
    ) -> Bool {
        let collectionReturningMembers: Set = [
            interner.intern("asSequence"), interner.intern("asIterable"), interner.intern("map"), interner.intern("filter"), interner.intern("filterNot"), interner.intern("mapNotNull"), interner.intern("filterNotNull"), interner.intern("requireNoNulls"),
            interner.intern("filterTo"), interner.intern("filterNotTo"), interner.intern("mapTo"), interner.intern("flatMapTo"), interner.intern("mapNotNullTo"), interner.intern("filterIsInstanceTo"), interner.intern("mapIndexedTo"), interner.intern("mapIndexedNotNullTo"), interner.intern("flatMapIndexedTo"),
            interner.intern("flatMap"), interner.intern("flatMapIndexed"), interner.intern("sortedBy"), interner.intern("groupBy"), interner.intern("groupingBy"), interner.intern("associateBy"), interner.intern("associateWith"), interner.intern("associateTo"), interner.intern("associateByTo"), interner.intern("associateWithTo"), interner.intern("groupByTo"), interner.intern("reduceTo"),
            interner.intern("associate"), interner.intern("zip"), interner.intern("toList"), interner.intern("toTypedArray"), interner.intern("take"), interner.intern("drop"), interner.intern("reversed"), interner.intern("asReversed"),
            interner.intern("sorted"), interner.intern("distinct"), interner.intern("distinctBy"), interner.intern("flatten"), interner.intern("chunked"), interner.intern("windowed"), interner.intern("withIndex"), interner.intern("mapIndexed"),
            interner.intern("shuffled"),
            interner.intern("sortedDescending"), interner.intern("sortedByDescending"), interner.intern("sortedWith"),
            interner.intern("onEach"), interner.intern("onEachIndexed"),
            interner.intern("filterIsInstance"),
            interner.intern("toCollection"),
            interner.intern("takeWhile"), interner.intern("dropWhile"),
            interner.intern("subList"), interner.intern("slice"),
            interner.intern("intersect"), interner.intern("union"), interner.intern("subtract"),
            interner.intern("scan"), interner.intern("scanIndexed"),
            interner.intern("runningFold"), interner.intern("runningFoldIndexed"),
            interner.intern("runningReduce"), interner.intern("runningReduceIndexed"),
            interner.intern("scanReduce"),
            interner.intern("toMutableList"),
        ]
        let setReturningMembers: Set = [
            interner.intern("intersect"),
            interner.intern("union"),
            interner.intern("subtract"),
        ]
        if memberName == interner.intern("mapValues") ||
            memberName == interner.intern("mapKeys") ||
            memberName == interner.intern("filterKeys") ||
            memberName == interner.intern("filterValues") ||
            memberName == interner.intern("plus") ||
            memberName == interner.intern("minus")
        {
            return isMapReceiver
        }
        if setReturningMembers.contains(memberName) {
            return isSetReceiver
        }
        return collectionReturningMembers.contains(memberName)
    }

    func isValidCollectionFallbackArity(
        _ memberName: InternedString,
        argCount: Int,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isSequenceReceiver: Bool,
        isMutableMapReceiver: Bool,
        isMutableSetReceiver: Bool = false,
        isMutableListReceiver: Bool,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        switch memberName {
        case knownNames.size, knownNames.isEmpty, interner.intern("iterator"), interner.intern("asSequence"),
             interner.intern("asIterable"),
             interner.intern("toList"), interner.intern("toTypedArray"), interner.intern("reversed"),
            interner.intern("asReversed"), interner.intern("sorted"),
             interner.intern("distinct"), interner.intern("flatten"), interner.intern("withIndex"),
             interner.intern("maxOrNull"), interner.intern("minOrNull"), interner.intern("sortedDescending"), interner.intern("filterIsInstance"),
             interner.intern("firstOrNull"), interner.intern("lastOrNull"), interner.intern("singleOrNull"), interner.intern("sort"),
             interner.intern("toMutableList"), interner.intern("sum"), interner.intern("average"),
             interner.intern("requireNoNulls"):
            return argCount == 0
        case interner.intern("joinToString"):
            return (0 ... 3).contains(argCount)
        case interner.intern("shuffled"):
            return argCount == 0 || argCount == 1
        case interner.intern("filterNotNull"), interner.intern("requireNoNulls"), interner.intern("unzip"), interner.intern("eachCount"):
            return argCount == 0
        case interner.intern("get"), interner.intern("getOrNull"), interner.intern("elementAtOrNull"),
             interner.intern("contains"), interner.intern("containsAll"), interner.intern("indexOf"), interner.intern("lastIndexOf"), interner.intern("indexOfFirst"), interner.intern("indexOfLast"), interner.intern("binarySearch"),
             interner.intern("map"), interner.intern("filter"), interner.intern("filterNot"), interner.intern("mapNotNull"), interner.intern("forEach"), interner.intern("flatMap"), interner.intern("flatMapIndexed"),
             interner.intern("any"), interner.intern("none"), interner.intern("all"),
             interner.intern("groupBy"), interner.intern("groupingBy"), interner.intern("sortedBy"), interner.intern("find"), interner.intern("associateBy"), interner.intern("associateWith"), interner.intern("associate"), interner.intern("reduce"), interner.intern("reduceOrNull"), interner.intern("reduceIndexedOrNull"), interner.intern("runningReduce"), interner.intern("runningReduceIndexed"), interner.intern("scanReduce"), interner.intern("take"), interner.intern("drop"), interner.intern("zip"),
             interner.intern("forEachIndexed"), interner.intern("mapIndexed"), interner.intern("filterIndexed"), interner.intern("sumOf"), interner.intern("chunked"), interner.intern("onEach"), interner.intern("onEachIndexed"),
             interner.intern("sortedByDescending"), interner.intern("sortedWith"), interner.intern("partition"),
             interner.intern("takeWhile"), interner.intern("dropWhile"),
             interner.intern("sortBy"), interner.intern("sortByDescending"), interner.intern("distinctBy"),
             interner.intern("intersect"), interner.intern("union"), interner.intern("subtract"),
             interner.intern("maxByOrNull"), interner.intern("minByOrNull"),
             interner.intern("maxOfOrNull"), interner.intern("minOfOrNull"),
             interner.intern("maxOf"), interner.intern("minOf"),
             interner.intern("maxWith"), interner.intern("maxWithOrNull"),
             interner.intern("minWith"), interner.intern("minWithOrNull"),
             interner.intern("elementAt"):
            if memberName == interner.intern("binarySearch") {
                return (1...4).contains(argCount)
            }
            return argCount == 1
        case interner.intern("binarySearchBy"):
            return argCount == 2 || argCount == 3 || argCount == 4
        case interner.intern("toCollection"), interner.intern("filterIsInstanceTo"), interner.intern("filterNotNullTo"):
            return argCount == 1
        case interner.intern("filterTo"), interner.intern("filterNotTo"), interner.intern("mapTo"), interner.intern("flatMapTo"), interner.intern("mapNotNullTo"), interner.intern("mapIndexedTo"), interner.intern("mapIndexedNotNullTo"), interner.intern("flatMapIndexedTo"), interner.intern("associateTo"),
             interner.intern("reduceTo"), interner.intern("associateByTo"), interner.intern("associateWithTo"), interner.intern("groupByTo"), interner.intern("filterIndexedTo"):
            return argCount == 2
        case interner.intern("intersect"), interner.intern("union"), interner.intern("subtract"):
            return isSetReceiver && argCount == 1
        case interner.intern("containsKey"), interner.intern("mapValues"), interner.intern("mapKeys"),
             interner.intern("filterKeys"), interner.intern("filterValues"):
            return isMapReceiver && argCount == 1
        case knownNames.getValue:
            return isMapReceiver && argCount == 1
        case knownNames.getOrDefault:
            return isMapReceiver && argCount == 2
        case knownNames.getOrElse:
            return argCount == 2
        case interner.intern("elementAtOrElse"):
            return argCount == 2
        case knownNames.getOrPut:
            return isMutableMapReceiver && argCount == 2
        case interner.intern("addAll"), interner.intern("removeAll"), interner.intern("retainAll"):
            return (isMutableListReceiver || isMutableSetReceiver) && argCount == 1
        case knownNames.putAll:
            return isMutableMapReceiver && argCount == 1
        case interner.intern("plus"), interner.intern("minus"):
            return isMapReceiver && argCount == 1
        case interner.intern("fold"), interner.intern("foldRight"), interner.intern("foldIndexed"), interner.intern("foldRightIndexed"), interner.intern("scan"), interner.intern("scanIndexed"), interner.intern("runningFold"), interner.intern("runningFoldIndexed"), interner.intern("subList"):
            return argCount == 2
        case interner.intern("slice"):
            return argCount == 1
        case interner.intern("reduceRight"), interner.intern("reduceIndexed"), interner.intern("reduceIndexedOrNull"), interner.intern("runningReduceIndexed"):
            return argCount == 1
        case interner.intern("windowed"):
            return argCount == 1 || argCount == 2 || argCount == 3 || argCount == 4
        case interner.intern("chunked"):
            return argCount == 1 || argCount == 2
        case interner.intern("count"), interner.intern("first"), interner.intern("last"),
             interner.intern("single"):
            return argCount == 0 || argCount == 1
        default:
            return true
        }
    }

    func collectionFallbackResultType(
        memberName: InternedString,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isSequenceReceiver: Bool = false,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let intReturningMembers: Set = [
            interner.intern("size"),
            interner.intern("indexOf"),
            interner.intern("lastIndexOf"),
            interner.intern("indexOfFirst"),
            interner.intern("indexOfLast"),
            interner.intern("count"),
            interner.intern("sumOf"),
            interner.intern("binarySearch"),
            interner.intern("binarySearchBy"),
        ]
        if intReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.int, .nonNull))
        }

        // sum() returns the element type (Int for List<Int>, Long for List<Long>, etc.)
        if memberName == interner.intern("sum") {
            return receiverElementType
        }

        if memberName == interner.intern("chunked") && args.count == 2 {
            let transformExpr = args[1].expr
            let lambdaReturnType: TypeID = if let transformType = sema.bindings.exprTypes[transformExpr],
                                               case let .functionType(fnType) = sema.types.kind(of: transformType) {
                fnType.returnType
            } else {
                sema.types.anyType
            }

            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: lambdaReturnType
                )
            }

            if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(lambdaReturnType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        }

        if memberName == interner.intern("requireNoNulls"), isSequenceReceiver {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.makeNonNullable(receiverElementType)
            )
        }

        let boolReturningMembers: Set = [
            knownNames.isEmpty, interner.intern("contains"), interner.intern("containsAll"),
            interner.intern("containsKey"),
            interner.intern("any"), interner.intern("none"), interner.intern("all"),
            interner.intern("addAll"), interner.intern("removeAll"), interner.intern("retainAll"),
        ]
        if boolReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.boolean, .nonNull))
        }

        if memberName == interner.intern("forEach") ||
            memberName == interner.intern("forEachIndexed") ||
            memberName == interner.intern("sort") ||
            memberName == interner.intern("sortBy") ||
            memberName == interner.intern("sortByDescending")
        {
            return sema.types.unitType
        }

        if memberName == interner.intern("joinToString") {
            return sema.types.stringType
        }

        if memberName == knownNames.putAll {
            return sema.types.unitType
        }

        let destinationCollectionReturningMembers: Set = [
            interner.intern("filterTo"),
            interner.intern("filterNotTo"),
            interner.intern("mapTo"),
            interner.intern("flatMapTo"),
            interner.intern("mapNotNullTo"),
            interner.intern("mapIndexedTo"),
            interner.intern("mapIndexedNotNullTo"),
            interner.intern("flatMapIndexedTo"),
            interner.intern("filterIsInstanceTo"),
            interner.intern("filterIndexedTo"),
            interner.intern("filterNotNullTo"),
            interner.intern("reduceTo"),
            interner.intern("associateTo"),
            interner.intern("toCollection"),
            interner.intern("associateByTo"),
            interner.intern("associateWithTo"),
            interner.intern("groupByTo"),
        ]
        if destinationCollectionReturningMembers.contains(memberName),
           let firstArg = args.first
        {
            return sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
        }

        if (memberName == interner.intern("onEach") || memberName == interner.intern("onEachIndexed")),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("find") {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == interner.intern("asIterable") {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }

        if memberName == interner.intern("elementAt")
            || memberName == interner.intern("single")
        {
            return receiverElementType
        }

        if memberName == interner.intern("getOrNull")
            || memberName == interner.intern("elementAtOrNull")
            || memberName == interner.intern("firstOrNull")
            || memberName == interner.intern("lastOrNull")
            || memberName == interner.intern("singleOrNull")
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == knownNames.getOrElse, !isMapReceiver {
            return receiverElementType
        }

        if memberName == interner.intern("elementAtOrElse") {
            return receiverElementType
        }

        if memberName == interner.intern("plus") || memberName == interner.intern("minus")
            || memberName == interner.intern("filter") || memberName == interner.intern("filterKeys")
            || memberName == interner.intern("filterValues")
        {
            // plus/minus/filter/filterKeys/filterValues return the same Map type as the receiver.
            // receiverElementType for maps is Map.Entry<K,V>, so reconstruct Map<K,V>.
            if case let .classType(entryType) = sema.types.kind(of: receiverElementType),
               entryType.args.count >= 2
            {
                let keyArg = entryType.args[0]
                let valueArg = entryType.args[1]
                if let mapSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Map"),
                ]) {
                    return sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [keyArg, valueArg],
                        nullability: .nonNull
                    )))
                }
            }
            return sema.types.anyType
        }

        if memberName == knownNames.getValue
            || memberName == knownNames.getOrDefault
            || memberName == knownNames.getOrPut
            || (memberName == knownNames.getOrElse && isMapReceiver)
        {
            if case let .classType(classType) = sema.types.kind(of: receiverElementType),
               classType.args.count >= 2
            {
                return switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            }
            return sema.types.anyType
        }

        if memberName == interner.intern("maxOrNull")
            || memberName == interner.intern("minOrNull")
            || memberName == interner.intern("maxByOrNull")
            || memberName == interner.intern("minByOrNull")
            || memberName == interner.intern("firstOrNull")
            || memberName == interner.intern("lastOrNull")
            || memberName == interner.intern("singleOrNull")
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == interner.intern("maxOfOrNull")
            || memberName == interner.intern("minOfOrNull")
        {
            return sema.types.nullableAnyType
        }

        if (memberName == interner.intern("toList")
            || memberName == interner.intern("subList")
            || memberName == interner.intern("slice")),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toIntArray"),
           let intArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("IntArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: intArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toLongArray"),
           let longArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("LongArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: longArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toByteArray"),
           let byteArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("ByteArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: byteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toUByteArray"),
           let ubyteArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("UByteArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ubyteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toUShortArray"),
           let ushortArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("UShortArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ushortArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toUIntArray"),
           let uintArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("UIntArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: uintArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toULongArray"),
           let ulongArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("ULongArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ulongArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toMutableList"),
           let mutableListSymbol = sema.symbols.lookupByShortName(interner.intern("MutableList")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableListSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("reduceOrNull")
            || memberName == interner.intern("reduceIndexedOrNull")
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if (memberName == interner.intern("runningReduce")
            || memberName == interner.intern("runningReduceIndexed")
            || memberName == interner.intern("scanReduce")),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if (memberName == interner.intern("scan")
            || memberName == interner.intern("scanIndexed")
            || memberName == interner.intern("runningFold")
            || memberName == interner.intern("runningFoldIndexed")),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            // scan/runningFold variants return List<R> where R is the accumulator type,
            // derived from the initial value (first argument).
            let accumulatorType: TypeID
            if args.count >= 1, let inferredInitType = sema.bindings.exprTypes[args[0].expr] {
                accumulatorType = inferredInitType
            } else {
                accumulatorType = sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(accumulatorType)],
                nullability: .nonNull
            )))
        }

        if isSetReceiver,
           (memberName == interner.intern("intersect") ||
               memberName == interner.intern("union") ||
               memberName == interner.intern("subtract")),
           let setSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("Set"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("withIndex"),
           let iterableSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("Iterable"),
           ]),
           let indexedValueSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("IndexedValue"),
           ])
        {
            let indexedValueType = sema.types.make(.classType(ClassType(
                classSymbol: indexedValueSymbol,
                args: [.out(receiverElementType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: iterableSymbol,
                args: [.out(indexedValueType)],
                nullability: .nonNull
            )))
        }

        // sorted(), sortedDescending(), sortedWith(), sorted(comparator): return List<E>
        // reversed(), asReversed(), distinct(), distinctBy(): return List<E>
        let listPreservingMembers: Set = [
            interner.intern("sorted"),
            interner.intern("sortedDescending"),
            interner.intern("sortedWith"),
            interner.intern("shuffled"),
            interner.intern("reversed"),
            interner.intern("asReversed"),
            interner.intern("distinct"),
            interner.intern("distinctBy"),
        ]
        if memberName == interner.intern("shuffled"), isSequenceReceiver {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        if listPreservingMembers.contains(memberName),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        // flatten(): for List<List<E>>, returns List<E> (element type of the outer list elements).
        // Skip this for sequence receivers — the existing sequence HOF logic handles them,
        // and mixed-type sequence flatten should fail gracefully (matching kotlinc).
        if memberName == interner.intern("flatten"),
           !isSequenceReceiver,
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            // The receiverElementType is List<E> (the inner list). Extract E from it.
            let innerElementType: TypeID
            if case let .classType(innerListType) = sema.types.kind(of: receiverElementType),
               let firstArg = innerListType.args.first
            {
                innerElementType = switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                innerElementType = sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(innerElementType)],
                nullability: .nonNull
            )))
        }

        // zip(other): returns List<Pair<A,B>> where A is receiver element type and B is other element type
        if memberName == interner.intern("zip"),
           !args.isEmpty,
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first,
           let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first
        {
            // Try to get the element type of the other list from the first argument
            let otherElementType: TypeID
            if let otherListType = sema.bindings.exprTypes[args[0].expr] {
                let nonNullOther = sema.types.makeNonNullable(otherListType)
                if case let .classType(classType) = sema.types.kind(of: nonNullOther),
                   let firstArg = classType.args.first
                {
                    otherElementType = switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    otherElementType = sema.types.anyType
                }
            } else {
                otherElementType = sema.types.anyType
            }
            let pairType = sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.invariant(receiverElementType), .invariant(otherElementType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(pairType)],
                nullability: .nonNull
            )))
        }

        // unzip(): for List<Pair<A,B>>, returns Pair<List<A>, List<B>>
        if memberName == interner.intern("unzip"),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first,
           let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first
        {
            // receiverElementType should be Pair<A, B>; extract A and B
            let aType: TypeID
            let bType: TypeID
            if case let .classType(pairClassType) = sema.types.kind(of: receiverElementType),
               pairClassType.args.count >= 2
            {
                aType = switch pairClassType.args[0] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
                bType = switch pairClassType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                aType = sema.types.anyType
                bType = sema.types.anyType
            }
            let listAType = sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(aType)],
                nullability: .nonNull
            )))
            let listBType = sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(bType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(listAType), .out(listBType)],
                nullability: .nonNull
            )))
        }

        // iterator(): returns Iterator<E>
        if memberName == interner.intern("iterator"),
           let iteratorSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("Iterator"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if isSequenceReceiver,
           memberName == interner.intern("windowed"),
           args.count == 4
        {
            let transformExpr = args[3].expr
            let transformType = sema.bindings.exprTypes[transformExpr] ?? sema.types.anyType
            let transformedElementType: TypeID
            if case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType)) {
                transformedElementType = fnType.returnType
            } else {
                transformedElementType = sema.types.anyType
            }
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: transformedElementType
            )
        }

        if isSequenceReceiver,
           memberName == interner.intern("chunked"),
           args.count == 2
        {
            let transformExpr = args[1].expr
            let transformType = sema.bindings.exprTypes[transformExpr] ?? sema.types.anyType
            let transformedElementType: TypeID
            if case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType)) {
                transformedElementType = fnType.returnType
            } else {
                transformedElementType = sema.types.anyType
            }
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: transformedElementType
            )
        }

        return sema.types.anyType
    }

    func collectionFallbackLambdaExpectation(
        memberName: InternedString,
        argCount: Int,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        isMutableMapReceiver: Bool,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        interner: StringInterner,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let mapValues = interner.intern("mapValues")
        let mapKeys = interner.intern("mapKeys")
        let boolOneParamMembers: Set = [
            interner.intern("filter"),
            interner.intern("filterNot"),
            interner.intern("any"),
            interner.intern("none"),
            interner.intern("all"),
            interner.intern("count"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("single"),
            interner.intern("find"),
            interner.intern("indexOfFirst"),
            interner.intern("indexOfLast"),
            interner.intern("partition"),
            interner.intern("takeWhile"),
            interner.intern("dropWhile"),
        ]
        let knownNames = KnownCompilerNames(interner: interner)
        let oneParamMembers: Set = [
            interner.intern("map"),
            interner.intern("filter"),
            interner.intern("filterNot"),
            interner.intern("mapNotNull"),
            interner.intern("forEach"),
            interner.intern("flatMap"),
            interner.intern("flatMapIndexed"),
            interner.intern("any"),
            interner.intern("none"),
            interner.intern("all"),
            interner.intern("groupBy"),
            interner.intern("groupingBy"),
            interner.intern("sortedBy"),
            interner.intern("count"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("single"),
            interner.intern("find"),
            interner.intern("associateBy"),
            interner.intern("associateWith"),
            interner.intern("associate"),
            interner.intern("sumOf"),
            interner.intern("sortedByDescending"),
            interner.intern("partition"),
            interner.intern("takeWhile"),
            interner.intern("dropWhile"),
            interner.intern("onEach"),
            interner.intern("sortBy"),
            interner.intern("sortByDescending"),
            interner.intern("maxByOrNull"),
            interner.intern("minByOrNull"),
            interner.intern("maxOfOrNull"),
            interner.intern("minOfOrNull"),
            interner.intern("maxOf"),
            interner.intern("minOf"),
        ]
        let filterKeys = interner.intern("filterKeys")
        let filterValues = interner.intern("filterValues")
        let mapOnlyMembers: Set = [
            mapValues,
            mapKeys,
            filterKeys,
            filterValues,
            knownNames.getOrDefault,
        ]
        let destinationCollectionLambdaMembers: Set = [
            interner.intern("filterTo"),
            interner.intern("filterNotTo"),
            interner.intern("mapTo"),
            interner.intern("flatMapTo"),
            interner.intern("mapNotNullTo"),
            interner.intern("mapIndexedTo"),
            interner.intern("mapIndexedNotNullTo"),
            interner.intern("flatMapIndexedTo"),
            interner.intern("associateTo"),
            interner.intern("filterIndexedTo"),
        ]
        if mapOnlyMembers.contains(memberName) {
            guard isMapReceiver else {
                return nil
            }
        }
        if oneParamMembers.contains(memberName) || memberName == mapValues || memberName == mapKeys, argCount == 1 {
            let lambdaReturnType = boolOneParamMembers.contains(memberName)
                ? sema.types.make(.primitive(.boolean, .nonNull))
                : memberName == interner.intern("sumOf")
                ? sema.types.intType
                : sema.types.anyType
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: lambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if destinationCollectionLambdaMembers.contains(memberName), argCount == 2 {
            let destinationType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let destinationCollectionElementType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                                   destClassType.args.count >= 1
            {
                switch destClassType.args[0] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let destinationMapKeyType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                          destClassType.args.count >= 2
            {
                switch destClassType.args[0] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let destinationMapValueType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                            destClassType.args.count >= 2
            {
                switch destClassType.args[1] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let destinationLambdaReturnType: TypeID = switch memberName {
            case interner.intern("filterTo"), interner.intern("filterNotTo"), interner.intern("filterIndexedTo"):
                sema.types.booleanType
            case interner.intern("mapNotNullTo"), interner.intern("mapIndexedNotNullTo"):
                sema.types.nullableAnyType
            case interner.intern("flatMapTo"), interner.intern("flatMapIndexedTo"):
                if let collectionSymbol = sema.symbols.lookupByShortName(interner.intern("Collection")).first {
                    sema.types.make(.classType(ClassType(
                        classSymbol: collectionSymbol,
                        args: [.out(destinationCollectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }
            case interner.intern("associateTo"):
                if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                    sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.out(destinationMapKeyType), .out(destinationMapValueType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }
            default:
                sema.types.anyType
            }
            let expectedType: TypeID
            if memberName == interner.intern("mapIndexedTo")
                || memberName == interner.intern("mapIndexedNotNullTo")
                || memberName == interner.intern("flatMapIndexedTo")
                || memberName == interner.intern("filterIndexedTo")
            {
                expectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, receiverElementType],
                    returnType: destinationLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            } else {
                expectedType = sema.types.make(.functionType(FunctionType(
                    params: [receiverElementType],
                    returnType: destinationLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            }
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if (memberName == interner.intern("maxWith")
            || memberName == interner.intern("maxWithOrNull")
            || memberName == interner.intern("minWith")
            || memberName == interner.intern("minWithOrNull")),
           argCount == 1,
           let comparatorSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("Comparator"),
           ])
        {
            let expectedType = sema.types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if (memberName == interner.intern("maxOfWith")
            || memberName == interner.intern("maxOfWithOrNull")
            || memberName == interner.intern("minOfWith")
            || memberName == interner.intern("minOfWithOrNull")),
           argCount == 2
        {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // *To functions: destination + lambda (2 args), lambda is at index 1
        if (memberName == interner.intern("associateByTo") || memberName == interner.intern("associateWithTo") || memberName == interner.intern("groupByTo")), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("forEachIndexed")
            || memberName == interner.intern("mapIndexed")
            || memberName == interner.intern("onEachIndexed")
            || memberName == interner.intern("flatMapIndexed"),
            argCount == 1
        {
            let lambdaReturnType = memberName == interner.intern("forEachIndexed") || memberName == interner.intern("onEachIndexed")
                ? sema.types.unitType
                : sema.types.anyType
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, receiverElementType],
                returnType: lambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        // chunked(size, transform): transform receives List<T> and returns R
        if memberName == interner.intern("chunked"), argCount == 2 {
            // Build List<T> for the lambda parameter type; the transform receives
            // a List<T> chunk.
            let listType: TypeID
            if let listSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ]) {
                listType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
            } else {
                listType = sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [listType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // windowed(size, step, partialWindows, transform): transform receives List<T> and returns R
        if memberName == interner.intern("windowed"), (2...4).contains(argCount) {
            let lastArgIsFunctionLike: Bool = if let lastExpr = args.last?.expr,
                                                 let lastExprNode = ctx.ast.arena.expr(lastExpr) {
                lastExprNode.isLambdaOrCallableRef
            } else {
                false
            }
            if lastArgIsFunctionLike {
                let listType: TypeID
                if let listSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]) {
                    listType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(receiverElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    listType = sema.types.anyType
                }
                let expectedType = sema.types.make(.functionType(FunctionType(
                    params: [listType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return (argumentIndex: argCount - 1, expectedType: expectedType)
            }
        }

        if memberName == interner.intern("fold"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("foldIndexed"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("foldRight"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("foldRightIndexed"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("reduceRight"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if (memberName == interner.intern("reduce") || memberName == interner.intern("reduceOrNull")), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == interner.intern("reduceIndexed"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if (memberName == interner.intern("scan")
            || memberName == interner.intern("scanIndexed")
            || memberName == interner.intern("runningFold")
            || memberName == interner.intern("runningFoldIndexed")), argCount == 2
        {
            // scan/runningFold variants: (acc: R, element: T) -> R
            // The accumulator type is unknown in the fallback path, so use Any;
            // indexed variants prepend the Int index parameter.
            let params: [TypeID] = if memberName == interner.intern("scanIndexed")
                || memberName == interner.intern("runningFoldIndexed")
            {
                [sema.types.intType, sema.types.anyType, receiverElementType]
            } else {
                [sema.types.anyType, receiverElementType]
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: params,
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if (memberName == interner.intern("runningReduce")
            || memberName == interner.intern("runningReduceIndexed")
            || memberName == interner.intern("scanReduce")
            || memberName == interner.intern("reduceIndexedOrNull")), argCount == 1
        {
            // runningReduce/scanReduce/reduceIndexedOrNull variants use receiver element type.
            let params: [TypeID] = if memberName == interner.intern("runningReduceIndexed")
                || memberName == interner.intern("reduceIndexedOrNull")
            {
                [sema.types.intType, receiverElementType, receiverElementType]
            } else {
                [receiverElementType, receiverElementType]
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: params,
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == interner.intern("sortedWith"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType, receiverElementType],
                returnType: sema.types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.getOrPut, isMutableMapReceiver, argCount == 2 {
            let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: receiverElementType),
                                       classType.args.count >= 2
            {
                switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: valueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.getOrElse, isMapReceiver, argCount == 2 {
            let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: receiverElementType),
                                       classType.args.count >= 2
            {
                switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: valueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // List.getOrElse(index, { default }) — lambda takes Int (index), returns element type
        if memberName == knownNames.getOrElse, !isMapReceiver, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // List.elementAtOrElse(index, { default }) — same as getOrElse
        if memberName == interner.intern("elementAtOrElse"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("binarySearchBy"), (2...4).contains(argCount) {
            let keyType = args.indices.contains(0)
                ? (sema.bindings.exprTypes[args[0].expr] ?? sema.types.nullableAnyType)
                : sema.types.nullableAnyType
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
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: selectorReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: argCount - 1, expectedType: expectedType)
        }

        return nil
    }

    func collectionFallbackElementType(receiverID: ExprID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        else {
            return sema.types.anyType
        }
        if let symbol = sema.symbols.symbol(classType.classSymbol),
           knownNames.isMapLikeSymbol(symbol),
           classType.args.count == 2
        {
            let keyType = switch classType.args[0] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let valueType = switch classType.args[1] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let entrySymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Map"),
                interner.intern("Entry"),
            ])
            guard let entrySymbol else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: entrySymbol,
                args: [.out(keyType), .out(valueType)],
                nullability: .nonNull
            )))
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

    func isCollectionLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        if sema.bindings.isCollectionExpr(receiverID) {
            return true
        }
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        return isCollectionLikeType(receiverType, sema: sema, interner: interner)
    }

    func isIterableLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.name == interner.intern("Iterable")
            || symbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
    }

    private func isSequenceLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        return isSequenceLikeType(receiverType, sema: sema, interner: interner)
    }

    func isSequenceLikeType(
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
        return knownNames.isSequenceSymbol(symbol)
    }

    func isCollectionLikeType(
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
        return knownNames.isCollectionLikeSymbol(symbol)
    }

    func isListLikeType(
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
        return knownNames.isConcreteListLikeSymbol(symbol)
    }

    private func isMapLikeCollectionReceiver(receiverID: ExprID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol) && classType.args.count == 2
    }

    private func isMutableListCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return (
            symbol.name == knownNames.mutableList
                || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
        ) && classType.args.count == 1
    }

    private func isMutableSetCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMutableSetSymbol(symbol) && classType.args.count == 1
    }

    private func isMutableMapCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMutableMapSymbol(symbol) && classType.args.count == 2
    }

    private func isConcreteListLikeCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && !knownNames.isMapLikeSymbol(symbol)
    }

    private func isSetLikeCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.collectionKind(of: symbol) == .set && classType.args.count == 1
    }

    // MARK: - Array member fallback (STDLIB-087/088/089)

    func tryArrayMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard !isClassNameReceiver,
              isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        if memberName == "binarySearch" {
            if isBooleanArrayReceiver(receiverID: receiverID, sema: sema, interner: interner) {
                return nil
            }
            if !isGenericArrayReceiver(receiverID: receiverID, sema: sema, interner: interner) {
                if args.indices.contains(1) {
                    let secondArgumentType = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
                    if !sema.types.isSubtype(secondArgumentType, sema.types.intType) {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0002",
                            "No viable overload found for call.",
                            range: ctx.ast.arena.exprRange(id)
                        )
                        sema.bindings.bindExprType(id, type: sema.types.errorType)
                        return sema.types.errorType
                    }
                }
                return nil
            }
        }
        guard isSupportedArrayMember(memberName),
              isValidArrayMemberArity(memberName, argCount: args.count)
        else {
            return nil
        }

        // Extract the actual element type from the Array<T> receiver (TYPE-103).
        let receiverElementType = arrayFallbackElementType(receiverID: receiverID, sema: sema, interner: interner)
        if memberName == "binarySearch" {
            if isGenericArrayReceiver(receiverID: receiverID, sema: sema, interner: interner),
               (2...4).contains(args.count),
               args.indices.contains(1)
            {
                let comparatorArgExpr = args[1].expr
                let comparatorArg = ctx.ast.arena.expr(comparatorArgExpr)
                let comparatorExpectedType: TypeID
                if comparatorArg?.isLambdaOrCallableRef ?? false {
                    sema.bindings.markCollectionHOFLambdaExpr(comparatorArgExpr)
                    comparatorExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [receiverElementType, receiverElementType],
                        returnType: sema.types.intType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                } else if let comparatorSymbol = sema.symbols.lookupByShortName(interner.intern("Comparator")).first {
                    comparatorExpectedType = sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(receiverElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    comparatorExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [receiverElementType, receiverElementType],
                        returnType: sema.types.intType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                }
                _ = driver.inferExpr(
                    comparatorArgExpr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: comparatorExpectedType
                )
            } else {
                if args.indices.contains(0) {
                    let firstArgExpr = args[0].expr
                    if let lambdaExpr = ctx.ast.arena.expr(firstArgExpr), lambdaExpr.isLambdaOrCallableRef {
                        return nil
                    }
                    _ = driver.inferExpr(
                        firstArgExpr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: receiverElementType
                    )
                }
                if args.indices.contains(1) {
                    _ = driver.inferExpr(
                        args[1].expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: sema.types.intType
                    )
                }
                if args.indices.contains(2) {
                    _ = driver.inferExpr(
                        args[2].expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: sema.types.intType
                    )
                }
            }
        } else {
            if memberName == "copyOf", args.indices.contains(0) {
                _ = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: sema.types.intType
                )
            }
            if let expectation = arrayMemberLambdaExpectation(
                memberName: memberName,
                argCount: args.count,
                receiverElementType: receiverElementType,
                sema: sema
            ),
                args.indices.contains(expectation.argumentIndex)
            {
                let lambdaArgExpr = args[expectation.argumentIndex].expr
                if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
                }
                _ = driver.inferExpr(
                    lambdaArgExpr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: expectation.expectedType
                )
            }
            if memberName == "binarySearch", args.count == 4,
               let comparatorSymbol = sema.symbols.lookup(fqName: [
                   interner.intern("kotlin"),
                   interner.intern("Comparator"),
               ])
            {
                let comparatorExpectedType = sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: receiverElementType)
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            }
        }

        // Mark result as collection if it returns a List
        if isArrayMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }

        let resultType = arrayMemberResultType(
            memberName: memberName,
            receiverID: receiverID,
            elementType: receiverElementType,
            sema: sema,
            interner: interner
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSupportedArrayMember(_ memberName: String) -> Bool {
        let arrayMembers: Set = [
            "toList", "toMutableList",
            "map", "filter", "forEach", "any", "none",
            "copyOf", "copyOfRange", "fill",
            "size", "get", "contains", "isEmpty",
            "binarySearch",
            "concatToString",
        ]
        return arrayMembers.contains(memberName)
    }

    private func isValidArrayMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "toList", "toMutableList", "size", "isEmpty", "concatToString":
            argCount == 0
        case "copyOf":
            (0...2).contains(argCount)
        case "map", "filter", "forEach", "any", "none", "fill", "get", "contains":
            argCount == 1
        case "binarySearch":
            (1...4).contains(argCount)
        case "copyOfRange":
            argCount == 2
        default:
            true
        }
    }

    private func isArrayMemberReturningCollection(_ memberName: String) -> Bool {
        ["toList", "toMutableList", "map", "filter", "copyOf", "copyOfRange"].contains(memberName)
    }

    private func arrayMemberResultType(
        memberName: String,
        receiverID: ExprID,
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        switch memberName {
        case "size":
            return sema.types.intType
        case "binarySearch":
            return sema.types.intType
        case "isEmpty", "contains", "any", "none":
            return sema.types.booleanType
        case "forEach", "fill":
            return sema.types.unitType
        case "concatToString":
            return sema.types.stringType
        case "get":
            return elementType
        case "copyOf", "copyOfRange":
            let receiverType = sema.bindings.exprTypes[receiverID]
                ?? sema.bindings.identifierSymbol(for: receiverID).flatMap { sema.symbols.propertyType(for: $0) }
                ?? sema.types.anyType
            return sema.types.makeNonNullable(receiverType)
        case "toList":
            if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        case "toMutableList":
            if let mutableListSymbol = sema.symbols.lookupByShortName(interner.intern("MutableList")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: mutableListSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        default:
            return sema.types.anyType
        }
    }

    private func isGenericArrayReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let knownNames = KnownCompilerNames(interner: interner)
        return symbol.name == knownNames.array && classType.args.count == 1
    }

    private func arrayMemberLambdaExpectation(
        memberName: String,
        argCount: Int,
        receiverElementType: TypeID,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let boolPredicateMembers: Set = ["filter", "any", "none"]
        let oneParamMembers: Set = ["map", "filter", "forEach", "any", "none"]
        if memberName == "copyOf", argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }
        guard oneParamMembers.contains(memberName), argCount == 1 else {
            return nil
        }
        let lambdaReturnType = boolPredicateMembers.contains(memberName)
            ? sema.types.booleanType
            : memberName == "forEach" ? sema.types.unitType : sema.types.anyType
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: [receiverElementType],
            returnType: lambdaReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: 0, expectedType: expectedType)
    }

    /// Extract the element type from an `Array<T>` receiver.
    /// For generic `Array<T>`, returns `T`; for primitive arrays (IntArray, etc.)
    /// returns the corresponding primitive type.  Falls back to `Any` when the
    /// element type cannot be determined.
    private func isBooleanArrayReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID]
            ?? sema.bindings.identifierSymbol(for: receiverID).flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNull),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let knownNames = KnownCompilerNames(interner: interner)
        return symbol.name == knownNames.booleanArray
    }

    private func arrayFallbackElementType(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let receiverType = sema.bindings.exprTypes[receiverID]
            ?? sema.bindings.identifierSymbol(for: receiverID).flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNull),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return sema.types.anyType
        }

        let knownNames = KnownCompilerNames(interner: interner)

        // Generic Array<T>: extract type argument.
        if symbol.name == knownNames.array, let firstArg = classType.args.first {
            return switch firstArg {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
        }

        // Primitive arrays have a fixed element type.
        // Note: Byte/Short map to intType (same as builtinType resolution).
        let primitiveMapping: [(InternedString, TypeID)] = [
            (knownNames.intArray, sema.types.intType),
            (knownNames.longArray, sema.types.longType),
            (knownNames.shortArray, sema.types.intType),
            (knownNames.byteArray, sema.types.intType),
            (knownNames.ubyteArray, sema.types.ubyteType),
            (knownNames.ushortArray, sema.types.ushortType),
            (knownNames.uintArray, sema.types.uintType),
            (knownNames.ulongArray, sema.types.ulongType),
            (knownNames.doubleArray, sema.types.doubleType),
            (knownNames.floatArray, sema.types.floatType),
            (knownNames.booleanArray, sema.types.booleanType),
            (knownNames.charArray, sema.types.charType),
        ]
        for (name, elementType) in primitiveMapping {
            if symbol.name == name {
                return elementType
            }
        }

        return sema.types.anyType
    }

    func isArrayLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        return isArrayLikeType(receiverType, sema: sema, interner: interner)
    }

    private func isArrayLikeType(
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
        return knownNames.isArrayLikeName(symbol.name)
    }

    // MARK: - KFunction member call fallback (STDLIB-REFLECT-063)

    /// Checks whether the receiver type is `kotlin.reflect.KFunction<*>`.
    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let kFuncSym = sema.types.kFunctionInterfaceSymbol,
              classType.classSymbol == kFuncSym
        else {
            return false
        }
        return true
    }

    /// Returns the return-type argument of a `KFunction<R>` type, or `anyType` when not available.
    private func kFunctionReturnType(
        _ receiverType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              classType.args.count == 1
        else {
            return sema.types.anyType
        }
        switch classType.args[0] {
        case let .out(t), let .invariant(t): return t
        default: return sema.types.anyType
        }
    }

    /// Handles member calls on `KFunction<R>` receivers:
    /// - `call(vararg args)` → returns R (the KFunction type argument)
    func tryKFunctionMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema) else { return nil }
        let memberName = interner.resolve(calleeName)

        switch memberName {
        case "call":
            // Infer argument types (accept any).
            for arg in args {
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: nil)
            }
            let returnType = kFunctionReturnType(receiverType, sema: sema)
            let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "name":
            let resultType = sema.types.make(.primitive(.string, .nonNull))
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "isSuspend":
            let resultType = sema.types.booleanType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        case "parameters":
            // parameters returns List<Any?>, but at this stage use anyType as a safe fallback.
            let resultType = sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        default:
            return nil
        }
    }
}
