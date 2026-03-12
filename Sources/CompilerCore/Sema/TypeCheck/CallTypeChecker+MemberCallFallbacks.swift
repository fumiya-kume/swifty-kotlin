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
        case ("lines", 0):
            listStringType
        case ("matches", 1), ("contains", 1):
            sema.types.booleanType
        case ("split", 1):
            listStringType
        case ("replace", 2):
            sema.types.stringType
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
        if args.indices.contains(0), let regexType {
            let expectedType = memberName == "replace" || memberName == "contains" || memberName == "matches" || memberName == "split"
                ? regexType
                : nil
            if let expectedType {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            }
        }
        if memberName == "replace", args.indices.contains(1) {
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
        }

        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
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

        guard !isClassNameReceiver,
              isCollectionLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        let isMapReceiver = isMapLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        guard isSupportedCollectionFallbackMember(memberName, isMapReceiver: isMapReceiver),
              isValidCollectionFallbackArity(memberName, argCount: args.count, isMapReceiver: isMapReceiver)
        else {
            return nil
        }

        // Provide contextual function type for collection HOF lambda inference.
        let receiverElementType = collectionFallbackElementType(receiverID: receiverID, sema: sema, interner: interner)
        if let expectation = collectionFallbackLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            sema: sema
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), case .lambdaLiteral = lambdaExpr {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }

        if isCollectionReturningMember(memberName, isMapReceiver: isMapReceiver) {
            sema.bindings.markCollectionExpr(id)
        }

        let resultType = collectionFallbackResultType(
            memberName: memberName,
            receiverElementType: receiverElementType,
            sema: sema,
            interner: interner
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func isSupportedCollectionFallbackMember(_ memberName: String, isMapReceiver: Bool) -> Bool {
        let collectionMembers: Set = [
            "size", "get", "contains",
            "isEmpty", "first", "last", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast",
            "count", "iterator",
            "map", "filter", "mapNotNull", "filterNotNull", "forEach", "flatMap",
            "any", "none", "all",
            "fold", "reduce", "groupBy", "sortedBy", "find", "associateBy", "associateWith", "associate", "zip", "unzip",
            "withIndex", "forEachIndexed", "mapIndexed", "sumOf", "maxOrNull", "minOrNull",
            "asSequence", "toList", "toTypedArray", "take", "drop", "reversed", "sorted", "distinct", "flatten",
            "chunked", "windowed",
            "sortedDescending", "sortedByDescending", "sortedWith", "partition",
            "filterIsInstance",
            "sort", "sortBy", "sortByDescending",
        ]
        let mapOnlyMembers: Set = ["containsKey", "mapValues", "mapKeys", "getOrDefault", "getOrElse"]
        if mapOnlyMembers.contains(memberName) {
            return isMapReceiver
        }
        return collectionMembers.contains(memberName)
    }

    func isCollectionReturningMember(_ memberName: String, isMapReceiver: Bool) -> Bool {
        let collectionReturningMembers: Set = [
            "asSequence", "map", "filter", "mapNotNull", "filterNotNull",
            "flatMap", "sortedBy", "groupBy", "associateBy", "associateWith",
            "associate", "zip", "toList", "toTypedArray", "take", "drop", "reversed",
            "sorted", "distinct", "flatten", "chunked", "windowed", "withIndex", "mapIndexed",
            "sortedDescending", "sortedByDescending", "sortedWith",
            "filterIsInstance",
        ]
        if memberName == "mapValues" || memberName == "mapKeys" {
            return isMapReceiver
        }
        return collectionReturningMembers.contains(memberName)
    }

    func isValidCollectionFallbackArity(_ memberName: String, argCount: Int, isMapReceiver: Bool) -> Bool {
        switch memberName {
        case "size", "isEmpty", "iterator", "asSequence", "toList", "toTypedArray", "reversed", "sorted", "distinct", "flatten", "withIndex", "maxOrNull", "minOrNull",
             "sortedDescending", "filterIsInstance",
             "sort":
            argCount == 0
        case "filterNotNull", "unzip":
            argCount == 0
        case "get", "contains", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast",
             "map", "filter", "mapNotNull", "forEach", "flatMap",
             "any", "none", "all",
             "groupBy", "sortedBy", "find", "associateBy", "associateWith", "associate", "reduce", "take", "drop", "zip",
             "forEachIndexed", "mapIndexed", "sumOf", "chunked",
             "sortedByDescending", "sortedWith", "partition",
             "sortBy", "sortByDescending":
            argCount == 1
        case "containsKey", "mapValues", "mapKeys":
            isMapReceiver && argCount == 1
        case "getOrDefault":
            isMapReceiver && argCount == 2
        case "getOrElse":
            isMapReceiver && argCount == 1
        case "fold", "windowed":
            argCount == 2
        case "count", "first", "last":
            argCount == 0 || argCount == 1
        default:
            true
        }
    }

    func collectionFallbackResultType(
        memberName: String,
        receiverElementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let intReturningMembers: Set = ["size", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast", "count", "sumOf"]
        if intReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.int, .nonNull))
        }

        let boolReturningMembers: Set = [
            "isEmpty", "contains", "containsKey",
            "any", "none", "all",
        ]
        if boolReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.boolean, .nonNull))
        }

        if memberName == "forEach" || memberName == "forEachIndexed"
            || memberName == "sort" || memberName == "sortBy" || memberName == "sortByDescending"
        {
            return sema.types.unitType
        }

        if memberName == "find" {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == "getOrDefault" || memberName == "getOrElse" {
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

        if memberName == "maxOrNull" || memberName == "minOrNull" {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == "toList",
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == "withIndex",
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

        return sema.types.anyType
    }

    func collectionFallbackLambdaExpectation(
        memberName: String,
        argCount: Int,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let boolOneParamMembers: Set = ["filter", "any", "none", "all", "count", "first", "last", "find", "indexOfFirst", "indexOfLast", "partition"]
        let oneParamMembers: Set = [
            "map", "filter", "mapNotNull", "forEach", "flatMap", "any", "none", "all",
            "groupBy", "sortedBy", "count", "first", "last", "find", "associateBy", "associateWith", "associate", "sumOf",
            "sortedByDescending", "partition",
            "sortBy", "sortByDescending",
        ]
        if memberName == "mapValues" || memberName == "mapKeys" {
            guard isMapReceiver, argCount == 1 else {
                return nil
            }
        }
        if oneParamMembers.contains(memberName) || memberName == "mapValues" || memberName == "mapKeys", argCount == 1 {
            let lambdaReturnType = boolOneParamMembers.contains(memberName)
                ? sema.types.make(.primitive(.boolean, .nonNull))
                : memberName == "sumOf"
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

        if memberName == "forEachIndexed" || memberName == "mapIndexed", argCount == 1 {
            let lambdaReturnType = memberName == "forEachIndexed" ? sema.types.unitType : sema.types.anyType
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, receiverElementType],
                returnType: lambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == "fold", argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == "reduce", argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == "sortedWith", argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType, receiverElementType],
                returnType: sema.types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == "getOrElse", isMapReceiver, argCount == 1 {
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
            return (argumentIndex: 0, expectedType: expectedType)
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
        guard isSupportedArrayMember(memberName),
              isValidArrayMemberArity(memberName, argCount: args.count)
        else {
            return nil
        }

        // Provide contextual function type for array HOF lambda inference.
        let receiverElementType = sema.types.anyType
        if let expectation = arrayMemberLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
            receiverElementType: receiverElementType,
            sema: sema
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), case .lambdaLiteral = lambdaExpr {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }

        // Mark result as collection if it returns a List
        if isArrayMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }

        let resultType = arrayMemberResultType(memberName: memberName, sema: sema)
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
        ]
        return arrayMembers.contains(memberName)
    }

    private func isValidArrayMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "toList", "toMutableList", "copyOf", "size", "isEmpty":
            argCount == 0
        case "map", "filter", "forEach", "any", "none", "fill", "get", "contains":
            argCount == 1
        case "copyOfRange":
            argCount == 2
        default:
            true
        }
    }

    private func isArrayMemberReturningCollection(_ memberName: String) -> Bool {
        ["toList", "toMutableList", "map", "filter", "copyOf", "copyOfRange"].contains(memberName)
    }

    private func arrayMemberResultType(memberName: String, sema: SemaModule) -> TypeID {
        switch memberName {
        case "size":
            sema.types.intType
        case "isEmpty", "contains", "any", "none":
            sema.types.booleanType
        case "forEach", "fill":
            sema.types.unitType
        default:
            sema.types.anyType
        }
    }

    private func arrayMemberLambdaExpectation(
        memberName: String,
        argCount: Int,
        receiverElementType: TypeID,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let boolPredicateMembers: Set = ["filter", "any", "none"]
        let oneParamMembers: Set = ["map", "filter", "forEach", "any", "none"]
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

    func isArrayLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        if sema.bindings.isCollectionExpr(receiverID) {
            let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
            if isArrayLikeType(receiverType, sema: sema, interner: interner) {
                return true
            }
            // Also check if it's marked as collection but actually an array
            // (e.g. arrayOf() results are marked as collection)
            if case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
               let symbol = sema.symbols.symbol(classType.classSymbol)
            {
                if knownNames.isArrayLikeName(symbol.name) {
                    return true
                }
            }
            // For arrayOf() results: the type is erased to Any, but marked as
            // collection. We use a heuristic: if the receiver is a collection
            // and the member is an array-only member, accept it.
            return true
        }
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
}
