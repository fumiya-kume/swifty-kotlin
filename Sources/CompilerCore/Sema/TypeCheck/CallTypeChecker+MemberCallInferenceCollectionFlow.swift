// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallCollectionFlowSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        // Primitive-array HOFs are bundled Kotlin extensions, not collection or
        // sequence operations. Unsigned arrays currently also classify as
        // synthetic sequences, so let exact primitive-array source lookup run
        // before the generic collection-flow fast path.
        if !collectPrimitiveArraySourceHOFs(
            named: calleeName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }
        if !collectArraySourceConversionCandidates(
            named: calleeName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ).isEmpty {
            return nil
        }
        // Defer inference of lambda arguments for collection HOFs so that the
        // contextual function type (and thus implicit `it`) is available.
        let collectionHOFNames: Set = [
            "map", "filter", "filterNot", "mapNotNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
            "fold", "foldRight", "reduce", "reduceOrNull", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "foldIndexed", "foldRightIndexed", "reduceIndexed", "reduceIndexedOrNull",
            "scan", "scanIndexed", "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "scanReduce",
            "groupBy", "sortedBy", "count", "first", "last", "single", "singleOrNull", "find", "findLast", "indexOf", "lastIndexOf", "contains", "containsAll", "firstOrNull", "lastOrNull",
            "associateBy", "associateWith", "associate", "associateTo", "associateByTo", "associateWithTo", "groupByTo",
            "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo", "mapIndexedTo", "flatMapIndexedTo",
            "mapIndexedNotNullTo", "filterIndexedTo", "filterNotNullTo",
            "mapKeysTo", "mapValuesTo",
            "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed",
            "onEach", "onEachIndexed", "withIndex", "filterNotNull", "requireNoNulls",
            "sumOf", "sumBy", "sumByDouble", "min", "maxOrNull", "minOrNull",
            "indexOfFirst", "indexOfLast", "binarySearch", "binarySearchBy",
            "maxBy", "minBy", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull",
            "maxOf", "minOf",
            "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
            "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
            "sorted", "sortedDescending", "sortedByDescending", "sortedWith", "sortedArrayWith", "partition", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "distinctBy", "zip", "zipWithNext",
            "max",
            "flatten", "asSequence", "sum", "average", "reversed", "asReversed", "intersect", "union", "subtract",
            "sort", "sortBy", "sortByDescending", "sortWith",
        ]
        let flowHOFNames: Set = ["map", "filter", "collect"]
        let mapOnlyCollectionHOFNames: Set = ["mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues"]
        let mutableListOnlyCollectionHOFNames: Set = ["sort", "sortBy", "sortByDescending", "sortWith"]
        // Fallback for receivers that were never routed through a `flow { }`/operator
        // call (e.g. a user function declared `fun f(): Flow<Int>`), so the
        // `isFlowExpr`/`isFlowSymbol` bindings above were never marked. Recover the
        // same information directly from the receiver's inferred class type.
        let flowClassSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlinx"), interner.intern("coroutines"),
            interner.intern("flow"), interner.intern("Flow"),
        ])
        let receiverFlowClassType: ClassType? = if let flowClassSymbol,
                                                    case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                    classType.classSymbol == flowClassSymbol
        {
            classType
        } else {
            nil
        }
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverID) {
            true
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else if receiverFlowClassType != nil {
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
        } else if let firstArg = receiverFlowClassType?.args.first {
            switch firstArg {
            case let .invariant(t), let .out(t), let .in(t):
                t
            case .star:
                sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        let isFlowHOF = isFlowReceiver && flowHOFNames.contains(interner.resolve(calleeName))
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        let receiverClassification = receiverClassifier.classify(
            receiverID: receiverID,
            receiverType: receiverType,
            ast: ast
        )
        let isCollectionReceiver = receiverClassification.isCollectionReceiver
        let isIterableReceiver = receiverClassification.isIterableReceiver
        let isArrayReceiver = receiverClassification.isArrayReceiver
        let isMapReceiver = receiverClassification.isMapReceiver
        let isMutableListReceiver = receiverClassification.isMutableListReceiver
        let isListReceiver = receiverClassification.isListReceiver
        let isListFactoryReceiver = receiverClassification.isListFactoryReceiver
        let isSyntheticSequenceReceiver = receiverClassification.isSyntheticSequenceReceiver
        let isSequenceReceiver = receiverClassification.isSequenceReceiver
        let isSetReceiver = receiverClassification.isSetReceiver
        // KSP-979: only the plain Iterable surface and nominal user-defined
        // Iterable subtypes use the new source-backed index family. Concrete
        // collection receivers retain their existing owner-specific paths.
        let isIterableIndexReceiver = !isSequenceReceiver
            && !receiverClassifier.isCollectionLikeType(receiverType)
            && receiverClassifier.isNominalIterableType(receiverType)
        // Range/Progression aggregates have an independent runtime dispatch
        // family. Keep that ownership out of the Iterable source migration.
        let isRangeReceiver = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) != nil
        var activeCollectionHOFNames = collectionHOFNames
        if !isMutableListReceiver {
            activeCollectionHOFNames.subtract(mutableListOnlyCollectionHOFNames)
        }
        if !isSequenceReceiver {
            if !isIterableReceiver
                || receiverClassification.isListReceiver
                || receiverClassification.isSetReceiver
                || receiverClassification.isMapReceiver
            {
                activeCollectionHOFNames.remove("flatMapIndexed")
            }
            // List.zip resolves through bundled Kotlin source. Only Sequence
            // needs this generic fast path until KSP-308 removes its bridge.
            activeCollectionHOFNames.remove("zip")
        } else {
            activeCollectionHOFNames.remove("mapIndexedNotNull")
            activeCollectionHOFNames.remove("dropLastWhile")
        }
        if isMapReceiver {
            activeCollectionHOFNames.formUnion(mapOnlyCollectionHOFNames)
            // Map.flatMapTo has Iterable- and Sequence-return overloads. Let
            // the source-backed declarations reach regular overload
            // resolution instead of the collection fast path, which assumes
            // a single Collection<R>-returning lambda shape.
            activeCollectionHOFNames.remove("flatMapTo")
        }
        let calleeStr = interner.resolve(calleeName)
        let isIterableIndexFamilyHOF = ["indexOf", "indexOfFirst", "indexOfLast"].contains(calleeStr)
        // KSP-983: a nominal Iterable receiver must use the exact bundled
        // Iterable max-family declarations. Let regular overload resolution
        // select the Comparable/Float/Double and lambda-return overloads;
        // concrete List/Set/Map/Sequence paths remain under their own owners.
        let iterableMaxFamilyNames: Set = [
            "max", "maxBy", "maxByOrNull", "maxOf", "maxOfOrNull",
            "maxOfWith", "maxOfWithOrNull", "maxOrNull", "maxWith", "maxWithOrNull",
        ]
        if iterableMaxFamilyNames.contains(calleeStr),
           (isCollectionReceiver || isIterableReceiver),
           !isSequenceReceiver,
           !isSetReceiver,
           !isMapReceiver,
           !isArrayReceiver,
           !receiverClassifier.isConcreteListLikeType(receiverType)
        {
            return nil
        }
        let isIterableFilterFamilyHOF = [
            "filter", "filterIndexed", "filterIndexedTo", "filterIsInstance", "filterIsInstanceTo",
            "filterNot", "filterNotNull", "filterNotNullTo", "filterNotTo", "filterTo",
        ].contains(calleeStr)
        let isCollectionHOF = (activeCollectionHOFNames.contains(calleeStr) || isIterableFilterFamilyHOF)
            && (isCollectionReceiver
                || isSequenceReceiver
                || (isIterableIndexFamilyHOF && isIterableIndexReceiver)
                || (isIterableFilterFamilyHOF && isIterableReceiver)
                || (calleeStr == "asSequence" && isIterableReceiver)
                || ((calleeStr == "runningReduce" || calleeStr == "runningReduceIndexed") && isIterableReceiver))
            && !(calleeStr == "binarySearch"
                && isArrayReceiver)

        @discardableResult
        func bindBundledSequenceDestinationSourceFunction(
            typeArguments: [TypeID],
            parameterMapping: [Int: Int] = Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        ) -> Bool {
            guard isSequenceReceiver else {
                return false
            }
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                calleeName,
            ]
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                return receiverClassifier.isSequenceLikeType(signatureReceiver)
            }) else {
                return false
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: typeArguments,
                parameterMapping: parameterMapping
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            for arg in args {
                if let expr = ast.arena.expr(arg.expr), expr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
                }
            }
            return true
        }

        @discardableResult
        func bindBundledListSourceFunction(
            typeArguments: [TypeID],
            parameterMapping: [Int: Int] = Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) }),
            matchingParameterType: TypeID? = nil,
            receiverElementType: TypeID? = nil,
            requireMutableListReceiver: Bool = false
        ) -> Bool {
            func typeArgMatches(_ lhs: TypeArg, _ rhs: TypeArg) -> Bool {
                switch (lhs, rhs) {
                case let (.invariant(l), .invariant(r)),
                     let (.out(l), .out(r)),
                     let (.in(l), .in(r)):
                    return typeMatches(l, r)
                case (.star, .star):
                    return true
                default:
                    return false
                }
            }
            func typeMatches(_ lhs: TypeID, _ rhs: TypeID) -> Bool {
                let lk = sema.types.kind(of: lhs)
                let rk = sema.types.kind(of: rhs)
                switch (lk, rk) {
                case let (.classType(l), .classType(r)):
                    return l.classSymbol == r.classSymbol
                        && l.nullability == r.nullability
                        && l.args.count == r.args.count
                        && zip(l.args, r.args).allSatisfy(typeArgMatches)
                case let (.functionType(l), .functionType(r)):
                    return l.nullability == r.nullability
                        && l.isSuspend == r.isSuspend
                        && l.params.count == r.params.count
                        && zip(l.params, r.params).allSatisfy(typeMatches)
                        && typeMatches(l.returnType, r.returnType)
                        && l.receiver == r.receiver
                        && l.throws == r.throws
                case let (.typeParam(l), .typeParam(r)):
                    return l.symbol == r.symbol && l.nullability == r.nullability
                case let (.kClassType(l), .kClassType(r)):
                    return l.nullability == r.nullability && typeMatches(l.argument, r.argument)
                case let (.primitive(l, lNull), .primitive(r, rNull)):
                    return l == r && lNull == rNull
                case let (.nothing(lNull), .nothing(rNull)),
                     let (.any(lNull), .any(rNull)),
                     let (.stringStruct(lNull), .stringStruct(rNull)):
                    return lNull == rNull
                case (.error, .error), (.unit, .unit):
                    return true
                default:
                    return false
                }
            }
            guard (!isSequenceReceiver || isListFactoryReceiver),
                  receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
            else {
                return false
            }
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                guard receiverClassifier.isConcreteListLikeType(signatureReceiver) else {
                    return false
                }
                if requireMutableListReceiver,
                   !receiverClassifier.isMutableListCollectionType(signatureReceiver)
                {
                    return false
                }
                if let matchingParameterType,
                   !signature.parameterTypes.isEmpty,
                   !signature.typeParameterSymbols.isEmpty
                {
                    let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                    let substitution = Dictionary(uniqueKeysWithValues: typeArguments.enumerated().map {
                        (TypeVarID(rawValue: Int32($0.offset)), $0.element)
                    })
                    let substitutedParam = sema.types.substituteTypeParameters(
                        in: signature.parameterTypes[0],
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                    guard typeMatches(substitutedParam, matchingParameterType) else {
                        return false
                    }
                }
                if let receiverElementType {
                    guard extractListElementType(
                        signatureReceiver,
                        sema: sema,
                        interner: interner
                    ) == receiverElementType else {
                        return false
                    }
                }
                return true
            }) else {
                return false
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: typeArguments,
                parameterMapping: parameterMapping
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            return true
        }

        /// Bind a source-backed `List.binarySearch` / `binarySearchBy` overload using
        /// the regular overload resolver so default arguments and named labels are
        /// handled correctly.
        @discardableResult
        func bindBundledListBinarySearchSource(elementType: TypeID) -> Bool {
            let calleeStr = interner.resolve(calleeName)
            guard calleeStr == "binarySearch" || calleeStr == "binarySearchBy" else { return false }
            guard (!isSequenceReceiver || isListFactoryReceiver),
                  receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
            else {
                return false
            }
            let sourceFQName = [interner.intern("kotlin"), interner.intern("collections"), calleeName]
            let candidates = sema.symbols.lookupAll(fqName: sourceFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                return receiverClassifier.isConcreteListLikeType(signatureReceiver)
            }
            guard !candidates.isEmpty else { return false }

            let callArgs: [CallArg] = args.map { arg in
                CallArg(label: arg.label, isSpread: arg.isSpread, type: sema.bindings.exprTypes[arg.expr] ?? sema.types.anyType)
            }
            let callExpr = CallExpr(range: range, calleeName: calleeName, args: callArgs)
            let resolved = OverloadResolver().resolveCall(
                candidates: candidates,
                call: callExpr,
                expectedType: sema.types.intType,
                implicitReceiverType: receiverType,
                ctx: sema
            )
            guard let chosenCallee = resolved.chosenCallee else { return false }
            _ = bindCallAndResolveReturnType(id, chosen: chosenCallee, resolved: resolved, sema: sema)
            return true
        }

        @discardableResult
        func bindBundledIterableSourceFunction(
            typeArguments: [TypeID],
            receiverElementType: TypeID? = nil
        ) -> Bool {
            guard !isSequenceReceiver,
                  isCollectionReceiver
                  || (isIterableReceiver && (calleeStr == "drop"
                      || calleeStr == "dropWhile"
                      || calleeStr == "runningReduce"
                      || calleeStr == "runningReduceIndexed"
                      || isIterableFilterFamilyHOF))
                    || (isIterableIndexReceiver && isIterableIndexFamilyHOF)
            else {
                return false
            }
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            let receiverForLookup = sema.types.makeNonNullable(receiverType)
            guard let (actualReceiverClassType, _) = resolveClassTypeSymbol(receiverForLookup, sema: sema) else {
                return false
            }
            let actualClassSymbol = actualReceiverClassType.classSymbol
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                if let receiverElementType,
                   getCollectionElementType(signatureReceiver, sema: sema, interner: interner) != receiverElementType {
                    return false
                }
                if isCollectionLikeType(signatureReceiver, sema: sema, interner: interner),
                   let (sigClassType, _) = resolveClassTypeSymbol(signatureReceiver, sema: sema),
                   sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol) {
                    return true
                }
                guard let (sigClassType, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema) else {
                    return false
                }
                if receiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Iterable"),
                ], sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol) {
                    return true
                }
                return false
            }) else {
                return false
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: typeArguments,
                parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            return true
        }

        // KSP-969: bind the generic Iterable drop family for a statically
        // Iterable receiver as well as concrete collection receivers. List
        // overloads are attempted first so the more specific source-backed
        // declaration keeps winning for List values.
        let isIterableDropFamily = !isSequenceReceiver
            && (calleeStr == "drop" || calleeStr == "dropWhile")
            && (isCollectionReceiver || isIterableReceiver)
        if isIterableDropFamily {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            guard args.count == 1 else {
                return nil
            }

            let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner)
            let resultType = if let listSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let didBindSource: Bool
            if calleeStr == "drop" {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                didBindSource = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                    || bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
            } else {
                let predicateType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.booleanType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: predicateType)
                didBindSource = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                    || bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                if didBindSource,
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            guard didBindSource else {
                return nil
            }
            sema.bindings.markCollectionExpr(id)

            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // KSP-970: bind the generic Iterable element family explicitly so a
        // plain Iterable receiver cannot fall through to the legacy runtime
        // fallback. List source overloads remain preferred for concrete Lists.
        if !isSequenceReceiver,
           (calleeStr == "elementAt" || calleeStr == "elementAtOrElse" || calleeStr == "elementAtOrNull"),
           (isCollectionReceiver || isIterableReceiver)
        {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let expectedArgumentCount = calleeStr == "elementAtOrElse" ? 2 : 1
            guard args.count == expectedArgumentCount else {
                return nil
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            if calleeStr == "elementAtOrElse" {
                let defaultValueType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType],
                    returnType: collectionElementType
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: defaultValueType
                )
            }
            let didBindSource = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                || bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
            guard didBindSource else {
                return nil
            }
            for argument in args
            where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
            }
            sema.bindings.markCollectionExpr(id)
            let resultType = calleeStr == "elementAtOrNull"
                ? sema.types.makeNullable(collectionElementType)
                : collectionElementType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        /// Bind the source-backed `Iterable<T>.sum()` overload without allowing a
        /// concrete List overload to win. The regular collection fast path only
        /// knows the historical Int result, while the Iterable family has ten
        /// receiver-element/return-type pairs.
        func bindBundledIterableSumSource() -> TypeID? {
            guard !isSequenceReceiver,
                  !isRangeReceiver,
                  isCollectionReceiver,
                  args.isEmpty,
                  !receiverClassifier.isConcreteListLikeType(receiverType)
            else {
                return nil
            }
            let collectionElementType = getCollectionElementType(
                receiverType,
                sema: sema,
                interner: interner
            )
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            let chosen = sema.symbols.lookupAll(fqName: sourceFQName).first { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.isEmpty,
                      let signatureReceiver = signature.receiverType,
                      receiverClassifier.isIterableLikeType(signatureReceiver)
                else {
                    return false
                }
                return extractIterableOrSequenceElementType(
                    signatureReceiver,
                    sema: sema,
                    interner: interner
                ) == collectionElementType
            }
            guard let chosen,
                  let signature = sema.symbols.functionSignature(for: chosen)
            else {
                return nil
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [],
                parameterMapping: [:]
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            return signature.returnType
        }

        /// Bind one of the five source-backed `Iterable<T>.sumOf` overloads by
        /// the selector body's actual return type. This is the target-specific
        /// counterpart of the general collection HOF path; List and Sequence
        /// overload resolution remains on their existing paths.
        func bindBundledIterableSumOfSource() -> TypeID? {
            guard !isSequenceReceiver,
                  !isRangeReceiver,
                  isCollectionReceiver,
                  args.count == 1,
                  !receiverClassifier.isConcreteListLikeType(receiverType)
            else {
                return nil
            }
            let collectionElementType = getCollectionElementType(
                receiverType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.anyType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let selectorReturnType = inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            let chosen = sema.symbols.lookupAll(fqName: sourceFQName).first { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let signatureReceiver = signature.receiverType,
                      receiverClassifier.isIterableLikeType(signatureReceiver),
                      extractIterableOrSequenceElementType(
                          signatureReceiver,
                          sema: sema,
                          interner: interner
                      ) == collectionElementType,
                      case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]),
                      selectorType.params.count == 1,
                      selectorType.params[0] == collectionElementType
                else {
                    return false
                }
                return selectorType.returnType == selectorReturnType
            }
            guard let chosen,
                  let signature = sema.symbols.functionSignature(for: chosen)
            else {
                return nil
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [collectionElementType],
                parameterMapping: [0: 0]
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
            }
            return signature.returnType
        }

        @discardableResult
        func bindBundledIterableFlatMapSourceFunction(
            collectionElementType: TypeID,
            resultElementType: TypeID,
            returnsSequence: Bool,
            destinationType: TypeID? = nil
        ) -> Bool {
            // KSP-974: select the Iterable receiver's overload by the lambda
            // return type before lowering, including indexed and destination transforms.
            guard !isSequenceReceiver,
                  isIterableReceiver,
                  !receiverClassification.isListReceiver,
                  !receiverClassification.isSetReceiver,
                  !receiverClassification.isMapReceiver
            else {
                return false
            }
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            let iterableFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
            let sequenceFQName = [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("Sequence"),
            ]
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType,
                      let receiverSymbol = resolveClassTypeSymbol(signatureReceiver, sema: sema)?.1,
                      receiverSymbol.fqName == iterableFQName,
                      let transformTypeIndex = signature.parameterTypes.indices.last,
                      case let .functionType(transformType) = sema.types.kind(of: signature.parameterTypes[transformTypeIndex]),
                      let returnSymbol = resolveClassTypeSymbol(transformType.returnType, sema: sema)?.1
                else {
                    return false
                }
                let returnFQName = returnSymbol.fqName
                if returnsSequence {
                    return returnFQName == sequenceFQName
                }
                return returnFQName == iterableFQName
            }) else {
                return false
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: destinationType.map {
                    [collectionElementType, resultElementType, $0]
                } ?? [collectionElementType, resultElementType],
                parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            for argument in args {
                if let lambdaExpr = ast.arena.expr(argument.expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                }
            }
            return true
        }

        @discardableResult
        func bindBundledAsSequenceSourceIfAvailable(typeArguments: [TypeID]) -> Bool {
            // Sequence.asSequence() is an identity conversion. The bundled
            // Iterable.asSequence() implementation is only valid for an
            // Iterable receiver; binding it to Sequence produces an empty
            // result because Sequence is not an Iterable in Kotlin.
            guard !isSequenceReceiver,
                  (isCollectionReceiver || isIterableReceiver),
                  !isArrayReceiver,
                  args.isEmpty else {
                return false
            }
            guard interner.resolve(calleeName) == "asSequence" else {
                return false
            }
            // KSP-1003: Map.asSequence() has its own source-backed overload.
            // Do not let the generic Iterable fallback treat Map as a
            // collection expression; Map is not an Iterable in Kotlin.
            if isMapReceiver, bindBundledMapSourceFunction() {
                return true
            }
            let sourcePackages: [[InternedString]] = [
                [interner.intern("kotlin"), interner.intern("sequences")],
                [interner.intern("kotlin"), interner.intern("collections")],
            ]
            for packageFQName in sourcePackages {
                if let chosenCallee = sema.symbols.lookupAll(fqName: packageFQName + [calleeName]).first(where: { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.isSourceBackedSymbol(candidate),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == args.count,
                          let signatureReceiver = signature.receiverType
                    else {
                        return false
                    }
                    let signatureIsSequence = receiverClassifier.isSequenceLikeType(signatureReceiver)
                    // Sequence<T> is marked as a collection expression while
                    // its static type is being inferred. Do not let that
                    // heuristic select Iterable<T>.asSequence(): Kotlin's
                    // Sequence<T>.asSequence() overload is the identity
                    // conversion and must win for a Sequence receiver.
                    if isSequenceReceiver {
                        return signatureIsSequence
                    }
                    if signatureIsSequence {
                        return false
                    }
                    return receiverClassifier.isIterableLikeType(signatureReceiver)
                        || receiverClassifier.isCollectionLikeType(signatureReceiver)
                }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: typeArguments,
                        parameterMapping: [:]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                    return true
                }
            }
            return false
        }

        func typeIDFromTypeArg(_ typeArg: TypeArg) -> TypeID {
            switch typeArg {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
        }

        func containsTypeParameter(_ typeID: TypeID, symbols: Set<SymbolID>) -> Bool {
            switch sema.types.kind(of: typeID) {
            case let .typeParam(typeParam):
                symbols.contains(typeParam.symbol)
            case let .classType(classType):
                classType.args.contains { arg in
                    containsTypeParameter(arg, symbols: symbols)
                }
            case let .functionType(functionType):
                (functionType.receiver.map { containsTypeParameter($0, symbols: symbols) } ?? false)
                    || functionType.params.contains { containsTypeParameter($0, symbols: symbols) }
                    || containsTypeParameter(functionType.returnType, symbols: symbols)
                    || functionType.contextReceivers.contains { containsTypeParameter($0, symbols: symbols) }
            case let .kClassType(kClassType):
                containsTypeParameter(kClassType.argument, symbols: symbols)
            case let .intersection(parts):
                parts.contains { containsTypeParameter($0, symbols: symbols) }
            default:
                false
            }
        }

        func containsTypeParameter(_ typeArg: TypeArg, symbols: Set<SymbolID>) -> Bool {
            switch typeArg {
            case let .invariant(type), let .out(type), let .in(type):
                containsTypeParameter(type, symbols: symbols)
            case .star:
                false
            }
        }

        func mapExtraTypeArgument(
            signatureReturnType: TypeID,
            actualLambdaReturnType: TypeID,
            extraSymbol: SymbolID,
            sema: SemaModule,
            interner: StringInterner
        ) -> TypeID? {
            let extraSymbols: Set<SymbolID> = [extraSymbol]
            guard containsTypeParameter(signatureReturnType, symbols: extraSymbols) else {
                return nil
            }
            switch sema.types.kind(of: signatureReturnType) {
            case let .typeParam(typeParam) where typeParam.symbol == extraSymbol:
                if typeParam.nullability == .nullable {
                    return sema.types.makeNonNullable(actualLambdaReturnType)
                }
                return actualLambdaReturnType
            case let .classType(classType):
                if classType.args.count == 1,
                   containsTypeParameter(typeIDFromTypeArg(classType.args[0]), symbols: extraSymbols) {
                    return extractIterableOrSequenceElementType(actualLambdaReturnType, sema: sema, interner: interner)
                }
            default:
                break
            }
            return nil
        }

        /// Bind a member call to a bundled Kotlin-source extension declared on a
        /// collection owner interface (`Map`, `Set`, …), inferring the owner's type
        /// arguments from the receiver and any remaining ones from lambda returns.
        @discardableResult
        func bindBundledCollectionOwnerSourceFunction(
            receiverTypeArgumentCount: Int,
            matchingLambdaReturnType: TypeID? = nil,
            isOwnerSymbol: (SemanticSymbol) -> Bool
        ) -> Bool {
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            let receiverForLookup = sema.types.makeNonNullable(receiverType)
            guard let (actualReceiverClassType, _) = resolveClassTypeSymbol(receiverForLookup, sema: sema),
                  actualReceiverClassType.args.count >= receiverTypeArgumentCount
            else {
                return false
            }
            let actualClassSymbol = actualReceiverClassType.classSymbol
            let sourceCandidates = sema.symbols.lookupAll(fqName: sourceFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                guard let (sigClassType, sigSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema),
                      isOwnerSymbol(sigSymbol)
                else {
                    return false
                }
                return sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol)
            }
            let chosenCallee: SymbolID?
            if let matchingLambdaReturnType {
                let exactCandidate = sourceCandidates.first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.parameterTypes.contains { parameterType in
                        guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                            return false
                        }
                        return functionType.returnType == matchingLambdaReturnType
                            || (sema.types.isSubtype(functionType.returnType, matchingLambdaReturnType)
                                && sema.types.isSubtype(matchingLambdaReturnType, functionType.returnType))
                    }
                })
                chosenCallee = exactCandidate ?? sourceCandidates.first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.parameterTypes.contains { parameterType in
                        guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                            return false
                        }
                        if case .typeParam = sema.types.kind(of: functionType.returnType) {
                            return true
                        }
                        return false
                    }
                }) ?? sourceCandidates.first
            } else {
                chosenCallee = sourceCandidates.first
            }
            guard let chosenCallee,
                  let signature = sema.symbols.functionSignature(for: chosenCallee)
            else {
                return false
            }
            let baseCount = min(
                max(signature.classTypeParameterCount, actualReceiverClassType.args.count),
                signature.typeParameterSymbols.count
            )
            var typeArguments: [TypeID] = []
            for index in 0..<baseCount {
                if index < actualReceiverClassType.args.count {
                    typeArguments.append(typeIDFromTypeArg(actualReceiverClassType.args[index]))
                } else {
                    typeArguments.append(sema.types.anyType)
                }
            }
            let extraParamSymbols = Array(signature.typeParameterSymbols.dropFirst(typeArguments.count))
            if !extraParamSymbols.isEmpty {
                var inferredExtras: [TypeID?] = Array(repeating: nil, count: extraParamSymbols.count)
                // Destination-type parameters such as `C`/`M` appear directly in
                // the first value parameter, so infer them from the actual
                // destination before inferring transform-result parameters.
                if isMapReceiver {
                    for (argIndex, parameterType) in signature.parameterTypes.enumerated() {
                        guard argIndex < args.count,
                              case let .typeParam(parameterTypeParam) = sema.types.kind(of: parameterType),
                              let extraIndex = extraParamSymbols.firstIndex(of: parameterTypeParam.symbol)
                        else {
                            continue
                        }
                        let actualArgumentType = sema.bindings.exprTypes[args[argIndex].expr] ?? sema.types.anyType
                        inferredExtras[extraIndex] = sema.types.makeNonNullable(actualArgumentType)
                    }
                }
                var inferredLambdaArgExpr: ExprID?
                for (argIndex, paramType) in signature.parameterTypes.enumerated() {
                    guard case let .functionType(fn) = sema.types.kind(of: paramType) else {
                        continue
                    }
                    let paramReturnType = fn.returnType
                    guard containsTypeParameter(paramReturnType, symbols: Set(extraParamSymbols)) else {
                        continue
                    }
                    let actualArgExpr = args[argIndex].expr
                    let actualLambdaReturnType = inferredLambdaReturnType(argExpr: actualArgExpr, ast: ast, sema: sema)
                    var extrasForParam: [TypeID] = []
                    for (extraIndex, extraSymbol) in extraParamSymbols.enumerated() {
                        if let inferred = inferredExtras[extraIndex] {
                            extrasForParam.append(inferred)
                            continue
                        }
                        if let inferred = mapExtraTypeArgument(
                            signatureReturnType: paramReturnType,
                            actualLambdaReturnType: actualLambdaReturnType,
                            extraSymbol: extraSymbol,
                            sema: sema,
                            interner: interner
                        ) {
                            extrasForParam.append(inferred)
                        } else {
                            extrasForParam.append(sema.types.anyType)
                        }
                    }
                    if extrasForParam.count == extraParamSymbols.count {
                        inferredExtras = extrasForParam.map(Optional.some)
                        inferredLambdaArgExpr = actualArgExpr
                        break
                    }
                }
                if let inferredLambdaArgExpr {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(inferredLambdaArgExpr)
                }
                typeArguments.append(contentsOf: inferredExtras.map { $0 ?? sema.types.anyType })
                if typeArguments.count < signature.typeParameterSymbols.count {
                    typeArguments.append(contentsOf: Array(repeating: sema.types.anyType, count: signature.typeParameterSymbols.count - typeArguments.count))
                }
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: typeArguments,
                parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            return true
        }

        @discardableResult
        func bindBundledMapSourceFunction(matchingLambdaReturnType: TypeID? = nil) -> Bool {
            guard isMapReceiver, !isSequenceReceiver else {
                return false
            }
            return bindBundledCollectionOwnerSourceFunction(
                receiverTypeArgumentCount: 2,
                matchingLambdaReturnType: matchingLambdaReturnType
            ) {
                knownNames.isMapLikeSymbol($0)
            }
        }

        /// KSP-1011: Bind `map.iterator()` straight to the bundled
        /// `Map<out K, V>.__kspMapIterator()` source declaration. That
        /// declaration is deliberately *not* named `iterator`: a second
        /// source-backed function named `iterator` in `kotlin.collections`
        /// widens the by-simple-name candidate pool that the generic
        /// `Iterable<T>.iterator()` call inside bundled HOFs (`reduce`,
        /// `reduceIndexed`, ...) resolves against, and that lookup does not
        /// filter candidates by nominal receiver compatibility — it matched
        /// this Map-only function for every Iterable receiver, including
        /// ranges, and crashed at runtime. Keeping the call-site name
        /// (`iterator`) but the target name mangled avoids widening that
        /// pool while still binding the correct implementation here.
        func bindBundledMapIteratorSourceFunction() -> TypeID? {
            // MutableMap.iterator() has a more specific source-backed overload
            // whose mutable entry type and runtime bridge must win. Let the
            // regular member resolver select that overload instead of binding
            // the read-only Map iterator first.
            guard isMapReceiver,
                  !isSequenceReceiver,
                  !receiverClassifier.isMutableMapType(receiverType),
                  calleeStr == "iterator",
                  args.isEmpty
            else {
                return nil
            }
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("__kspMapIterator"),
            ]
            let receiverForLookup = sema.types.makeNonNullable(receiverType)
            guard let (actualReceiverClassType, _) = resolveClassTypeSymbol(receiverForLookup, sema: sema),
                  actualReceiverClassType.args.count >= 2
            else {
                return nil
            }
            let actualClassSymbol = actualReceiverClassType.classSymbol
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.isEmpty,
                      let signatureReceiver = signature.receiverType,
                      let (sigClassType, sigSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema)
                else {
                    return false
                }
                return knownNames.isMapLikeSymbol(sigSymbol)
                    && sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol)
            }),
                  let signature = sema.symbols.functionSignature(for: chosenCallee)
            else {
                return nil
            }

            let typeArguments = actualReceiverClassType.args.prefix(2).map(typeIDFromTypeArg)
            guard typeArguments.count == signature.typeParameterSymbols.count else {
                return nil
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: typeArguments,
                parameterMapping: [:]
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))

            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var substitution: [TypeVarID: TypeID] = [:]
            for (symbol, type) in zip(signature.typeParameterSymbols, typeArguments) {
                if let typeVar = typeVarBySymbol[symbol] {
                    substitution[typeVar] = type
                }
            }
            return sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
        }

        if let mapIteratorType = bindBundledMapIteratorSourceFunction() {
            sema.bindings.bindExprType(id, type: mapIteratorType)
            return mapIteratorType
        }

        // KSP-432: Set members are source-backed in Stdlib/kotlin/collections/SetHOF.kt.
        @discardableResult
        func bindBundledSetSourceFunction() -> Bool {
            guard isSetReceiver, !isSequenceReceiver, !isMapReceiver else {
                return false
            }
            return bindBundledCollectionOwnerSourceFunction(receiverTypeArgumentCount: 1) {
                knownNames.isSetLikeSymbol($0)
            }
        }

        // KSP-1021: MutableList source extensions share names with retained
        // synthetic member fallbacks. Bind the exact source overload before the
        // generic collection/member resolver can select the fallback by name and
        // arity alone. The mutable receiver check also keeps List.asReversed()
        // read-only when the static receiver is only List<T>.
        let isMutableListPredicateName = calleeStr == "removeAll" || calleeStr == "retainAll"
        let hasMutableListPredicateArgument = args.count == 1
            && (ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false)
        if isMutableListReceiver,
           (!isMutableListPredicateName || hasMutableListPredicateArgument),
           [
               "asReversed", "remove", "removeFirst", "removeFirstOrNull",
               "removeLast", "removeLastOrNull", "removeAll", "retainAll",
               "reverse", "shuffle",
           ].contains(calleeStr)
        {
            let elementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let mutableSourceArguments: [TypeID] = [elementType]
            let bound: Bool
            let resultType: TypeID

            func bindMutableCollectionElementRemove() -> Bool {
                guard args.count == 1, args[0].label == nil else { return false }
                let argumentType = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals
                )
                guard sema.types.isSubtype(argumentType, elementType) else { return false }
                let mutableCollectionRemoveFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableCollection"),
                    interner.intern("remove"),
                ]
                guard let chosenCallee = sema.symbols.lookupAll(fqName: mutableCollectionRemoveFQName)
                    .first(where: { candidate in
                        sema.symbols.symbol(candidate)?.kind == .function
                            && sema.symbols.externalLinkName(for: candidate) == "__kk_mutable_collection_remove"
                    })
                else {
                    return false
                }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: mutableSourceArguments,
                    parameterMapping: [0: 0]
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                return true
            }

            switch calleeStr {
            case "asReversed" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                )
                resultType = receiverType
            case "remove" where args.count == 1 && args[0].label == interner.intern("index"):
                _ = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: sema.types.intType
                )
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                )
                resultType = elementType
            case "remove" where args.count == 1 && args[0].label == nil:
                bound = bindMutableCollectionElementRemove()
                resultType = sema.types.booleanType
            case "removeFirst" where args.isEmpty,
                 "removeLast" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                )
                resultType = elementType
            case "removeFirstOrNull" where args.isEmpty,
                 "removeLastOrNull" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                )
                resultType = sema.types.makeNullable(elementType)
            case "removeAll" where args.count == 1,
                 "retainAll" where args.count == 1:
                let predicateType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: sema.types.booleanType
                )))
                if let argExpr = ast.arena.expr(args[0].expr), argExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: predicateType
                )
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    matchingParameterType: predicateType,
                    requireMutableListReceiver: true
                )
                if bound, let argExpr = ast.arena.expr(args[0].expr), argExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
                resultType = sema.types.booleanType
            case "reverse" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                )
                resultType = sema.types.unitType
            case "shuffle" where args.isEmpty || args.count == 1:
                if let randomArg = args.first {
                    _ = driver.inferExpr(randomArg.expr, ctx: ctx, locals: &locals)
                }
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                )
                resultType = sema.types.unitType
            default:
                return nil
            }

            guard bound else { return nil }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "asFlow",
           args.isEmpty,
           isCollectionReceiver || isSequenceReceiver
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
            // KSP-674: resolve to the bundled `Iterable<T>.asFlow()` Kotlin
            // source (kotlinx.coroutines.flow) when present, so Lowering runs the
            // real `flow { }`-composed body instead of the removed
            // `kk_flow_as_flow` bridge. Fall back to type-only binding otherwise.
            let asFlowFQName = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("flow"),
                calleeName,
            ]
            if isCollectionReceiver,
               let chosenCallee = sema.symbols.lookupAll(fqName: asFlowFQName).first(where: { candidate in
                   guard let symbol = sema.symbols.symbol(candidate),
                         symbol.kind == .function,
                         sema.symbols.isSourceBackedSymbol(candidate),
                         let signature = sema.symbols.functionSignature(for: candidate),
                         signature.parameterTypes.isEmpty,
                         signature.receiverType != nil
                   else {
                       return false
                   }
                   return true
               })
            {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: [elementType],
                    parameterMapping: [:]
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
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

        if interner.resolve(calleeName) == "zip",
           !isSequenceReceiver,
           isCollectionReceiver,
           !args.isEmpty
        {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let otherType = sema.bindings.exprTypes[args[0].expr]
                ?? driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let otherElementType: TypeID
            if case let .classType(otherClassType) = sema.types.kind(of: sema.types.makeNonNullable(otherType)),
               let firstArg = otherClassType.args.first
            {
                otherElementType = switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                otherElementType = sema.types.anyType
            }

            let resultElementType: TypeID
            let sourceTypeArguments: [TypeID]
            if args.count >= 2 {
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, otherElementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultElementType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                sourceTypeArguments = [collectionElementType, otherElementType, resultElementType]
            } else if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                resultElementType = sema.types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.invariant(collectionElementType), .invariant(otherElementType)],
                    nullability: .nonNull
                )))
                sourceTypeArguments = [collectionElementType, otherElementType]
            } else {
                resultElementType = sema.types.anyType
                sourceTypeArguments = [collectionElementType, otherElementType]
            }

            let resultType = if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(resultElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            _ = bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterIsInstance<R>() — reified type parameter, returns List<R> or Sequence<R>
        if interner.resolve(calleeName) == "filterIsInstance",
           args.isEmpty,
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
        {
            let filterType = explicitTypeArgs.first ?? sema.types.anyType
            let receiverElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let resultType = if isSequenceReceiver {
                makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: filterType
                )
            } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(filterType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            if resultType != sema.types.anyType {
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.markCollectionExpr(id)
                let didBindSource: Bool = if isSequenceReceiver {
                    bindBundledSequenceDestinationSourceFunction(
                        typeArguments: [filterType],
                        parameterMapping: [:]
                    )
                } else if receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver {
                    bindBundledListSourceFunction(typeArguments: [filterType], parameterMapping: [:])
                } else {
                    bindBundledIterableSourceFunction(typeArguments: [filterType])
                }
                let ownerFQName = isSequenceReceiver
                    ? [interner.intern("kotlin"), interner.intern("sequences")]
                    : KnownCompilerNames(interner: interner).kotlinCollectionsListFQName
                if !didBindSource,
                   let chosenCallee = sema.symbols.lookupAll(fqName: ownerFQName + [calleeName]).first(where: { symbolID in
                       guard let signature = sema.symbols.functionSignature(for: symbolID),
                             signature.parameterTypes.count == args.count
                       else {
                           return false
                       }
                       // Bundled Kotlin-source declarations (e.g. List<T>.filter) share
                       // this fqName with Map/Set/Iterable fallback candidates once their
                       // synthetic stub is suppressed. Skip a receiver-specific bundled
                       // declaration when the concrete receiver kind doesn't match it, so
                       // non-List collection fallbacks (Map.filter, etc.) aren't
                       // incorrectly bound to the List-only bundled function.
                       if let signatureReceiver = signature.receiverType,
                          sema.symbols.isSourceBackedSymbol(symbolID),
                          receiverClassifier.isConcreteListLikeType(signatureReceiver),
                          !receiverClassifier.isConcreteListLikeType(receiverType) {
                           return false
                       }
                       return true
                   }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [receiverElementType, filterType],
                        parameterMapping: [:]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }
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
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
            let destinationElementType: TypeID = if case let .classType(destinationClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                    let firstArg = destinationClassType.args.first
            {
                switch firstArg {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            if isSequenceReceiver {
                _ = bindBundledSequenceDestinationSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                )
            } else if receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver {
                bindBundledListSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                )
            } else {
                _ = bindBundledIterableSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType]
                )
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterNotNull() — bundled Kotlin source implementation with sequence runtime fallback.
        if interner.resolve(calleeName) == "filterNotNull",
           args.isEmpty,
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
        {
            let receiverElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let resultElementType = sema.types.makeNonNullable(receiverElementType)
            let resultType: TypeID = if isSequenceReceiver {
                makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: resultElementType
                )
            } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(resultElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            if isSequenceReceiver {
                let memberFQName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    calleeName,
                ]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.isSourceBackedSymbol(candidate),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == args.count,
                          let signatureReceiver = signature.receiverType
                    else {
                        return false
                    }
                    return receiverClassifier.isSequenceLikeType(signatureReceiver)
                }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [resultElementType],
                        parameterMapping: [:]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }
            } else if receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver {
                _ = bindBundledListSourceFunction(typeArguments: [resultElementType])
            } else {
                _ = bindBundledIterableSourceFunction(typeArguments: [resultElementType])
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterNotNullTo(destination) — no lambda, returns destination type (STDLIB-SEQ-021)
        if interner.resolve(calleeName) == "filterNotNullTo",
           args.count == 1,
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
            let destinationElementType: TypeID = if case let .classType(destinationClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                    let firstArg = destinationClassType.args.first
            {
                switch firstArg {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            if !isSequenceReceiver,
               receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
            {
                bindBundledListSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                )
            } else if !isSequenceReceiver {
                _ = bindBundledIterableSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType]
                )
            } else {
                _ = bindBundledSequenceDestinationSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                )
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "binarySearch",
           receiverClassifier.isConcreteListLikeType(receiverType),
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
            _ = bindBundledListBinarySearchSource(elementType: collectionElementType)
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // --- Collection higher-order functions (STDLIB-005) ---
        if isCollectionHOF {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let collectionMapTypes: (key: TypeID, value: TypeID) = {
                guard let classType = resolveClassType(receiverType, sema: sema),
                      classType.args.count >= 2
                else {
                    return (sema.types.anyType, sema.types.anyType)
                }
                let keyType: TypeID = switch classType.args[0] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
                let valueType: TypeID = switch classType.args[1] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
                return (keyType, valueType)
            }()

            func bindBundledSequenceAggregateSource(typeArguments: [TypeID]) {
                guard isSequenceReceiver else {
                    return
                }
                let sourcePackages: [[InternedString]] = [
                    [interner.intern("kotlin"), interner.intern("sequences")],
                    [interner.intern("kotlin"), interner.intern("collections")],
                ]
                var chosenCallee: SymbolID?
                for packageFQName in sourcePackages {
                    if let candidate = sema.symbols.lookupAll(fqName: packageFQName + [calleeName]).first(where: { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              sema.symbols.isSourceBackedSymbol(candidate),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              signature.parameterTypes.count == args.count,
                              let signatureReceiver = signature.receiverType
                        else {
                            return false
                        }
                        return receiverClassifier.isSequenceLikeType(signatureReceiver)
                    }) {
                        chosenCallee = candidate
                        break
                    }
                }
                guard let chosenCallee else {
                    return
                }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                for arg in args {
                    if let expr = ast.arena.expr(arg.expr), expr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
                    }
                }
            }

            // KSP-441: Source-backed Sequence transforms (map/filter/etc.) live in
            // kotlin.sequences as top-level extensions. Prefer them over the synthetic
            // runtime stubs so the object-expression pipeline runs.
            // `allowIterableReceiver` lets a plain `Iterable<T>`-typed receiver
            // (e.g. `val x: Iterable<Int> = setOf(...)`) fall back to the
            // bundled `Sequence<T>` source implementation for aggregate HOFs
            // that have no direct Iterable source declaration. The Sequence
            // source bodies are plain `for (element in this)` iteration, so
            // they are valid for a Set/other Iterable receiver as for a real
            // Sequence.
            func bindBundledSequenceSourceIfAvailable(
                resultType: TypeID,
                otherElementType: TypeID? = nil,
                overrideTypeArguments: [TypeID]? = nil,
                allowIterableReceiver: Bool = false
            ) -> Bool {
                guard isSequenceReceiver || (allowIterableReceiver && isCollectionReceiver) else {
                    return false
                }
                let knownNames = KnownCompilerNames(interner: interner)
                let resultElementType: TypeID = if let classType = resolveClassType(resultType, sema: sema),
                                                      classType.args.count >= 1,
                                                      let classSymbolInfo = sema.symbols.symbol(classType.classSymbol),
                                                      knownNames.isSequenceSymbol(classSymbolInfo) {
                    switch classType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id):
                        id
                    case .star:
                        collectionElementType
                    }
                } else {
                    collectionElementType
                }
                let sourcePackages: [[InternedString]] = [
                    [interner.intern("kotlin"), interner.intern("sequences")],
                    [interner.intern("kotlin"), interner.intern("collections")],
                ]
                var chosenCallee: SymbolID?
                for packageFQName in sourcePackages {
                    let candidates = sema.symbols.lookupAll(fqName: packageFQName + [calleeName])

                    if let candidate = candidates.first(where: { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              sema.symbols.isSourceBackedSymbol(candidate),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              signature.parameterTypes.count == args.count,
                              let signatureReceiver = signature.receiverType
                        else {
                            return false
                        }
                        return receiverClassifier.isSequenceLikeType(signatureReceiver)
                    }) {
                        chosenCallee = candidate
                        break
                    }
                }
                guard let chosenCallee else {
                    return false
                }
                let typeParamCount = sema.symbols.functionSignature(for: chosenCallee)?.typeParameterSymbols.count ?? 0
                let typeArguments: [TypeID] = if let overrideTypeArguments {
                    overrideTypeArguments
                } else if typeParamCount == 1 {
                    [resultElementType]
                } else if typeParamCount == 2 {
                    if let otherElementType {
                        [collectionElementType, otherElementType]
                    } else {
                        [collectionElementType, resultElementType]
                    }
                } else if typeParamCount == 3, let otherElementType {
                    [collectionElementType, otherElementType, resultElementType]
                } else {
                    []
                }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                for arg in args {
                    if let expr = ast.arena.expr(arg.expr), expr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
                    }
                }
                return true
            }

            var sourceBackedSequenceAggregateTypeArguments: [TypeID]?
            let resultType: TypeID
            let listResultType: TypeID = if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let destinationCollectionHOFs: Set = [
                "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo",
                "mapIndexedTo", "mapIndexedNotNullTo", "flatMapIndexedTo", "associateTo",
                "filterIndexedTo", "mapKeysTo", "mapValuesTo",
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
                        returnType: !isListReceiver && !isSequenceReceiver && !isArrayReceiver && !isMapReceiver
                            ? sema.types.nullableAnyType
                            : destinationElementType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "flatMapTo":
                    {
                        // The Iterable and Sequence overloads are distinguished by
                        // the lambda return type; infer that return before binding.
                        if !isSequenceReceiver,
                           isIterableReceiver,
                           !receiverClassification.isListReceiver,
                           !receiverClassification.isSetReceiver,
                           !receiverClassification.isMapReceiver
                        {
                            return sema.types.make(.functionType(FunctionType(
                                params: [collectionElementType],
                                returnType: sema.types.anyType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        }
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
                        }
                        return sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
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
                        returnType: !isListReceiver && !isSequenceReceiver && !isArrayReceiver && !isMapReceiver
                            ? sema.types.nullableAnyType
                            : destinationElementType,
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
                        // The Iterable and Sequence overloads are distinguished by
                        // the lambda return type; infer that return before binding.
                        if !isSequenceReceiver,
                           isIterableReceiver,
                           !receiverClassification.isListReceiver,
                           !receiverClassification.isSetReceiver,
                           !receiverClassification.isMapReceiver
                        {
                            return sema.types.make(.functionType(FunctionType(
                                params: [sema.types.intType, collectionElementType],
                                returnType: sema.types.anyType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        }
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
                        }
                        return sema.types.make(.functionType(FunctionType(
                            params: [sema.types.intType, collectionElementType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }()
                case "associateTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: pairReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "mapKeysTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: destinationMapKeyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "mapValuesTo":
                    sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: destinationMapValueType,
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
                // Sequence and List now share top-level source-backed overload names.
                // Bind the Sequence overload explicitly to avoid selecting List.associateTo.
                if calleeStr == "associateTo", isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [
                        collectionElementType, destinationMapKeyType, destinationMapValueType
                    ]
                }
                if calleeStr == "associateTo" {
                    if bindBundledListSourceFunction(
                        typeArguments: [collectionElementType, destinationMapKeyType, destinationMapValueType, nonNullableDestinationType]
                    ) {
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                        }
                    }
                }
                if let sourceBackedSequenceAggregateTypeArguments {
                    bindBundledSequenceAggregateSource(typeArguments: sourceBackedSequenceAggregateTypeArguments)
                }
                if ["filterTo", "filterNotTo", "filterIndexedTo"].contains(calleeStr),
                   !isSequenceReceiver
                {
                    let didBindListSource = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType, nonNullableDestinationType]
                    )
                    let didBindIterableSource = !didBindListSource && isIterableReceiver
                        && bindBundledIterableSourceFunction(
                            typeArguments: [collectionElementType, nonNullableDestinationType]
                        )
                    if didBindListSource || didBindIterableSource,
                       let lambdaExpr = ast.arena.expr(args[1].expr),
                       lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }
                if ["mapTo", "mapNotNullTo", "flatMapTo", "mapIndexedTo", "mapIndexedNotNullTo", "flatMapIndexedTo"].contains(calleeStr),
                   !isSequenceReceiver,
                   !isMapReceiver
                {
                    let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                    let resultElementType: TypeID
                    if calleeStr == "mapTo" || calleeStr == "mapIndexedTo" {
                        resultElementType = rawLambdaReturnType
                    } else if calleeStr == "mapNotNullTo" || calleeStr == "mapIndexedNotNullTo" {
                        resultElementType = sema.types.makeNonNullable(rawLambdaReturnType)
                    } else if (calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo"),
                              !isSequenceReceiver,
                              isIterableReceiver,
                              !receiverClassification.isListReceiver,
                              !receiverClassification.isSetReceiver,
                              !receiverClassification.isMapReceiver
                    {
                        resultElementType = extractIterableOrSequenceElementType(
                            rawLambdaReturnType,
                            sema: sema,
                            interner: interner
                        )
                    } else {
                        resultElementType = extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                    }
                    let boundIterableDestination = (calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo")
                        && bindBundledIterableFlatMapSourceFunction(
                            collectionElementType: collectionElementType,
                            resultElementType: resultElementType,
                            returnsSequence: receiverClassifier.isSequenceLikeType(rawLambdaReturnType),
                            destinationType: nonNullableDestinationType
                        )
                    let didBindListSource: Bool
                    if boundIterableDestination {
                        didBindListSource = false
                    } else {
                        didBindListSource = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType, resultElementType, nonNullableDestinationType]
                        )
                    }
                    let didBindIterableSource: Bool
                    if !boundIterableDestination,
                       !didBindListSource,
                       !isArrayReceiver,
                       !isMapReceiver
                    {
                        didBindIterableSource = bindBundledIterableSourceFunction(
                            typeArguments: [collectionElementType, resultElementType, nonNullableDestinationType]
                        )
                    } else {
                        didBindIterableSource = false
                    }
                    if boundIterableDestination || didBindListSource || didBindIterableSource {
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                        }
                    }
                }
                if isSequenceReceiver {
                    let typeArguments: [TypeID]
                    if ["filterTo", "filterNotTo", "filterIndexedTo"].contains(calleeStr) {
                        typeArguments = [collectionElementType, nonNullableDestinationType]
                    } else {
                        let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                        let resultElementType: TypeID
                        if calleeStr == "mapTo" || calleeStr == "mapIndexedTo" {
                            resultElementType = rawLambdaReturnType
                        } else if calleeStr == "mapNotNullTo" || calleeStr == "mapIndexedNotNullTo" {
                            resultElementType = sema.types.makeNonNullable(rawLambdaReturnType)
                        } else {
                            resultElementType = extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                        }
                        typeArguments = [collectionElementType, resultElementType, nonNullableDestinationType]
                    }
                    _ = bindBundledSequenceDestinationSourceFunction(typeArguments: typeArguments)
                }
                if isMapReceiver,
                   ["mapTo", "mapNotNullTo", "mapKeysTo", "mapValuesTo"].contains(calleeStr)
                {
                    _ = bindBundledMapSourceFunction()
                }
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if calleeStr == "zip", !args.isEmpty {
                let otherType = sema.bindings.exprTypes[args[0].expr]
                    ?? driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let otherElementType: TypeID
                if let otherClassType = resolveClassType(otherType, sema: sema),
                   let firstArg = otherClassType.args.first
                {
                    otherElementType = switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    otherElementType = sema.types.anyType
                }

                let resultElementType: TypeID
                if args.count >= 2 {
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, otherElementType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    }
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultElementType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                } else if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                    resultElementType = sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.invariant(collectionElementType), .invariant(otherElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultElementType = sema.types.anyType
                }

                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: resultElementType
                    )
                } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(resultElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                if isSequenceReceiver {
                    _ = bindBundledSequenceSourceIfAvailable(resultType: resultType, otherElementType: otherElementType)
                }
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            switch calleeStr {
            case "indexOf":
                if !isIterableIndexReceiver {
                    guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                        return nil
                    }
                }
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                resultType = sema.types.intType
                if isIterableIndexReceiver {
                    _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                } else {
                    _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                }

            case "lastIndexOf":
                if isCollectionReceiver,
                   !isSequenceReceiver,
                   !receiverClassifier.isConcreteListLikeType(receiverType),
                   !isListFactoryReceiver
                {
                    guard args.count == 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.intType)
                        return sema.types.intType
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                    resultType = sema.types.intType
                    _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                } else {
                    guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                        return nil
                    }
                    guard args.count == 1 else {
                        sema.bindings.bindExprType(id, type: sema.types.intType)
                        return sema.types.intType
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                    resultType = sema.types.intType
                    _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                }

            case "contains":
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    return nil
                }
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.booleanType)
                    return sema.types.booleanType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                resultType = sema.types.booleanType
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])

            case "containsAll":
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    return nil
                }
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.booleanType)
                    return sema.types.booleanType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.anyType)
                resultType = sema.types.booleanType
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])

            case "findLast", "firstOrNull", "lastOrNull":
                if calleeStr == "lastOrNull",
                   isCollectionReceiver,
                   !isSequenceReceiver,
                   !receiverClassifier.isConcreteListLikeType(receiverType),
                   !isListFactoryReceiver
                {
                    if args.isEmpty {
                        resultType = sema.types.makeNullable(collectionElementType)
                        _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                    } else if args.count == 1 {
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType],
                            returnType: sema.types.booleanType
                        )))
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        resultType = sema.types.makeNullable(collectionElementType)
                        if bindBundledIterableSourceFunction(typeArguments: [collectionElementType]) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    } else {
                        sema.bindings.bindExprType(id, type: sema.types.makeNullable(collectionElementType))
                        return sema.types.makeNullable(collectionElementType)
                    }
                } else {
                    guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                        return nil
                    }
                    if args.isEmpty {
                        resultType = sema.types.makeNullable(collectionElementType)
                        _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                    } else if args.count == 1 {
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType],
                            returnType: sema.types.booleanType
                        )))
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        resultType = sema.types.makeNullable(collectionElementType)
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    } else {
                        sema.bindings.bindExprType(id, type: sema.types.makeNullable(collectionElementType))
                        return sema.types.makeNullable(collectionElementType)
                    }
                }

            case "map", "filter", "filterNot", "filterKeys", "filterValues", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
                 "count", "first", "last", "single", "singleOrNull", "find", "associateBy", "associateWith", "associate",
                 "mapValues", "mapKeys", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "onEach", "distinct", "withIndex", "filterNotNull", "requireNoNulls", "asSequence", "sum", "average", "reversed", "asReversed":
                // any(), none(), count(), first(), last() can be called with no args
                if args.isEmpty {
                    switch calleeStr {
                    case "any", "none": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last", "single":
                        resultType = collectionElementType
                    case "singleOrNull":
                        resultType = sema.types.makeNullable(collectionElementType)
                    case "find": resultType = sema.types.makeNullable(collectionElementType)
                    case "withIndex":
                        let indexedValueSymbol = lookupStdlibSymbol("IndexedValue", symbols: sema.symbols, interner: interner)
                        let indexedValueType: TypeID = if let indexedValueSymbol {
                            sema.types.make(.classType(ClassType(
                                classSymbol: indexedValueSymbol,
                                args: [.out(collectionElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            sema.types.anyType
                        }
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: indexedValueType
                            )
                            _ = bindBundledSequenceSourceIfAvailable(
                                resultType: resultType,
                                overrideTypeArguments: [collectionElementType]
                            )
                        } else if bindBundledIterableSourceFunction(typeArguments: [collectionElementType]),
                                  let iterableSymbol = lookupStdlibSymbol("Iterable", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: iterableSymbol,
                                args: [.out(indexedValueType)],
                                nullability: .nonNull
                            )))
                        } else if let iterableSymbol = lookupStdlibSymbol("Iterable", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: iterableSymbol,
                                args: [.out(indexedValueType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "filterNotNull", "requireNoNulls":
                        let nonNullElementType = sema.types.makeNonNullable(collectionElementType)
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: nonNullElementType
                            )
                        } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(nonNullElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "asSequence":
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                        _ = bindBundledAsSequenceSourceIfAvailable(typeArguments: [collectionElementType])
                    case "distinct":
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: collectionElementType
                            )
                        } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(collectionElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    case "sum":
                        resultType = bindBundledIterableSumSource() ?? sema.types.intType
                    case "average":
                        resultType = sema.types.doubleType
                    case "reversed", "asReversed":
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
                    case "flatten":
                        let innerElementType = extractIterableOrSequenceElementType(
                            collectionElementType,
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
                    default: resultType = sema.types.anyType
                    }
                    if ["any", "none", "first", "last", "single", "singleOrNull"].contains(calleeStr) {
                        _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                    }
                    if isMapReceiver, calleeStr == "none" {
                        // KSP-1016: bind the zero-argument Map overload to its
                        // bundled source symbol instead of the name-only fallback.
                        _ = bindBundledMapSourceFunction()
                    }
                    if calleeStr == "sum", !isSequenceReceiver, !isRangeReceiver {
                        if receiverClassifier.isConcreteListLikeType(receiverType) {
                            let bound = bindBundledListSourceFunction(
                                typeArguments: [],
                                receiverElementType: collectionElementType
                            )
                            // KSP-994 regression: `Deferred<T>.await()` can't recover `T`
                            // statically (Deferred has no class-level type parameter; see
                            // CallTypeChecker+CoroutineBuilderReturnType.swift), so a
                            // `List<Deferred<T>>` mapped through `.map { it.await() }`
                            // erases its element type to `Any` here. None of the
                            // monomorphic `sum()` overloads declare an `Any` element, so
                            // the call above never binds and would otherwise reach
                            // codegen as an unresolved `sum` callee (link failure).
                            // Fall back to the pre-migration assumption that an unknown
                            // element type is `Int`, matching historical behavior.
                            if !bound, collectionElementType == sema.types.anyType {
                                _ = bindBundledListSourceFunction(
                                    typeArguments: [],
                                    receiverElementType: sema.types.intType
                                )
                            }
                        } else {
                            _ = bindBundledIterableSumSource()
                        }
                    }
                    if calleeStr == "average", !isSequenceReceiver {
                        // KSP-965: prefer the existing List overloads, then bind
                        // the numeric Iterable overload matching the element type.
                        let didBindAverageSource = if bindBundledListSourceFunction(
                            typeArguments: [],
                            receiverElementType: collectionElementType
                        ) {
                            true
                        } else {
                            bindBundledIterableSourceFunction(
                                typeArguments: [collectionElementType],
                                receiverElementType: collectionElementType
                            )
                        }
                        if !didBindAverageSource,
                           isIterableReceiver,
                           !isArrayReceiver
                        {
                            // Iterable.average() is defined only for the six
                            // non-null numeric element types. Do not let the
                            // legacy name-based fallback accept String, nullable,
                            // or otherwise unsupported Iterable receivers.
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-0024",
                                "No viable overload found for call.",
                                range: ast.arena.exprRange(id)
                            )
                            let failedType = safeCall
                                ? sema.types.makeNullable(sema.types.errorType)
                                : sema.types.errorType
                            sema.bindings.bindExprType(id, type: failedType)
                            return failedType
                        }
                    }
                    if calleeStr == "reversed", !isSequenceReceiver {
                        _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                    }
                    if calleeStr == "asReversed", !isSequenceReceiver {
                        _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                    }
                    if calleeStr == "distinct", !isSequenceReceiver {
                        _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                    }
                    if calleeStr == "withIndex", !isSequenceReceiver {
                        _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                    }
                } else {
                    let lambdaReturnType: TypeID = switch calleeStr {
                    case "filter", "filterNot", "filterKeys", "filterValues", "any", "none", "all", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "find", "first", "last", "single", "singleOrNull": sema.types.booleanType
                    case "forEach", "onEach": sema.types.unitType
                    case "count": sema.types.booleanType
                    case "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull": sema.types.nullableAnyType
                    default: sema.types.anyType
                    }
                    let lambdaParameterTypes: [TypeID] = switch calleeStr {
                    case "flatMapIndexed":
                        [sema.types.intType, collectionElementType]
                    case "filterKeys":
                        [collectionMapTypes.key]
                    case "filterValues":
                        [collectionMapTypes.value]
                    default:
                        [collectionElementType]
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)

                    switch calleeStr {
                    case "map", "mapNotNull":
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            fnType.returnType
                        } else {
                            sema.types.anyType
                        }
                        let resultElementType = calleeStr == "mapNotNull"
                            ? sema.types.makeNonNullable(bodyType)
                            : bodyType
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: resultElementType
                            )
                        } else {
                            if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                                resultType = sema.types.make(.classType(ClassType(
                                    classSymbol: listSymbol,
                                    args: [.invariant(resultElementType)],
                                    nullability: .nonNull
                                )))
                            } else {
                                resultType = sema.types.anyType
                            }
                        }
                        let didBindListSource = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType, resultElementType]
                        )
                        let didBindIterableSource: Bool
                        if !didBindListSource,
                           !isSequenceReceiver,
                           !isArrayReceiver,
                           !isMapReceiver,
                           !(calleeStr == "map" && isSetReceiver),
                           !(calleeStr == "mapNotNull" && isSetReceiver)
                        {
                            didBindIterableSource = bindBundledIterableSourceFunction(
                                typeArguments: [collectionElementType, resultElementType]
                            )
                        } else {
                            didBindIterableSource = false
                        }
                        if didBindListSource || didBindIterableSource {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
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
                        } else if isMapReceiver {
                            // Map.filter/filterNot return Map<K, V>, not List<Map.Entry<K, V>>.
                            resultType = receiverType
                        } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(collectionElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = receiverType
                        }
                        if calleeStr == "filter",
                           bindBundledListSourceFunction(typeArguments: [collectionElementType])
                        {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    case "takeLastWhile":
                        if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(collectionElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = receiverType
                        }
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    case "takeWhile", "dropWhile", "dropLastWhile":
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
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
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
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    case "flatMap":
                        let lambdaBodyType = inferredLambdaReturnType(
                            argExpr: args[0].expr, ast: ast, sema: sema
                        )
                        let innerElementType = extractIterableOrSequenceElementType(
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
                        let boundIterableSource = bindBundledIterableFlatMapSourceFunction(
                            collectionElementType: collectionElementType,
                            resultElementType: innerElementType,
                            returnsSequence: receiverClassifier.isSequenceLikeType(lambdaBodyType)
                        )
                        if !boundIterableSource,
                           bindBundledListSourceFunction(typeArguments: [collectionElementType, innerElementType])
                        {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
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
                        let boundIterableSource = bindBundledIterableFlatMapSourceFunction(
                            collectionElementType: collectionElementType,
                            resultElementType: innerElementType,
                            returnsSequence: receiverClassifier.isSequenceLikeType(lambdaBodyType)
                        )
                        if !boundIterableSource,
                           bindBundledListSourceFunction(typeArguments: [collectionElementType, innerElementType])
                        {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    case "any", "none", "all": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last", "single": resultType = collectionElementType
                    case "singleOrNull": resultType = sema.types.makeNullable(collectionElementType)
                    case "find": resultType = sema.types.makeNullable(collectionElementType)
                    case "associateBy":
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            let keyType = inferredLambdaReturnType(
                                argExpr: args[0].expr, ast: ast, sema: sema
                            )
                            let valueType: TypeID
                            if args.count >= 2 {
                                let valueLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                                    params: [collectionElementType],
                                    returnType: sema.types.anyType
                                )))
                                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                                }
                                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: valueLambdaExpectedType)
                                valueType = inferredLambdaReturnType(
                                    argExpr: args[1].expr, ast: ast, sema: sema
                                )
                            } else {
                                valueType = collectionElementType
                            }
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(keyType), .invariant(valueType)],
                                nullability: .nonNull
                            )))
                            if isSequenceReceiver {
                                sourceBackedSequenceAggregateTypeArguments = args.count >= 2
                                    ? [collectionElementType, keyType, valueType]
                                    : [collectionElementType, keyType]
                            }
                            let associateByTypeArgs: [TypeID] = args.count >= 2
                                ? [collectionElementType, keyType, valueType]
                                : [collectionElementType, keyType]
                            if bindBundledListSourceFunction(typeArguments: associateByTypeArgs) {
                                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                                }
                                if args.count >= 2,
                                   let lambdaExpr = ast.arena.expr(args[1].expr),
                                   lambdaExpr.isLambdaOrCallableRef {
                                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                                }
                            }
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
                            if bindBundledListSourceFunction(typeArguments: [collectionElementType, valueType]) {
                                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                                }
                            }
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
                            if let (pairClass, pairSym) = resolveClassTypeSymbol(nonNullBodyType, sema: sema),
                               pairClass.args.count == 2,
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
                            if isSequenceReceiver {
                                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, keyType, valueType]
                            }
                            if bindBundledListSourceFunction(typeArguments: [collectionElementType, keyType, valueType]) {
                                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                                }
                            }
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
                        let keyType: TypeID = if let classType = resolveClassType(receiverType, sema: sema),
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
                        let valueType: TypeID = if let classType = resolveClassType(receiverType, sema: sema),
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
                    case "firstNotNullOf":
                        resultType = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            sema.types.makeNonNullable(fnType.returnType)
                        } else {
                            sema.types.anyType
                        }
                    case "firstNotNullOfOrNull":
                        if let expectedType {
                            resultType = sema.types.makeNullable(sema.types.makeNonNullable(expectedType))
                        } else if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            resultType = sema.types.makeNullable(sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType))
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            resultType = sema.types.makeNullable(sema.types.makeNonNullable(fnType.returnType))
                        } else {
                            resultType = sema.types.nullableAnyType
                        }
                    default: resultType = sema.types.anyType
                    }

                    if ["any", "none", "all", "count", "find", "first", "last", "single", "singleOrNull"].contains(calleeStr) {
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                            if args.count == 1, let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    }

                    if isMapReceiver {
                        _ = bindBundledMapSourceFunction()
                    }
                }

            case "fold":
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
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
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
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
                }

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
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }

            case "reduceRightIndexed":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
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
                resultType = collectionElementType
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }

            case "reduceRightIndexedOrNull":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
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
                resultType = sema.types.makeNullable(collectionElementType)
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }

            case "reduceRightOrNull":
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
                resultType = sema.types.makeNullable(collectionElementType)
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = collectionElementType
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }

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
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }

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
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }

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
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: initialType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(initialType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
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
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: initialType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(initialType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
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
                let isIterableRunningReduce = !isSequenceReceiver
                    && !receiverClassifier.isConcreteListLikeType(receiverType)
                let accumulatorType: TypeID = if isIterableRunningReduce,
                                                  let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
                                                      args[0].expr,
                                                      ctx: ctx,
                                                      paramCount: 2
                                                  ),
                                                  let annotated = annotations[0]
                {
                    annotated
                } else {
                    collectionElementType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [accumulatorType, collectionElementType],
                    returnType: accumulatorType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(accumulatorType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                let sourceTypeArguments = isIterableRunningReduce
                    ? [accumulatorType, collectionElementType]
                    : [collectionElementType]
                let didBindSource = isIterableRunningReduce
                    ? bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments)
                    : bindBundledListSourceFunction(typeArguments: sourceTypeArguments)
                if didBindSource {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
                let isIterableRunningReduce = !isSequenceReceiver
                    && !receiverClassifier.isConcreteListLikeType(receiverType)
                let accumulatorType: TypeID = if isIterableRunningReduce,
                                                  let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
                                                      args[0].expr,
                                                      ctx: ctx,
                                                      paramCount: 3
                                                  ),
                                                  let annotated = annotations[1]
                {
                    annotated
                } else {
                    collectionElementType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, accumulatorType, collectionElementType],
                    returnType: accumulatorType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(accumulatorType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                let sourceTypeArguments = isIterableRunningReduce
                    ? [accumulatorType, collectionElementType]
                    : [collectionElementType]
                let didBindSource = isIterableRunningReduce
                    ? bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments)
                    : bindBundledListSourceFunction(typeArguments: sourceTypeArguments)
                if didBindSource {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
                    if isSequenceReceiver {
                        sourceBackedSequenceAggregateTypeArguments = args.count >= 2
                            ? [collectionElementType, keyType, valueElementType]
                            : [collectionElementType, keyType]
                    }
                } else {
                    resultType = sema.types.anyType
                }
                let groupByTypeArgs: [TypeID] = args.count >= 2
                    ? [collectionElementType, keyType, valueElementType]
                    : [collectionElementType, keyType]
                if bindBundledListSourceFunction(typeArguments: groupByTypeArgs) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                    if args.count >= 2,
                       let lambdaExpr = ast.arena.expr(args[1].expr),
                       lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }

            case "associateByTo", "associateWithTo", "groupByTo":
                // *To(destination, keySelector/valueSelector, [valueTransform]): returns the destination map
                guard args.count == 2 || args.count == 3 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                // Infer the destination map argument first
                let destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let nonNullableDestType = sema.types.makeNonNullable(destType)
                let destKeyType: TypeID
                let destValueType: TypeID
                if let destClassType = resolveClassType(nonNullableDestType, sema: sema),
                   destClassType.args.count >= 2
                {
                    destKeyType = switch destClassType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                    destValueType = switch destClassType.args[1] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    destKeyType = sema.types.anyType
                    destValueType = sema.types.anyType
                }

                // First lambda return type: value for associateWithTo, key otherwise.
                let firstLambdaReturnType: TypeID = (calleeStr == "associateWithTo") ? destValueType : destKeyType
                let firstLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: firstLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: firstLambdaExpectedType)
                let firstLambdaReturn = inferredLambdaReturnType(
                    argExpr: args[1].expr, ast: ast, sema: sema
                )

                var valueType: TypeID = destValueType
                if args.count == 3 {
                    // Second lambda provides the transformed value.
                    // For groupByTo the destination stores MutableList<V>, so the lambda returns V.
                    let secondLambdaExpectedReturn: TypeID
                    if calleeStr == "groupByTo" {
                        secondLambdaExpectedReturn = extractListElementType(destValueType, sema: sema, interner: interner)
                    } else {
                        secondLambdaExpectedReturn = destValueType
                    }
                    let secondLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: secondLambdaExpectedReturn,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[2].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[2].expr)
                    }
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: secondLambdaExpectedType)
                    valueType = inferredLambdaReturnType(
                        argExpr: args[2].expr, ast: ast, sema: sema
                    )
                }

                // Return type is the destination map type
                resultType = destType

                // Source-backed overloads:
                //   associateByTo<T,K,M> / associateByTo<T,K,V,M> / associateWithTo<T,V,M>
                //   groupByTo<T,K,M> / groupByTo<T,K,V,M>
                let toTypeArgs: [TypeID] = args.count == 3
                    ? [collectionElementType, firstLambdaReturn, valueType, nonNullableDestType]
                    : [collectionElementType, firstLambdaReturn, nonNullableDestType]
                if bindBundledListSourceFunction(typeArguments: toTypeArgs) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                    if args.count == 3,
                       let lambdaExpr = ast.arena.expr(args[2].expr),
                       lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[2].expr)
                    }
                }

            case "sortedBy", "sortedByDescending", "sortBy", "sortByDescending":
                let isInPlaceMutation = calleeStr == "sortBy" || calleeStr == "sortByDescending"
                guard args.count == 1 else {
                    let failedType = isInPlaceMutation ? sema.types.unitType : sema.types.anyType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: calleeStr == "sortedByDescending"
                        ? sema.types.nullableAnyType
                        : sema.types.anyType
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
                if selectorType != sema.types.anyType {
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
                            args: [.invariant(selectorType)],
                            nullability: .nonNull
                        )))
                        isNominalComparable = sema.types.isSubtype(selectorType, comparableSelectorType)
                    } else {
                        isNominalComparable = false
                    }
                    if !isPrimitiveComparable, !isNominalComparable {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: ast.arena.exprRange(id)
                        )
                        let failedType = isInPlaceMutation ? sema.types.unitType : (safeCall ? sema.types.nullableAnyType : sema.types.anyType)
                        sema.bindings.bindExprType(id, type: failedType)
                        return failedType
                    }
                }
                if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isInPlaceMutation {
                    resultType = sema.types.unitType
                } else if isSequenceReceiver {
                    resultType = receiverType
                } else {
                    resultType = listResultType
                }
                if !isInPlaceMutation, isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType, selectorType]
                }

            case "sort", "sorted", "sortedDescending":
                let isInPlaceMutation = calleeStr == "sort"
                guard args.isEmpty else {
                    let failedType = isInPlaceMutation ? sema.types.unitType : sema.types.anyType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                    let comparableElementType = sema.types.make(.classType(ClassType(
                        classSymbol: comparableSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                    if !sema.types.isSubtype(collectionElementType, comparableElementType) {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: ast.arena.exprRange(id)
                        )
                        let failedType = isInPlaceMutation ? sema.types.unitType : (safeCall ? sema.types.nullableAnyType : sema.types.anyType)
                        sema.bindings.bindExprType(id, type: failedType)
                        return failedType
                    }
                }
                if !bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                }
                if isInPlaceMutation {
                    resultType = sema.types.unitType
                } else if isSequenceReceiver {
                    resultType = receiverType
                } else {
                    resultType = listResultType
                }

            case "sortedWith", "sortedArrayWith", "sortWith":
                let isInPlaceMutation = calleeStr == "sortWith"
                guard args.count == 1 else {
                    let failedType = isInPlaceMutation ? sema.types.unitType : sema.types.anyType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                let usesRuntimeFunctionPointerComparator = calleeStr == "sortedArrayWith"
                let functionExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: sema.types.intType
                )))
                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.in(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    nil
                }
                if usesRuntimeFunctionPointerComparator {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: functionExpectedType)
                    } else {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                    }
                } else if isSequenceReceiver {
                    let argExpr = ast.arena.expr(args[0].expr)
                    if argExpr?.isLambdaOrCallableRef == true {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                    } else {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                    }
                } else if (calleeStr == "sortedWith" || calleeStr == "sortWith"),
                          receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
                {
                    let argExpr = ast.arena.expr(args[0].expr)
                    if argExpr?.isLambdaOrCallableRef == true {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: functionExpectedType)
                        _ = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType],
                            matchingParameterType: functionExpectedType
                        )
                    } else if case .nameRef = argExpr {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                        let argType = sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType
                        let argKind = sema.types.kind(of: argType)
                        if case .functionType = argKind {
                            _ = bindBundledListSourceFunction(
                                typeArguments: [collectionElementType],
                                matchingParameterType: functionExpectedType
                            )
                        } else {
                            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                            _ = bindBundledListSourceFunction(
                                typeArguments: [collectionElementType],
                                matchingParameterType: comparatorExpectedType ?? sema.types.nothingType
                            )
                        }
                    } else {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                        _ = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType],
                            matchingParameterType: comparatorExpectedType ?? sema.types.nothingType
                        )
                    }
                } else {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                }
                if isInPlaceMutation {
                    resultType = sema.types.unitType
                } else if calleeStr == "sortedArrayWith" {
                    resultType = receiverType
                } else if isSequenceReceiver {
                    resultType = receiverType
                } else {
                    resultType = listResultType
                }
                if !isInPlaceMutation, isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }

            case "maxWith", "minWith", "maxWithOrNull", "minWithOrNull":
                guard args.count == 1 else {
                    let failedType = (calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull")
                        ? sema.types.makeNullable(sema.types.errorType)
                        : sema.types.errorType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.in(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    nil
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                if isMapReceiver,
                   calleeStr == "maxWith" || calleeStr == "minWith"
                       || calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull"
                {
                    _ = bindBundledMapSourceFunction()
                } else if !isSequenceReceiver, bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
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
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
                {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }
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
                if isMapReceiver,
                   calleeStr == "maxOfWith" || calleeStr == "minOfWith"
                       || calleeStr == "maxOfWithOrNull" || calleeStr == "minOfWithOrNull"
                {
                    if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorResultType) {
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                        }
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorResultType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
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
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "flatten":
                // Sequence<Iterable<T>> / List<List<T>> etc.: one-level flatten → element type T
                guard args.isEmpty else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                // If the receiver call has explicit type arguments (e.g. listOf<Int>())
                // and the explicit element type is a known non-collection, flatten() is
                // invalid — reject before the type-inference result can mask the error.
                // This handles cases where kswiftc infers List<Any> despite <Int> being
                // written explicitly (type-inference gap for empty collection literals).
                if !isSequenceReceiver,
                   let receiverExpr = ast.arena.expr(receiverID),
                   case let .call(_, receiverTypeArgs, _, _) = receiverExpr,
                   let firstTypeArgID = receiverTypeArgs.first
                {
                    let explicitElemType = driver.helpers.resolveTypeRef(firstTypeArgID, ast: ast, sema: sema, interner: interner)
                    if !receiverClassifier.isCollectionLikeType(explicitElemType) {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "Unresolved member function 'flatten'.",
                            range: range
                        )
                        sema.bindings.bindExprType(id, type: sema.types.errorType)
                        return sema.types.errorType
                    }
                }
                let extractedInner = getCollectionElementType(collectionElementType, sema: sema, interner: interner)
                // Reject when the element type is a KNOWN non-collection (e.g. Int).
                if !isSequenceReceiver && extractedInner == sema.types.anyType
                    && collectionElementType != sema.types.anyType
                    && !receiverClassifier.isCollectionLikeType(collectionElementType) {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "Unresolved member function 'flatten'.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
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
                if !isSequenceReceiver {
                    // List.flatten and Iterable.flatten share the public name,
                    // but the statically Iterable path must not fall through
                    // without a source-backed callee binding.
                    _ = bindBundledListSourceFunction(typeArguments: [flattenedElementType])
                        || bindBundledIterableSourceFunction(typeArguments: [flattenedElementType])
                }

            case "zipWithNext":
                if args.isEmpty {
                    guard explicitTypeArgs.isEmpty else {
                        sema.bindings.bindExprType(id, type: sema.types.anyType)
                        return sema.types.anyType
                    }
                    if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                        let pairType = sema.types.make(.classType(ClassType(
                            classSymbol: pairSymbol,
                            args: [.invariant(collectionElementType), .invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                        if isSequenceReceiver {
                            resultType = makeSyntheticSequenceType(
                                symbols: sema.symbols,
                                types: sema.types,
                                interner: interner,
                                elementType: pairType
                            )
                            _ = bindBundledSequenceSourceIfAvailable(
                                resultType: resultType,
                                overrideTypeArguments: [collectionElementType]
                            )
                        } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(pairType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
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
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: bodyType
                        )
                    } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
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
                let didBindSource = if isIterableIndexReceiver {
                    bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                } else {
                    bindBundledListSourceFunction(typeArguments: [collectionElementType])
                }
                if didBindSource {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "onEachIndexed":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaReturnType: TypeID = switch calleeStr {
                case "forEachIndexed", "onEachIndexed":
                    sema.types.unitType
                case "filterIndexed":
                    sema.types.booleanType
                case "mapIndexedNotNull":
                    sema.types.nullableAnyType
                default:
                    sema.types.anyType
                }
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
                    // KSP-626: bind the bundled Iterable<T>.forEachIndexed source function.
                    if bindBundledIterableSourceFunction(typeArguments: [collectionElementType]),
                       let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
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
                    if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                } else if calleeStr == "filterIndexed" {
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                    } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = receiverType
                    }
                } else if isSequenceReceiver {
                    let inferredBodyType = inferredLambdaReturnType(
                        argExpr: args[0].expr, ast: ast, sema: sema
                    )
                    let bodyType = calleeStr == "mapIndexedNotNull"
                        ? sema.types.makeNonNullable(inferredBodyType)
                        : inferredBodyType
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: bodyType
                    )
                } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                    let inferredBodyType = inferredLambdaReturnType(
                        argExpr: args[0].expr, ast: ast, sema: sema
                    )
                    let bodyType = calleeStr == "mapIndexedNotNull"
                        ? sema.types.makeNonNullable(inferredBodyType)
                        : inferredBodyType
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(bodyType)],
                        nullability: .nonNull
                    )))
                    if calleeStr == "mapIndexed" || calleeStr == "mapIndexedNotNull" {
                        let didBindListSource = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType, bodyType]
                        )
                        let didBindIterableSource: Bool
                        if !didBindListSource, !isArrayReceiver, !isMapReceiver {
                            didBindIterableSource = bindBundledIterableSourceFunction(
                                typeArguments: [collectionElementType, bodyType]
                            )
                        } else {
                            didBindIterableSource = false
                        }
                        if didBindListSource || didBindIterableSource {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    }
                } else {
                    resultType = sema.types.anyType
                }

            case "sumOf", "sumBy":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                if calleeStr == "sumOf",
                   let iterableSumOfType = bindBundledIterableSumOfSource()
                {
                    resultType = iterableSumOfType
                    break
                }
                let isListSumOf = calleeStr == "sumOf"
                    && (receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: isListSumOf ? sema.types.anyType : sema.types.intType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let selectorType = isListSumOf
                    ? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                    : sema.types.intType
                let supportedListSumOfType = selectorType == sema.types.intType
                    || selectorType == sema.types.longType
                    || selectorType == sema.types.doubleType
                resultType = isListSumOf && supportedListSumOfType
                    ? selectorType
                    : sema.types.intType
                if isListSumOf,
                   supportedListSumOfType,
                   case .lambdaLiteral = ast.arena.expr(args[0].expr)
                {
                    // The temporary Any return type above supplies the lambda's
                    // input type while its body is inferred. Restore the
                    // concrete selector type before KIR lowering so the closure
                    // ABI remains raw for primitive results such as Double.
                    sema.bindings.bindExprType(
                        args[0].expr,
                        type: sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType],
                            returnType: selectorType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    )
                }
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                } else {
                    let didBindSource = calleeStr == "sumOf"
                        ? bindBundledListSourceFunction(
                            typeArguments: [collectionElementType],
                            matchingParameterType: isListSumOf && supportedListSumOfType
                                ? sema.types.make(.functionType(FunctionType(
                                    params: [collectionElementType],
                                    returnType: selectorType
                                )))
                                : nil
                        )
                        : bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                    if didBindSource,
                       let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "intersect", "union", "subtract":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.anyType)
                if let setSymbol = lookupStdlibSymbol("Set", symbols: sema.symbols, interner: interner) {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: setSymbol,
                        args: [.out(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])

            case "sumByDouble":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.doubleType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.doubleType
                if isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                } else {
                    let didBindSource = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
                    if didBindSource,
                       let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "max", "min", "maxOrNull", "minOrNull":
                guard args.isEmpty else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                    let comparableElementType = sema.types.make(.classType(ClassType(
                        classSymbol: comparableSymbol,
                        args: [.invariant(collectionElementType)],
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
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                resultType = (calleeStr == "max" || calleeStr == "min")
                    ? collectionElementType
                    : sema.types.makeNullable(collectionElementType)

            case "maxBy", "minBy", "maxByOrNull", "minByOrNull":
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
                            args: [.invariant(selectorType)],
                            nullability: .nonNull
                        )))
                        isNominalComparable = sema.types.isSubtype(selectorType, comparableSelectorType)
                    } else {
                        isNominalComparable = false
                    }
                    if selectorType != sema.types.anyType, !isPrimitiveComparable, !isNominalComparable {
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
                resultType = (calleeStr == "maxBy" || calleeStr == "minBy")
                    ? collectionElementType
                    : sema.types.makeNullable(collectionElementType)
                if (calleeStr == "maxByOrNull" || calleeStr == "minByOrNull"), isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType, selectorType]
                }
                if isMapReceiver, calleeStr == "maxBy" || calleeStr == "minBy" {
                    if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorType),
                       let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                if isMapReceiver, calleeStr == "maxByOrNull" || calleeStr == "minByOrNull" {
                    _ = bindBundledMapSourceFunction()
                }

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
                let selectorType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
                {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }
                if isMapReceiver, calleeStr == "maxOf" || calleeStr == "minOf" {
                    if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorType),
                       let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
                resultType = selectorType

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
                                args: [.invariant(selectorType)],
                                nullability: .nonNull
                            )))
                            isNominalComparable = sema.types.isSubtype(selectorType, comparableSelectorType)
                        } else {
                            isNominalComparable = false
                        }
                        if selectorType != sema.types.anyType, !isPrimitiveComparable, !isNominalComparable {
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
                if isMapReceiver, calleeStr == "maxOfOrNull" || calleeStr == "minOfOrNull" {
                    if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorType),
                       let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

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
                let binarySearchFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    calleeName,
                ]
                func bindBinarySearchSource(parameterCount: Int, parameterMapping: [Int: Int]) {
                    guard let chosenCallee = sema.symbols.lookupAll(fqName: binarySearchFQName).first(where: { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate),
                              let signatureReceiver = signature.receiverType
                        else { return false }
                        return sema.symbols.isSourceBackedSymbol(candidate)
                            && signature.parameterTypes.count == parameterCount
                            && receiverClassifier.isConcreteListLikeType(signatureReceiver)
                    }) else {
                        return
                    }
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [collectionElementType],
                        parameterMapping: parameterMapping
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
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
                        bindBinarySearchSource(parameterCount: 3, parameterMapping: [0: 0])
                    }
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        bindBinarySearchSource(parameterCount: 1, parameterMapping: [0: 0])
                    }
                    resultType = sema.types.intType
                } else if (2 ... 4).contains(args.count) {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                    let secondIsLambda = ast.arena.expr(args[1].expr)?.isLambdaOrCallableRef == true
                    let secondType = sema.bindings.exprTypes[args[1].expr]
                        ?? driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
                    let isNaturalRange = !secondIsLambda && secondType == sema.types.intType && args.count <= 3
                    if isNaturalRange {
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                        if args.count == 3 {
                            _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                        }
                        bindBinarySearchSource(
                            parameterCount: 3,
                            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                        )
                    } else if let comparatorLambdaExpr = ast.arena.expr(args[1].expr),
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
                    if !isNaturalRange {
                        bindBinarySearchSource(
                            parameterCount: 4,
                            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                        )
                    }
                    resultType = sema.types.intType
                } else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
                _ = bindBundledListBinarySearchSource(elementType: collectionElementType)

            case "binarySearchBy":
                guard (2 ... 4).contains(args.count) else {
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
                        sema.types.makeNonNullable(keyType)
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
                _ = bindBundledListBinarySearchSource(elementType: collectionElementType)

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
                let keyType = inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                    _ = bindBundledSequenceSourceIfAvailable(
                        resultType: resultType,
                        overrideTypeArguments: [collectionElementType, keyType]
                    )
                } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = receiverType
                }
                if !isSequenceReceiver,
                   bindBundledIterableSourceFunction(typeArguments: [collectionElementType, keyType])
                {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "scanReduce":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "scanReduce() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let scanReduceLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: scanReduceLambdaType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "mapTo", "mapIndexedTo", "mapNotNullTo", "flatMapTo", "flatMapIndexedTo":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "\(calleeStr)() expects 2 arguments (destination and a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let destinationType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
                let isIndexed = calleeStr == "mapIndexedTo" || calleeStr == "flatMapIndexedTo"
                let isMapNotNullTo = calleeStr == "mapNotNullTo"
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: isIndexed ? [sema.types.intType, collectionElementType] : [collectionElementType],
                    returnType: isMapNotNullTo ? sema.types.nullableAnyType : sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let rawReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                let resultElementType: TypeID
                if calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo" {
                    resultElementType = extractListElementType(rawReturnType, sema: sema, interner: interner)
                } else if isMapNotNullTo {
                    resultElementType = sema.types.makeNonNullable(rawReturnType)
                } else {
                    resultElementType = rawReturnType
                }
                resultType = destinationType
                if bindBundledListSourceFunction(typeArguments: [collectionElementType, resultElementType, destinationType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }

            default:
                resultType = sema.types.anyType
            }

            let sourceBackedListFilterNames: Set = ["filter", "filterNot", "filterIndexed"]
            let didBindListFilterSource = sourceBackedListFilterNames.contains(calleeStr) && args.count == 1
                ? bindBundledListSourceFunction(typeArguments: [collectionElementType])
                : false
            if didBindListFilterSource {
                // The lambda argument was speculatively marked (above) as a
                // native collection HOF lambda expecting the (closureObj, it)
                // two-argument ABI. It is actually being passed to a bundled
                // Kotlin-source declaration as an ordinary boxed callable
                // value, so undo that so LambdaLowerer materializes it via
                // kk_function_create_N instead. Otherwise multi-capture
                // lambdas crash: the callee never packs captures into a
                // closure object (appendClosureArgumentsIfNeeded only runs
                // for calls with an externalLinkName), so the lambda's own
                // (closureObj, it) parameters read out-of-bounds.
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
            }

            let didBindIterableFilterSource = sourceBackedListFilterNames.contains(calleeStr)
                && args.count == 1
                && !didBindListFilterSource
                && isIterableReceiver
                && (!isSetReceiver || calleeStr == "filterIndexed")
                && bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
            if didBindIterableFilterSource,
               let lambdaExpr = ast.arena.expr(args[0].expr),
               lambdaExpr.isLambdaOrCallableRef
            {
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
            }

            if !didBindListFilterSource,
               !didBindIterableFilterSource,
               sema.bindings.callBindings[id] == nil,
               calleeStr == "filterIndexed",
               isCollectionReceiver
            {
                let knownNames = KnownCompilerNames(interner: interner)
                let memberFQName = knownNames.kotlinCollectionsListFQName + [calleeName]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count == args.count
                }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [collectionElementType],
                        parameterMapping: [0: 0]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }
            }

            if ["fold", "foldRight", "foldIndexed", "foldRightIndexed", "scan", "runningFold", "runningFoldIndexed", "scanIndexed"].contains(calleeStr), args.count == 2 {
                let initialType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
                if bindBundledListSourceFunction(typeArguments: [collectionElementType, initialType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if isSetReceiver, bindBundledSetSourceFunction() {
                    // Set has a more specific source-backed overload than
                    // Iterable; keep that receiver path ahead of the generic
                    // Iterable declaration.
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledIterableSourceFunction(typeArguments: [collectionElementType, initialType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledSequenceSourceIfAvailable(
                              resultType: resultType,
                              overrideTypeArguments: [collectionElementType, initialType],
                              allowIterableReceiver: true
                          ) {
                    // No dedicated Iterable source declaration or synthetic
                    // stub was found for this
                    // aggregate HOF (unlike reduce); fall back to the bundled
                    // Sequence<T> source body, which is plain iteration and
                    // therefore valid for any Iterable receiver.
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }
            } else if (calleeStr == "reduce" || calleeStr == "reduceOrNull" || calleeStr == "reduceIndexed" || calleeStr == "reduceIndexedOrNull"), args.count == 1 {
                // Iterable reduce-family source declarations are bound directly
                // below. Do not fall back to a Sequence declaration
                // for these names: the receiver may be a plain Set or another
                // Iterable, and the source-backed Iterable implementation is
                // the canonical dispatch target.
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledIterableSourceFunction(
                              typeArguments: [collectionElementType, collectionElementType]
                          ) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
            }
            // KSP-435: any/all/last/requireNoNulls on a nominal Collection/Iterable
            // receiver are bundled Kotlin source (Stdlib/kotlin/collections/Iterables.kt).
            // The name-keyed fast path above only computes a result type, so the call
            // would otherwise stay unresolved and lower to the bare member name.
            if sema.bindings.callBindings[id] == nil,
               !isSequenceReceiver, isCollectionReceiver,
               ["any", "all", "last", "requireNoNulls"].contains(calleeStr)
            {
                let iterableSourceTypeArguments = calleeStr == "requireNoNulls"
                    ? [sema.types.makeNonNullable(collectionElementType)]
                    : [collectionElementType]
                if bindBundledIterableSourceFunction(typeArguments: iterableSourceTypeArguments) {
                    for argument in args
                    where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                    }
                }
            }

            // Set-specific source declarations must be selected before the
            // generic Iterable overloads below. Set is also a Collection, so
            // binding Iterable.filter first would make the result depend on
            // bundled source load order.
            if isSetReceiver, sema.bindings.callBindings[id] == nil, bindBundledSetSourceFunction() {
                // The call now targets an ordinary Kotlin declaration, so its lambda
                // arguments are boxed callables rather than native (closureObj, it)
                // collection-HOF lambdas.
                for arg in args {
                    if let lambdaExpr = ast.arena.expr(arg.expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
                    }
                }
            }

            // KSP-701: these generic collection extensions are ordinary
            // bundled Kotlin declarations on Iterable<T>. Keep the explicit
            // binding here for a statically Iterable receiver (and for
            // concrete collection receivers without a more specific source
            // overload) so the call never falls through to a Sequence-shaped
            // declaration or a removed synthetic runtime bridge.
            let iterableSourceHOFNames: Set = [
                "filter",
                "partition",
                "single",
                "singleOrNull",
                "reduce",
                "reduceIndexed",
                "reduceRight",
                "reduceRightIndexed",
                "reduceRightOrNull",
                "reduceRightIndexedOrNull",
                "sumBy",
                "sumByDouble",
            ]
            if sema.bindings.callBindings[id] == nil,
               !isSequenceReceiver,
               isCollectionReceiver,
               iterableSourceHOFNames.contains(calleeStr),
               bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
            {
                for argument in args
                where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                }
            }
            if let sourceBackedSequenceAggregateTypeArguments {
                bindBundledSequenceAggregateSource(typeArguments: sourceBackedSequenceAggregateTypeArguments)
            }

            // KSP-441: Bind source-backed Sequence transform extensions (map, filter,
            // mapIndexed, etc.) once the result element type is known. Do not override
            // an already-bound CallBinding from a list/aggregate source path.
            if isSequenceReceiver, sema.bindings.callBindings[id] == nil {
                _ = bindBundledSequenceSourceIfAvailable(resultType: resultType)
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

        // KSP-499 Stage 3: a real bundled/user Kotlin declaration for this
        // exact (Flow owner, member name, arity) takes priority over the
        // hard-coded Flow intrinsic dispatch below — mirrors the declaration
        // priority rule already established for synthetic stub registration
        // (BundledDeclarationIndex / KSP-001-003). Without this, migrating a
        // Flow operator to real Kotlin source would compile but never run:
        // this special-case would keep intercepting the call by name.
        let flowOwnerFQNameForPriorityCheck: [InternedString]? = {
            guard case let .classType(classType) = sema.types.kind(of: receiverType),
                  let ownerSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            return ownerSymbol.fqName
        }()
        let hasBundledFlowDeclaration = flowOwnerFQNameForPriorityCheck.map {
            sema.bundledIndex.contains(
                ownerFQName: $0,
                name: calleeName,
                arity: args.count
            )
        } ?? false
        if isFlowReceiver,
           hasBundledFlowDeclaration,
           let bundledFlowType = tryBuiltinFlowMemberCall(
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
            // The builtin path above supplies the contextual lambda types and
            // Flow element-type tracking. Once a Flow operator has a bundled
            // Kotlin declaration, retain that source-backed symbol as the
            // call target so lowering cannot fall back to a name-only bridge.
            let flowPackageFQName = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("flow"),
                calleeName,
            ]
            if let bundledCallee = sema.symbols.lookupAll(fqName: flowPackageFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.parameterTypes.count == args.count && signature.receiverType != nil
            }),
               let signature = sema.symbols.functionSignature(for: bundledCallee)
            {
                func typeID(from argument: TypeArg) -> TypeID {
                    switch argument {
                    case let .invariant(type), let .out(type), let .in(type):
                        type
                    case .star:
                        sema.types.anyType
                    }
                }

                func inferTypeParameters(
                    declared: TypeID,
                    actual: TypeID,
                    substitutions: inout [SymbolID: TypeID]
                ) {
                    switch sema.types.kind(of: declared) {
                    case let .typeParam(typeParameter):
                        substitutions[typeParameter.symbol] = actual
                    case let .classType(declaredClass):
                        guard case let .classType(actualClass) = sema.types.kind(of: sema.types.makeNonNullable(actual)),
                              declaredClass.classSymbol == actualClass.classSymbol
                        else {
                            return
                        }
                        for (declaredArgument, actualArgument) in zip(declaredClass.args, actualClass.args) {
                            inferTypeParameters(
                                declared: typeID(from: declaredArgument),
                                actual: typeID(from: actualArgument),
                                substitutions: &substitutions
                            )
                        }
                    case let .functionType(declaredFunction):
                        guard case let .functionType(actualFunction) = sema.types.kind(of: actual) else {
                            return
                        }
                        if let declaredReceiver = declaredFunction.receiver,
                           let actualReceiver = actualFunction.receiver
                        {
                            inferTypeParameters(
                                declared: declaredReceiver,
                                actual: actualReceiver,
                                substitutions: &substitutions
                            )
                        }
                        for (declaredParameter, actualParameter) in zip(declaredFunction.params, actualFunction.params) {
                            inferTypeParameters(
                                declared: declaredParameter,
                                actual: actualParameter,
                                substitutions: &substitutions
                            )
                        }
                        inferTypeParameters(
                            declared: declaredFunction.returnType,
                            actual: actualFunction.returnType,
                            substitutions: &substitutions
                        )
                    default:
                        return
                    }
                }

                var substitutions: [SymbolID: TypeID] = [:]
                if let declaredReceiver = signature.receiverType {
                    inferTypeParameters(
                        declared: declaredReceiver,
                        actual: receiverType,
                        substitutions: &substitutions
                    )
                }
                for (index, parameterType) in signature.parameterTypes.enumerated()
                where index < args.count {
                    let actualType = sema.bindings.exprType(for: args[index].expr)
                        ?? driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals)
                    inferTypeParameters(
                        declared: parameterType,
                        actual: actualType,
                        substitutions: &substitutions
                    )
                }
                let typeArguments = signature.typeParameterSymbols.map { substitutions[$0] ?? sema.types.anyType }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: bundledCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(bundledCallee))
            }
            return bundledFlowType
        }
        if isFlowReceiver,
           !hasBundledFlowDeclaration,
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
        return nil
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
