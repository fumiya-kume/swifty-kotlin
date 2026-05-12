/// Member-call fallback resolution for `Array<T>` and primitive-array
/// receivers (STDLIB-087/088/089).
///
/// Split out from `CallTypeChecker+MemberCallFallbacks.swift`.
extension CallTypeChecker {
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

    func isSupportedArrayMember(_ memberName: String) -> Bool {
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
