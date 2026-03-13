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

        let isMapReceiver = isMapLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableListReceiver = isMutableListCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableMapReceiver = isMutableMapCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        guard isSupportedCollectionFallbackMember(
            calleeName,
            isMapReceiver: isMapReceiver,
            isMutableListReceiver: isMutableListReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            interner: interner
        ),
        isValidCollectionFallbackArity(
            calleeName,
            argCount: args.count,
            isMapReceiver: isMapReceiver,
            isMutableListReceiver: isMutableListReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
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
            interner: interner,
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

        if isCollectionReturningMember(calleeName, isMapReceiver: isMapReceiver, interner: interner) {
            sema.bindings.markCollectionExpr(id)
        }

        if let fallbackCallee = resolveCollectionFallbackCallee(
            memberName: calleeName,
            receiverID: receiverID,
            sema: sema
        ) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: fallbackCallee,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
        }

        let resultType = collectionFallbackResultType(
            memberName: calleeName,
            receiverElementType: receiverElementType,
            sema: sema,
            interner: interner
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func resolveCollectionFallbackCallee(
        memberName: InternedString,
        receiverID: ExprID,
        sema: SemaModule
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
            if let candidate = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sema.symbols.functionSignature(for: candidate) != nil
                else {
                    return false
                }
                return true
            }) {
                return candidate
            }
            queue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }

    func isSupportedCollectionFallbackMember(
        _ memberName: InternedString,
        isMapReceiver: Bool,
        isMutableListReceiver: Bool,
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
            interner.intern("mapNotNull"),
            interner.intern("filterNotNull"),
            interner.intern("forEach"),
            interner.intern("flatMap"),
            interner.intern("any"),
            interner.intern("none"),
            interner.intern("all"),
            interner.intern("fold"),
            interner.intern("reduce"),
            interner.intern("groupBy"),
            interner.intern("sortedBy"),
            interner.intern("find"),
            interner.intern("associateBy"),
            interner.intern("associateWith"),
            interner.intern("associate"),
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
            interner.intern("toList"),
            interner.intern("toTypedArray"),
            interner.intern("take"),
            interner.intern("drop"),
            interner.intern("reversed"),
            interner.intern("sorted"),
            interner.intern("distinct"),
            interner.intern("flatten"),
            interner.intern("chunked"),
            interner.intern("windowed"),
            interner.intern("sortedDescending"),
            interner.intern("sortedByDescending"),
            interner.intern("sortedWith"),
            interner.intern("partition"),
            interner.intern("filterIsInstance"),
        ]
        let mutableListOnlyMembers: Set = [
            interner.intern("sort"),
            interner.intern("sortBy"),
            interner.intern("sortByDescending"),
        ]
        let mapOnlyMembers: Set = [
            interner.intern("containsKey"),
            interner.intern("mapValues"),
            interner.intern("mapKeys"),
            knownNames.getOrDefault,
            knownNames.getOrElse,
            interner.intern("maxByOrNull"),
            interner.intern("minByOrNull"),
            interner.intern("plus"),
            interner.intern("minus"),
        ]
        if mapOnlyMembers.contains(memberName) {
            return isMapReceiver
        }
        if mutableListOnlyMembers.contains(memberName) {
            return isMutableListReceiver
        }
        if memberName == knownNames.getOrPut || memberName == knownNames.putAll {
            return isMutableMapReceiver
        }
        return collectionMembers.contains(memberName)
    }

    func isCollectionReturningMember(
        _ memberName: InternedString,
        isMapReceiver: Bool,
        interner: StringInterner
    ) -> Bool {
        let collectionReturningMembers: Set = [
            interner.intern("asSequence"), interner.intern("map"), interner.intern("filter"), interner.intern("mapNotNull"), interner.intern("filterNotNull"),
            interner.intern("flatMap"), interner.intern("sortedBy"), interner.intern("groupBy"), interner.intern("associateBy"), interner.intern("associateWith"),
            interner.intern("associate"), interner.intern("zip"), interner.intern("toList"), interner.intern("toTypedArray"), interner.intern("take"), interner.intern("drop"), interner.intern("reversed"),
            interner.intern("sorted"), interner.intern("distinct"), interner.intern("flatten"), interner.intern("chunked"), interner.intern("windowed"), interner.intern("withIndex"), interner.intern("mapIndexed"),
            interner.intern("sortedDescending"), interner.intern("sortedByDescending"), interner.intern("sortedWith"),
            interner.intern("onEach"), interner.intern("onEachIndexed"),
            interner.intern("filterIsInstance"),
        ]
        if memberName == interner.intern("mapValues") ||
            memberName == interner.intern("mapKeys") ||
            memberName == interner.intern("plus") ||
            memberName == interner.intern("minus")
        {
            return isMapReceiver
        }
        return collectionReturningMembers.contains(memberName)
    }

    func isValidCollectionFallbackArity(
        _ memberName: InternedString,
        argCount: Int,
        isMapReceiver: Bool,
        isMutableListReceiver: Bool,
        isMutableMapReceiver: Bool,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        switch memberName {
        case knownNames.size, knownNames.isEmpty, interner.intern("iterator"), interner.intern("asSequence"),
             interner.intern("toList"), interner.intern("toTypedArray"), interner.intern("reversed"), interner.intern("sorted"),
             interner.intern("distinct"), interner.intern("flatten"), interner.intern("withIndex"),
             interner.intern("maxOrNull"), interner.intern("minOrNull"), interner.intern("sortedDescending"), interner.intern("filterIsInstance"),
             interner.intern("sort"):
            return argCount == 0
        case interner.intern("filterNotNull"), interner.intern("unzip"):
            return argCount == 0
        case interner.intern("get"), interner.intern("contains"), interner.intern("containsAll"), interner.intern("indexOf"), interner.intern("lastIndexOf"), interner.intern("indexOfFirst"), interner.intern("indexOfLast"),
             interner.intern("map"), interner.intern("filter"), interner.intern("mapNotNull"), interner.intern("forEach"), interner.intern("flatMap"),
             interner.intern("any"), interner.intern("none"), interner.intern("all"),
             interner.intern("groupBy"), interner.intern("sortedBy"), interner.intern("find"), interner.intern("associateBy"), interner.intern("associateWith"), interner.intern("associate"), interner.intern("reduce"), interner.intern("take"), interner.intern("drop"), interner.intern("zip"),
             interner.intern("forEachIndexed"), interner.intern("mapIndexed"), interner.intern("sumOf"), interner.intern("chunked"), interner.intern("onEach"), interner.intern("onEachIndexed"),
             interner.intern("sortedByDescending"), interner.intern("sortedWith"), interner.intern("partition"),
             interner.intern("sortBy"), interner.intern("sortByDescending"):
            return argCount == 1
        case interner.intern("maxByOrNull"), interner.intern("minByOrNull"):
            return isMapReceiver && argCount == 1
        case interner.intern("containsKey"), interner.intern("mapValues"), interner.intern("mapKeys"):
            return isMapReceiver && argCount == 1
        case knownNames.getOrDefault:
            return isMapReceiver && argCount == 2
        case knownNames.getOrElse:
            return isMapReceiver && argCount == 1
        case knownNames.getOrPut:
            return isMutableMapReceiver && argCount == 2
        case knownNames.putAll:
            return isMutableMapReceiver && argCount == 1
        case interner.intern("plus"), interner.intern("minus"):
            return isMapReceiver && argCount == 1
        case interner.intern("fold"), interner.intern("windowed"):
            return argCount == 2
        case interner.intern("count"), interner.intern("first"), interner.intern("last"):
            return argCount == 0 || argCount == 1
        default:
            return true
        }
    }

    func collectionFallbackResultType(
        memberName: InternedString,
        receiverElementType: TypeID,
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
        ]
        if intReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.int, .nonNull))
        }

        let boolReturningMembers: Set = [
            knownNames.isEmpty, interner.intern("contains"), interner.intern("containsAll"),
            interner.intern("containsKey"),
            interner.intern("any"), interner.intern("none"), interner.intern("all")
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

        if memberName == knownNames.putAll {
            return sema.types.unitType
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

        if memberName == interner.intern("plus") || memberName == interner.intern("minus") {
            // plus/minus return the same Map type as the receiver.
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

        if memberName == knownNames.getOrDefault || memberName == knownNames.getOrElse || memberName == knownNames.getOrPut {
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

        if memberName == interner.intern("maxOrNull") || memberName == interner.intern("minOrNull")
            || memberName == interner.intern("maxByOrNull") || memberName == interner.intern("minByOrNull")
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == interner.intern("toList"),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
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

        return sema.types.anyType
    }

    func collectionFallbackLambdaExpectation(
        memberName: InternedString,
        argCount: Int,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        isMutableMapReceiver: Bool,
        interner: StringInterner,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let mapValues = interner.intern("mapValues")
        let mapKeys = interner.intern("mapKeys")
        let boolOneParamMembers: Set = [
            interner.intern("filter"),
            interner.intern("any"),
            interner.intern("none"),
            interner.intern("all"),
            interner.intern("count"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("find"),
            interner.intern("indexOfFirst"),
            interner.intern("indexOfLast"),
            interner.intern("partition"),
        ]
        let knownNames = KnownCompilerNames(interner: interner)
        let oneParamMembers: Set = [
            interner.intern("map"),
            interner.intern("filter"),
            interner.intern("mapNotNull"),
            interner.intern("forEach"),
            interner.intern("flatMap"),
            interner.intern("any"),
            interner.intern("none"),
            interner.intern("all"),
            interner.intern("groupBy"),
            interner.intern("sortedBy"),
            interner.intern("count"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("find"),
            interner.intern("associateBy"),
            interner.intern("associateWith"),
            interner.intern("associate"),
            interner.intern("sumOf"),
            interner.intern("sortedByDescending"),
            interner.intern("partition"),
            interner.intern("onEach"),
            interner.intern("sortBy"),
            interner.intern("sortByDescending"),
            interner.intern("maxByOrNull"),
            interner.intern("minByOrNull"),
        ]
        let mapOnlyMembers: Set = [
            mapValues,
            mapKeys,
            knownNames.getOrDefault,
            knownNames.getOrElse,
            interner.intern("maxByOrNull"),
            interner.intern("minByOrNull"),
        ]
        if mapOnlyMembers.contains(memberName) {
            guard isMapReceiver, argCount == 1 else {
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

        if memberName == interner.intern("forEachIndexed") || memberName == interner.intern("mapIndexed") || memberName == interner.intern("onEachIndexed"), argCount == 1 {
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

        if memberName == interner.intern("fold"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("reduce"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
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

        if memberName == knownNames.getOrElse, isMapReceiver, argCount == 1 {
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
