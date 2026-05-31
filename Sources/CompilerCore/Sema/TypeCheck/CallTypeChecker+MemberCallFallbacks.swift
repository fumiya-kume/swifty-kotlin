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

    /// Resolves `placement.alloc<T>()` to the synthetic
    /// `kotlinx.cinterop.alloc<T : CVariable>(): T` extension when the new
    /// `NativePlacement` member overloads (`alloc(size, align)`) shadow the
    /// zero-argument generic form during member lookup.  See
    /// `inferRegularMemberCall` for why member candidates are not mixed with
    /// extension candidates by default.
    func tryNativePlacementAllocExtensionFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver,
              args.isEmpty,
              explicitTypeArgs.count == 1,
              interner.resolve(calleeName) == "alloc"
        else {
            return nil
        }

        let cinteropPkg = [interner.intern("kotlinx"), interner.intern("cinterop")]
        guard let nativePlacementSymbol = sema.symbols.lookup(
            fqName: cinteropPkg + [interner.intern("NativePlacement")]
        ) else {
            return nil
        }
        let nativePlacementType = sema.types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard sema.types.isSubtype(nonNullReceiverType, nativePlacementType) else {
            return nil
        }

        let allocFQName = cinteropPkg + [interner.intern("alloc")]
        guard let chosen = sema.symbols.lookupAll(fqName: allocFQName).first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        }) else {
            return nil
        }

        let typeArg = explicitTypeArgs[0]
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [typeArg],
                parameterMapping: [:]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let finalType = safeCall ? sema.types.makeNullable(typeArg) : typeArg
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    /// Resolves `value.readValue()` to the synthetic
    /// `<T : CStructVar> T.readValue(): CValue<T>` extension when the
    /// member-first lookup picks up `CPointed.readValue(size, align)` (an
    /// inherited member that any `CStructVar`-bounded receiver exposes) and
    /// the resolver rejects it on arity mismatch with no extension fallback.
    ///
    /// Returns `CValue<receiverType>` after binding the chosen callee.
    func tryNativeCInteropReadValueExtensionFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard !isClassNameReceiver,
              args.isEmpty,
              interner.resolve(calleeName) == "readValue"
        else {
            return nil
        }

        let cinteropPkg = [interner.intern("kotlinx"), interner.intern("cinterop")]
        guard let cStructVarSymbol = sema.symbols.lookup(
            fqName: cinteropPkg + [interner.intern("CStructVar")]
        ),
              let cValueSymbol = sema.symbols.lookup(
                  fqName: cinteropPkg + [interner.intern("CValue")]
              )
        else {
            return nil
        }
        let cStructVarType = sema.types.make(.classType(ClassType(
            classSymbol: cStructVarSymbol,
            args: [],
            nullability: .nonNull
        )))

        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        // Accept any receiver that is a CStructVar subtype, including a type
        // parameter whose upper bound is CStructVar (or one of its descendants).
        let receiverSatisfiesCStructVar: Bool = {
            if sema.types.isSubtype(nonNullReceiverType, cStructVarType) {
                return true
            }
            if case let .typeParam(typeParam) = sema.types.kind(of: nonNullReceiverType) {
                let upperBounds = sema.symbols.typeParameterUpperBounds(for: typeParam.symbol)
                return upperBounds.contains { sema.types.isSubtype($0, cStructVarType) }
            }
            return false
        }()
        guard receiverSatisfiesCStructVar else {
            return nil
        }

        let readValueFQName = cinteropPkg + [interner.intern("readValue")]
        guard let chosen = sema.symbols.lookupAll(fqName: readValueFQName).first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let recv = signature.receiverType,
                  signature.parameterTypes.isEmpty,
                  signature.typeParameterSymbols.count == 1
            else {
                return false
            }
            // The synthetic extension's declared receiver is its own type
            // parameter; reject `CPointed.readValue(size, align)` (concrete
            // receiver + 2 params) and any other unrelated overload.
            return sema.types.kind(of: recv) == .typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            ))
        }) else {
            return nil
        }

        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(nonNullReceiverType)],
            nullability: .nonNull
        )))
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [nonNullReceiverType],
                parameterMapping: [:]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryPathCharsetReadExtensionFallback(
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
        guard !isClassNameReceiver, args.count == 1 else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        guard memberName == "readText" || memberName == "readLines" else {
            return nil
        }

        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
              let owner = sema.symbols.symbol(classType.classSymbol),
              owner.fqName.count == 4,
              interner.resolve(owner.fqName[0]) == "kotlin",
              interner.resolve(owner.fqName[1]) == "io",
              interner.resolve(owner.fqName[2]) == "path",
              interner.resolve(owner.fqName[3]) == "Path",
              let charsetSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlin"),
                  interner.intern("text"),
                  interner.intern("Charset"),
              ])
        else {
            return nil
        }

        let charsetType = sema.types.make(.classType(ClassType(
            classSymbol: charsetSymbol,
            args: [],
            nullability: .nonNull
        )))
        let argType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: charsetType)
        guard sema.types.isSubtype(sema.types.makeNonNullable(argType), charsetType) else {
            return nil
        }

        let functionFQName = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("path"),
            calleeName,
        ]
        guard let chosen = sema.symbols.lookupAll(fqName: functionFQName).first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == nonNullReceiverType
                && signature.parameterTypes == [charsetType]
        }) else {
            return nil
        }

        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: ResolvedCall(
                chosenCallee: chosen,
                substitutedTypeArguments: [:],
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }


}
