import Foundation

extension CallTypeChecker {
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
            "isEmpty", "first", "last", "indexOf",
            "count", "iterator",
            "map", "filter", "mapNotNull", "filterNotNull", "forEach", "flatMap",
            "any", "none", "all",
            "fold", "reduce", "groupBy", "sortedBy", "find", "associateBy", "associateWith", "associate", "zip", "unzip",
            "withIndex", "forEachIndexed", "mapIndexed", "sumOf", "maxOrNull", "minOrNull",
            "asSequence", "toList", "toTypedArray", "take", "drop", "reversed", "sorted", "distinct",
        ]
        let mapOnlyMembers: Set = ["containsKey", "mapValues", "mapKeys"]
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
            "sorted", "distinct", "withIndex", "mapIndexed",
        ]
        if memberName == "mapValues" || memberName == "mapKeys" {
            return isMapReceiver
        }
        return collectionReturningMembers.contains(memberName)
    }

    func isValidCollectionFallbackArity(_ memberName: String, argCount: Int, isMapReceiver: Bool) -> Bool {
        switch memberName {
        case "size", "isEmpty", "iterator", "asSequence", "toList", "toTypedArray", "reversed", "sorted", "distinct", "withIndex", "maxOrNull", "minOrNull":
            argCount == 0
        case "filterNotNull", "unzip":
            argCount == 0
        case "get", "contains", "indexOf",
             "map", "filter", "mapNotNull", "forEach", "flatMap",
             "any", "none", "all",
             "groupBy", "sortedBy", "find", "associateBy", "associateWith", "associate", "reduce", "take", "drop", "zip",
             "forEachIndexed", "mapIndexed", "sumOf":
            argCount == 1
        case "containsKey", "mapValues", "mapKeys":
            isMapReceiver && argCount == 1
        case "fold":
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
        let intReturningMembers: Set = ["size", "indexOf", "count", "sumOf"]
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

        if memberName == "forEach" || memberName == "forEachIndexed" {
            return sema.types.unitType
        }

        if memberName == "find" {
            return sema.types.makeNullable(receiverElementType)
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
        let boolOneParamMembers: Set = ["filter", "any", "none", "all", "count", "first", "last", "find"]
        let oneParamMembers: Set = [
            "map", "filter", "mapNotNull", "forEach", "flatMap", "any", "none", "all",
            "groupBy", "sortedBy", "count", "first", "last", "find", "associateBy", "associateWith", "associate", "sumOf",
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

        return nil
    }

    func collectionFallbackElementType(receiverID: ExprID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        else {
            return sema.types.anyType
        }
        let receiverSymbolName = sema.symbols.symbol(classType.classSymbol).map { interner.resolve($0.name) } ?? ""
        if receiverSymbolName == "Map" || receiverSymbolName.contains("Map"), classType.args.count == 2 {
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
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let shortName = interner.resolve(symbol.name)
        return [
            "List", "MutableList", "Set", "MutableSet", "Map", "MutableMap",
        ].contains(shortName)
    }

    private func isMapLikeCollectionReceiver(receiverID: ExprID, sema: SemaModule, interner: StringInterner) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)) else {
            return false
        }
        let receiverSymbolName = sema.symbols.symbol(classType.classSymbol).map { interner.resolve($0.name) } ?? ""
        return (receiverSymbolName == "Map" || receiverSymbolName.contains("Map")) && classType.args.count == 2
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
                let shortName = interner.resolve(symbol.name)
                let arrayNames: Set = ["Array", "IntArray", "LongArray", "DoubleArray", "BooleanArray", "CharArray"]
                if arrayNames.contains(shortName) {
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
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let shortName = interner.resolve(symbol.name)
        let arrayNames: Set = ["Array", "IntArray", "LongArray", "DoubleArray", "BooleanArray", "CharArray"]
        return arrayNames.contains(shortName)
    }

    // MARK: - IntRange member fallback (STDLIB-090/091/092/093)

    func tryRangeMemberFallback(
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
              sema.bindings.isRangeExpr(receiverID)
        else {
            return nil
        }

        let memberName = interner.resolve(calleeName)
        guard isSupportedRangeMember(memberName),
              isValidRangeMemberArity(memberName, argCount: args.count)
        else {
            return nil
        }

        // Provide contextual function type for range HOF lambda inference.
        if let expectation = rangeMemberLambdaExpectation(
            memberName: memberName,
            argCount: args.count,
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

        // Mark result appropriately
        if isRangeMemberReturningCollection(memberName) {
            sema.bindings.markCollectionExpr(id)
        }
        if memberName == "reversed" {
            sema.bindings.markRangeExpr(id)
        }

        let resultType = rangeMemberResultType(memberName: memberName, sema: sema)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSupportedRangeMember(_ memberName: String) -> Bool {
        let rangeMembers: Set = [
            "first", "last", "count", "contains",
            "toList", "forEach", "map",
            "reversed",
        ]
        return rangeMembers.contains(memberName)
    }

    private func isValidRangeMemberArity(_ memberName: String, argCount: Int) -> Bool {
        switch memberName {
        case "first", "last", "count", "toList", "reversed":
            argCount == 0
        case "contains", "forEach", "map":
            argCount == 1
        default:
            true
        }
    }

    private func isRangeMemberReturningCollection(_ memberName: String) -> Bool {
        ["toList", "map"].contains(memberName)
    }

    private func rangeMemberResultType(memberName: String, sema: SemaModule) -> TypeID {
        switch memberName {
        case "first", "last", "count":
            sema.types.intType
        case "contains":
            sema.types.booleanType
        case "forEach":
            sema.types.unitType
        case "reversed":
            sema.types.intType
        default:
            sema.types.anyType
        }
    }

    private func rangeMemberLambdaExpectation(
        memberName: String,
        argCount: Int,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let oneParamMembers: Set = ["forEach", "map"]
        guard oneParamMembers.contains(memberName), argCount == 1 else {
            return nil
        }
        let lambdaReturnType = memberName == "forEach" ? sema.types.unitType : sema.types.anyType
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: [sema.types.intType],
            returnType: lambdaReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: 0, expectedType: expectedType)
    }
}
