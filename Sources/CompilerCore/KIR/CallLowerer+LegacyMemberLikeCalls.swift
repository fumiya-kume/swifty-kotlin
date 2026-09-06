// swiftlint:disable file_length

/// Legacy stdlib/member special-case lowering path.
///
/// This remains deliberately isolated while narrower families continue to move out.
extension CallLowerer {
    /// Whether Sema bound the call to a bundled Kotlin-source declaration that
    /// is lowered as an ordinary source call (no `kk_*` external link name).
    func isResolvedSourceBackedCallee(_ exprID: ExprID, sema: SemaModule) -> Bool {
        guard let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
              chosenCallee != .invalid,
              let symbol = sema.symbols.symbol(chosenCallee),
              symbol.kind == .function,
              sema.symbols.isSourceBackedSymbol(chosenCallee)
        else {
            return false
        }
        return Self.isSourceBackedLinkName(sema.symbols.externalLinkName(for: chosenCallee))
    }

    /// A declaration compiled from Kotlin source either carries no external link
    /// name (bundled source in this compilation) or the compiler's own `kk_fn_*`
    /// mangling (the same declaration imported from a stdlib library artifact).
    /// Any other `kk_*` link name is a runtime-bridge ABI stub.
    static func isSourceBackedLinkName(_ linkName: String?) -> Bool {
        guard let linkName, !linkName.isEmpty else { return true }
        return linkName.hasPrefix("kk_fn_")
    }

    /// Member names whose generic Iterable/Collection implementations moved to
    /// bundled Kotlin source in KSP-435, KSP-632, and KSP-983. A call bound to one of those
    /// source declarations bypasses this file's runtime-bridge special cases.
    static let sourceBackedIterableCollectionMemberNames: Set<String> = [
        "all", "any", "firstNotNullOf", "firstNotNullOfOrNull", "joinTo", "joinToString",
        "containsAll", "count", "isNotEmpty", "intersect", "last", "lastIndexOf", "lastOrNull",
        "minus", "minusElement", "plus", "plusElement", "random", "randomOrNull",
        "requireNoNulls", "reduceRight", "reduceRightIndexed", "reduceRightIndexedOrNull",
        "reduceRightOrNull", "sumBy", "sumByDouble", "subtract", "toCollection", "toHashSet",
        "toBooleanArray", "toByteArray", "toCharArray", "toDoubleArray", "toFloatArray", "toIntArray",
        "toList", "toLongArray", "toMap", "toMutableList", "toMutableSet", "toSet", "toShortArray",
        "toTypedArray", "toUByteArray", "toUIntArray", "toULongArray", "toUShortArray", "union",
        "filter", "filterIndexed", "filterIndexedTo", "filterIsInstance",
        "filterIsInstanceTo", "filterNot", "filterNotNull", "filterNotNullTo", "filterNotTo", "filterTo",
        "indexOf", "indexOfFirst", "indexOfLast",
        "shuffled",
        "distinct", "distinctBy", "flatten",
        "max", "maxBy", "maxByOrNull", "maxOf", "maxOfOrNull", "maxOfWith",
        "maxOfWithOrNull", "maxOrNull", "maxWith", "maxWithOrNull",
    ]

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// This shared lowering path still centralizes legacy stdlib/member special cases.
    func lowerMemberLikeCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        requireNonNullableReceiverForConstFold: Bool,
        prependReceiverForUnresolvedCollectionCall: Bool,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // swiftlint:enable cyclomatic_complexity function_body_length
        if let foldedConst = tryFoldConstMemberProperty(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            requireNonNullableReceiver: requireNonNullableReceiverForConstFold,
            sema: sema,
            arena: arena,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        ) {
            return foldedConst
        }
        if let constValue = sema.bindings.constExprValue(for: exprID) {
            let constResult = arena.appendExpr(
                constValue,
                type: sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            )
            instructions.append(.constValue(result: constResult, value: constValue))
            return constResult
        }
        if let staticMemberValue = tryLowerClassNameMemberValueExpr(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            instructions: &instructions
        ) {
            return staticMemberValue
        }

        let boundType = sema.bindings.exprTypes[exprID]
        let loweredReceiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let chosenCalleeForArgumentAdaptation = sema.bindings.callBindings[exprID]?.chosenCallee
        let isSourceBackedMemberCall: Bool = {
            guard let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            guard sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) else {
                return false
            }
            let sourceBackedStringMemberNames: Set<String> = ["split", "replace", "replaceFirst"]
            return sourceBackedStringMemberNames.contains(interner.resolve(calleeName))
        }()
        // KSP-435: the generic Iterable/Collection surface is bundled Kotlin source
        // (Stdlib/kotlin/collections/Iterables.kt, Collections.kt). When Sema binds a
        // call to one of those declarations, the legacy `kk_iterable_*`/`kk_collection_*`
        // interceptions below must not hijack it.
        let isSourceBackedIterableCollectionCall: Bool = {
            guard let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let memberName = interner.resolve(calleeName)
            if memberName == "plus" {
                // `plus` is shared by collections, sequences, maps, and other
                // receivers. Only the source declaration whose extension
                // receiver is Iterable belongs to this source-backed path.
                guard let signature = sema.symbols.functionSignature(for: chosenCallee),
                      let declaredReceiver = signature.receiverType,
                      let (_, declaredReceiverSymbol) = resolveClassTypeSymbol(
                          sema.types.makeNonNullable(declaredReceiver),
                          sema: sema
                      )
                else {
                    return false
                }
                return declaredReceiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Iterable"),
                ]
            }
            if Self.sourceBackedIterableCollectionMemberNames.contains(memberName) {
                return true
            }
            if interner.resolve(calleeName) == "zip" {
                guard let firstArgument = args.first,
                      let firstArgumentType = sema.bindings.exprTypes[firstArgument.expr]
                else {
                    return false
                }
                // KSP-999: only the Array overload is fully source-backed. The
                // existing Iterable overload intentionally keeps its shared runtime
                // bridge for now. Inspect the bound argument rather than the
                // generic declaration signature so Array<out R> remains visible
                // after overload substitution.
                return isGenericKotlinArrayType(
                    sema.types.makeNonNullable(firstArgumentType),
                    sema: sema,
                    interner: interner
                )
            }
            let sourceBackedListSearchNames: Set<String> = [
                "find", "findLast", "indexOf", "indexOfFirst", "indexOfLast",
                "lastIndexOf", "contains", "containsAll", "any", "all", "none",
                "count", "binarySearch", "binarySearchBy",
            ]
            guard sourceBackedListSearchNames.contains(interner.resolve(calleeName)) else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            return isConcreteListLikeType(
                sema.types.makeNonNullable(receiverType),
                sema: sema,
                interner: interner
            )
        }()
        // KSP-1515: Array copy APIs now have bundled Kotlin source implementations
        // (Stdlib/kotlin/collections/ArrayContentAndCopy.kt). When Sema resolves
        // the call to one of those declarations, skip the legacy copy interception
        // below so the resolved source symbol is emitted.
        let isSourceBackedArrayCopyCall: Bool = {
            guard let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let sourceBackedArrayCopyFQNames: Set<[InternedString]> = [
                [interner.intern("kotlin"), interner.intern("collections"), interner.intern("copyOf")],
                [interner.intern("kotlin"), interner.intern("collections"), interner.intern("copyOfRange")],
            ]
            return sourceBackedArrayCopyFQNames.contains(symbol.fqName)
        }()
        // KSP-1513: array `toList` is a bundled Kotlin extension. Keep its
        // selected source declaration so its typed private `__kk_*` bridge is
        // emitted instead of the generic array shortcut.
        let isSourceBackedArrayToListCall: Bool = {
            guard interner.resolve(calleeName) == "toList",
                  let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            guard let (_, receiverSymbol) = resolveClassTypeSymbol(
                sema.types.makeNonNullable(receiverType), sema: sema
            ) else {
                return false
            }
            let sourceBackedArrayNames: Set<String> = [
                "IntArray", "LongArray", "ShortArray", "ByteArray",
                "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
                "UByteArray", "UShortArray", "UIntArray", "ULongArray", "Array",
            ]
            return sourceBackedArrayNames.contains(interner.resolve(receiverSymbol.name))
        }()
        // KSP-1516: selected Array/primitive-array conversion declarations are
        // ordinary bundled Kotlin calls, not legacy runtime shortcuts.
        let isSourceBackedArrayConversionCall: Bool = {
            let memberName = interner.resolve(calleeName)
            guard ["sliceArray", "reversedArray", "asList", "toTypedArray"].contains(memberName),
                  let chosenCallee = chosenCalleeForArgumentAdaptation,
                  chosenCallee != .invalid,
                  let symbol = sema.symbols.symbol(chosenCallee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenCallee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            return isConcreteArrayLikeType(
                sema.types.makeNonNullable(receiverType),
                sema: sema,
                interner: interner
            )
        }()
        let shouldAdaptCollectionHOFArguments: Bool = {
            guard isCollectionHOFCallee(calleeName, interner: interner) else {
                return false
            }
            guard let chosenCallee = chosenCalleeForArgumentAdaptation, chosenCallee != .invalid else {
                return true
            }
            // `Result.fold(onSuccess, onFailure)` takes two callbacks, but the
            // (fnPtr, closureRaw) pairs produced here are still subject to
            // parameter-mapping normalization, which keeps one argument per
            // declared parameter and therefore drops the onFailure pair.
            // emitMemberCallInstruction expands both callbacks after
            // normalization, so leave the lambdas untouched here.
            if sema.symbols.externalLinkName(for: chosenCallee) == "kk_runtime_result_fold" {
                return false
            }
            if !Self.isSourceBackedLinkName(sema.symbols.externalLinkName(for: chosenCallee)) {
                return true
            }
            if resultRuntimeHOFMemberCalleeName(
                memberName: interner.resolve(calleeName),
                receiverType: sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType,
                sema: sema,
                interner: interner
            ) != nil {
                return true
            }
            return !sema.symbols.isSourceBackedSymbol(chosenCallee)
        }()
        let normalizedArgIDs: [KIRExprID] = {
            guard shouldAdaptCollectionHOFArguments else {
                return loweredArgIDs
            }
            let closureAdapted = addCollectionHOFClosureArguments(
                loweredArgIDs: loweredArgIDs,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return adaptComparatorFactoryArgumentsForCollectionHOF(
                calleeName: calleeName,
                loweredArgIDs: closureAdapted,
                argExprIDs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }()
        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        let chosenBase64Callee: SymbolID? = {
            guard let selected = sema.bindings.callBindings[exprID]?.chosenCallee, selected != .invalid else {
                return nil
            }
            return selected
        }()

        let isSourceBackedSequenceCall: Bool = {
            guard let chosenBase64Callee,
                  let symbol = sema.symbols.symbol(chosenBase64Callee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenBase64Callee)
            else {
                return false
            }
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            return isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
        }()
        let isSourceBackedTerminalCall: Bool = {
            guard let chosenBase64Callee,
                  let symbol = sema.symbols.symbol(chosenBase64Callee),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosenBase64Callee)
            else {
                return false
            }
            return true
        }()

        // KSP-426: List.sortedWith is source-backed and accepts Comparator<T>.

        // BUG-167: reduceRightOrNull's bundled Kotlin-source declaration
        // (ListAggregateHOF.kt) is scoped to `List<T>` specifically (its body
        // needs indexed access), so bindBundledListSourceFunction
        // (CallTypeChecker+MemberCallInferenceCollectionFlow.swift) only binds
        // a chosenCallee for genuine List receivers there — a concrete Set
        // receiver reaches KIR with chosenBase64Callee == nil, and (unlike an
        // Iterable-typed variable, which the useIterableRuntimeForCollectionFallback
        // branch below already covers) had no other fallback here, so it fell
        // all the way through to a bare-Kotlin-name "give up" call and
        // produced an unresolved `_reduceRightOrNull` link error.
        // kk_sequence_reduceRightOrNull already reads its receiver through
        // runtimeCollectionElements (List- and Set-compatible), so any
        // concrete collection Sema didn't already bind can use it directly.
        if args.count == 1,
           chosenBase64Callee == nil,
           interner.resolve(calleeName) == "reduceRightOrNull"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            // isConcreteCollectionLikeType (via isCollectionLikeSymbol) also
            // matches Sequence receivers -- Sequence must be excluded here so
            // it keeps going through the dedicated
            // useSequenceRuntimeForCollectionFallback dispatch below (which
            // correctly picks kk_sequence_reduceRightOrNull), rather than
            // being misrouted to kk_sequence_reduceRightOrNull and panicking on
            // an "invalid list handle" (a Sequence handle is not a List
            // handle).
            if isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner),
               !isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_sequence_reduceRightOrNull"),
                    arguments: [loweredReceiverID] + normalizedArgIDs,
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isRangeLikeReceiver = sema.bindings.isRangeExpr(receiverExpr) || {
                guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
                    return false
                }
                let name = interner.resolve(symbol.name)
                return name == "IntProgression"
                    || name == "LongProgression"
                    || name == "LongRange"
                    || name == "CharProgression"
                    || name == "UIntRange"
                    || name == "UIntProgression"
                    || name == "ULongProgression"
            }()
            let isExplicitCharProgressionSourceCall = ast.arena.isExplicitCall(exprID)
                && ["first", "firstOrNull", "last", "lastOrNull"].contains(interner.resolve(calleeName))
                && {
                    guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
                        return false
                    }
                    return interner.resolve(symbol.name) == "CharProgression"
                }()
            let isLongRange = nonNullReceiverType == sema.types.longType
            if isRangeLikeReceiver && !isExplicitCharProgressionSourceCall {
                let runtimeGetter: InternedString? = switch interner.resolve(calleeName) {
                case "start":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : "__kk_range_first"))
                // `endInclusive` is the `ClosedRange` property name; `end` is the legacy alias.
                case "end", "endInclusive":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : "__kk_range_last"))
                case "endExclusive":
                    interner.intern("__kk_range_endExclusive")
                case "first":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_first"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_first"
                            : "__kk_range_first"))
                case "last":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_last"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_last"
                            : "__kk_range_last"))
                case "step":
                    interner.intern(sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType
                        ? "kk_ulong_range_step"
                        : (sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType
                            ? "kk_uint_range_step"
                            : (isLongRange ? "kk_long_range_step" : "kk_range_step")))
                default:
                    nil
                }
                if let runtimeGetter {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeGetter,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        if let storedObjectProperty = tryLowerObjectLiteralStoredPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedObjectProperty
        }

        if let enumEntryProperty = tryLowerEnumEntryPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return enumEntryProperty
        }

        if let externalMemberProperty = tryLowerExternalMemberPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return externalMemberProperty
        }

        if let storedMemberProperty = tryLowerStoredMemberPropertyRead(
            exprID,
            loweredReceiverID: loweredReceiverID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return storedMemberProperty
        }

        if args.isEmpty,
           calleeName == interner.intern("step")
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let runtimeCallee: InternedString = if sema.bindings.isULongRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.ulongType
            {
                interner.intern("kk_ulong_range_step")
            } else if sema.bindings.isUIntRangeExpr(receiverExpr)
                || nonNullReceiverType == sema.types.uintType
            {
                interner.intern("kk_uint_range_step")
            } else {
                interner.intern("kk_range_step")
            }
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Primitive member function: Int/Long.inv() → kk_op_inv (P5-103)
        if calleeName == interner.intern("inv"),
           args.isEmpty,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_inv"),
                arguments: [loweredReceiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // KSP-642: Int/Long rotateLeft / rotateRight are lowered as ordinary calls to
        // the bundled Kotlin declarations in `Stdlib/kotlin/Numbers.kt`.

        // Boolean.not() → kk_op_not (STDLIB-308)
        if calleeName == interner.intern("not"),
           args.isEmpty
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_not"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.booleanType) {
                let boolCallee: InternedString? = switch interner.resolve(calleeName) {
                case "and":
                    interner.intern("kk_bitwise_and")
                case "or":
                    interner.intern("kk_bitwise_or")
                case "xor":
                    interner.intern("kk_bitwise_xor")
                default:
                    nil
                }
                if let boolCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: boolCallee,
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // Float.mod(other) / Double.mod(other): Kotlin mod uses floor-style
        // modulo, while rem/% use truncating remainder.
        if args.count == 1,
           interner.resolve(calleeName) == "mod"
        {
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rhsType)
            let isFloatingReceiver = nonNullReceiverType == floatType || nonNullReceiverType == doubleType
            let isFloatingRhs = nonNullRhsType == floatType || nonNullRhsType == doubleType
            if isFloatingReceiver, isFloatingRhs {
                let resultType = nonNullReceiverType == doubleType || nonNullRhsType == doubleType ? doubleType : floatType
                var lhs = loweredReceiverID
                var rhs = loweredArgIDs[0]
                if resultType == doubleType {
                    if nonNullReceiverType == floatType {
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_float_to_double_bits"),
                            arg: lhs,
                            result: converted,
                            into: &instructions
                        )
                        lhs = converted
                    }
                    if nonNullRhsType == floatType {
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: doubleType)
                        emitNonThrowingCall(
                            callee: interner.intern("__kk_float_to_double_bits"),
                            arg: rhs,
                            result: converted,
                            into: &instructions
                        )
                        rhs = converted
                    }
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(resultType == doubleType ? "kk_op_dfloor_mod" : "kk_op_ffloor_mod"),
                    arguments: [lhs, rhs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Primitive arithmetic/infix member functions on numeric receivers.
        if args.count == 1,
           shouldLowerPrimitiveInv(receiverExpr: receiverExpr, sema: sema, nullableReceiverAllowed: requireNonNullableReceiverForConstFold)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let rawRhsType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let nonNullRhsType = sema.types.makeNonNullable(rawRhsType)
            let isShiftReceiver = nonNullReceiverType == intType || nonNullReceiverType == longType || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
            let isUnsignedReceiver = nonNullReceiverType == uintType || nonNullReceiverType == ulongType || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
            let primitiveCallee: InternedString? = switch interner.resolve(calleeName) {
            case "plus":
                interner.intern("kk_op_add")
            case "minus":
                interner.intern("kk_op_sub")
            case "times":
                interner.intern("kk_op_mul")
            case "div":
                // swiftlint:disable:next void_function_in_ternary
                isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_div")
            case "floorDiv":
                // swiftlint:disable:next void_function_in_ternary
                isUnsignedReceiver ? interner.intern("kk_op_udiv") : interner.intern("kk_op_floor_div")
            case "rem":
                // swiftlint:disable:next void_function_in_ternary
                isUnsignedReceiver ? interner.intern("kk_op_urem") : interner.intern("kk_op_mod")
            case "mod":
                isUnsignedReceiver
                    // swiftlint:disable:next void_function_in_ternary
                    ? interner.intern("kk_op_urem")
                    : interner.intern(nonNullReceiverType == longType || nonNullRhsType == longType ? "kk_op_lfloor_mod" : "kk_op_floor_mod")
            case "and":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_and") : nil
            case "or":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_or") : nil
            case "xor":
                rawRhsType == nonNullReceiverType ? interner.intern("kk_bitwise_xor") : nil
            case "shl":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shl") : nil
            case "shr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_shr") : nil
            case "ushr":
                isShiftReceiver && rawRhsType == intType ? interner.intern("kk_op_ushr") : nil
            default:
                nil
            }
            if let primitiveCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: primitiveCallee,
                    arguments: [loweredReceiverID, loweredArgIDs[0]],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        // Primitive member function: Int/Long.toString() → kk_any_to_string
        // and Int/Long.toString(radix: Int) → kk_int_toString_radix (EXPR-003)
        if calleeName == interner.intern("toString"),
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if nonNullReceiverType == intType || nonNullReceiverType == longType {
                if args.isEmpty {
                    let stringReceiverID: KIRExprID
                    if nonNullReceiverType == longType {
                        // kk_any_to_string treats the raw null sentinel as null.
                        // Long.MIN_VALUE has the same representation, so box a
                        // Long receiver before generic stringification; the
                        // non-null variant preserves the value at that boundary.
                        stringReceiverID = boxValueForAnySlot(
                            loweredReceiverID,
                            sourceType: receiverType,
                            types: sema.types,
                            symbols: sema.symbols,
                            interner: interner,
                            arena: arena,
                            resultType: sema.types.anyType,
                            requireNonNull: sema.types.nullability(of: receiverType) == .nonNull,
                            into: &instructions
                        )
                    } else {
                        stringReceiverID = loweredReceiverID
                    }
                    let tagID = arena.appendExpr(.intLiteral(1), type: intType)
                    instructions.append(.constValue(result: tagID, value: .intLiteral(1)))
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_any_to_string"),
                        arguments: [stringReceiverID, tagID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_int_toString_radix"),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
        }

        let anyFallbackReceiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullAnyFallbackReceiverType = sema.types.makeNonNullable(anyFallbackReceiverType)
        let allowsAnyFallback: Bool = switch sema.types.kind(of: nonNullAnyFallbackReceiverType) {
        case .stringStruct:
            false
        case .primitive:
            true
        case .typeParam:
            // All type parameters have an implicit upper bound of Any? in Kotlin,
            // so Any methods (toString, hashCode, equals) are always available on
            // type parameter receivers (STDLIB-GEN-055).
            true
        default:
            nonNullAnyFallbackReceiverType == sema.types.anyType
        }
        // Any.toString(): String — use the member-dispatch bridge so a
        // Throwable override remains visible after erasure to Any. Keep the
        // tagged helper for primitive and type-parameter fallback values.
        if args.isEmpty, interner.resolve(calleeName) == "toString", allowsAnyFallback {
            if nonNullAnyFallbackReceiverType == sema.types.anyType {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_any_member_to_string"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let tag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
            instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [loweredReceiverID, tagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Any.hashCode(): Int — via kk_any_hashCode (STDLIB-306)
        if args.isEmpty, interner.resolve(calleeName) == "hashCode", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_hashCode"),
                arguments: [loweredReceiverID, receiverTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Any.equals(other: Any?): Boolean — via kk_any_equals (STDLIB-306)
        if args.count == 1, interner.resolve(calleeName) == "equals", allowsAnyFallback {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let receiverTag = anyFallbackTag(for: anyFallbackReceiverType, sema: sema)
            let argType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let argTag = anyFallbackTag(for: argType, sema: sema)
            let receiverTagID = arena.appendExpr(.intLiteral(receiverTag), type: intType)
            instructions.append(.constValue(result: receiverTagID, value: .intLiteral(receiverTag)))
            let argTagID = arena.appendExpr(.intLiteral(argTag), type: intType)
            instructions.append(.constValue(result: argTagID, value: .intLiteral(argTag)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_equals"),
                arguments: [loweredReceiverID, receiverTagID, loweredArgIDs[0], argTagID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toByte(), toShort() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let ubyteType = sema.types.make(.primitive(.ubyte, .nonNull))
            let ushortType = sema.types.make(.primitive(.ushort, .nonNull))
            let byteType = sema.types.byteType
            let shortType = sema.types.shortType
            let charType = sema.types.charType
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let nonNullResultType = sema.types.makeNonNullable(resultType)
            let calleeStr = interner.resolve(calleeName)
            let conversionCallee: InternedString? = switch (calleeStr, nonNullReceiverType, nonNullResultType) {
            case ("toInt", uintType, intType): interner.intern("kk_uint_to_int")
            case ("toInt", ulongType, intType): interner.intern("kk_ulong_to_int")
            case ("toInt", ubyteType, intType): interner.intern("kk_ubyte_to_int")
            case ("toInt", ushortType, intType): interner.intern("kk_ushort_to_int")
            case ("toInt", doubleType, intType): interner.intern("__kk_double_to_int")
            case ("toInt", floatType, intType): interner.intern("__kk_float_to_int")
            case ("toInt", longType, intType): interner.intern("kk_long_to_int")
            case ("toInt", charType, intType): nil // identity (Char is stored as Int)
            case ("toInt", byteType, intType): nil // identity
            case ("toInt", shortType, intType): nil // identity
            case ("toInt", intType, intType): nil // identity
            case ("toUInt", intType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", longType, uintType): interner.intern("kk_long_to_uint")
            case ("toUInt", ubyteType, uintType): interner.intern("kk_ubyte_to_uint")
            case ("toUInt", ushortType, uintType): interner.intern("kk_ushort_to_uint")
            case ("toUInt", byteType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", shortType, uintType): interner.intern("kk_int_to_uint")
            case ("toUInt", uintType, uintType), ("toUInt", ulongType, uintType): nil // identity
            case ("toLong", intType, longType): interner.intern("kk_int_to_long")
            case ("toLong", uintType, longType): interner.intern("kk_uint_to_long")
            case ("toLong", ubyteType, longType): interner.intern("kk_ubyte_to_long")
            case ("toLong", ushortType, longType): interner.intern("kk_ushort_to_long")
            case ("toLong", doubleType, longType): interner.intern("__kk_double_to_long")
            case ("toLong", floatType, longType): interner.intern("__kk_float_to_long")
            case ("toLong", byteType, longType): nil // identity
            case ("toLong", shortType, longType): nil // identity
            case ("toLong", longType, longType), ("toLong", ulongType, longType): nil // identity
            case ("toULong", intType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", longType, ulongType): interner.intern("kk_long_to_ulong")
            case ("toULong", uintType, ulongType): interner.intern("kk_uint_to_ulong")
            case ("toULong", ubyteType, ulongType): interner.intern("kk_ubyte_to_ulong")
            case ("toULong", ushortType, ulongType): interner.intern("kk_ushort_to_ulong")
            case ("toULong", byteType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", shortType, ulongType): interner.intern("kk_int_to_ulong")
            case ("toULong", ulongType, ulongType): nil // identity
            case ("toFloat", intType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", longType, floatType): interner.intern("kk_long_to_float")
            case ("toFloat", byteType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", shortType, floatType): interner.intern("kk_int_to_float")
            case ("toFloat", doubleType, floatType): interner.intern("kk_double_to_float")
            case ("toFloat", floatType, floatType): nil // identity
            case ("toDouble", byteType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", shortType, doubleType): interner.intern("kk_int_to_double_bits")
            case ("toDouble", longType, doubleType): interner.intern("kk_long_to_double")
            case ("toDouble", floatType, doubleType): interner.intern("__kk_float_to_double_bits")
            case ("toDouble", doubleType, doubleType): nil // identity
            case ("toByte", intType, byteType): interner.intern("kk_int_to_byte")
            case ("toByte", longType, byteType): interner.intern("kk_long_to_byte")
            case ("toByte", uintType, byteType): interner.intern("kk_uint_to_byte")
            case ("toByte", ulongType, byteType): interner.intern("kk_ulong_to_byte")
            case ("toByte", ubyteType, byteType): interner.intern("kk_ubyte_to_byte")
            case ("toByte", ushortType, byteType): interner.intern("kk_ushort_to_byte")
            case ("toByte", byteType, byteType): nil // identity
            case ("toByte", shortType, byteType): interner.intern("kk_int_to_byte")
            case ("toShort", intType, shortType): interner.intern("kk_int_to_short")
            case ("toShort", longType, shortType): interner.intern("kk_long_to_short")
            case ("toShort", uintType, shortType): interner.intern("kk_uint_to_short")
            case ("toShort", ulongType, shortType): interner.intern("kk_ulong_to_short")
            case ("toShort", ubyteType, shortType): interner.intern("kk_ubyte_to_short")
            case ("toShort", ushortType, shortType): interner.intern("kk_ushort_to_short")
            case ("toShort", byteType, shortType): nil // identity
            case ("toShort", shortType, shortType): nil // identity
            case ("toUByte", intType, ubyteType): interner.intern("kk_int_to_ubyte")
            case ("toUByte", longType, ubyteType): interner.intern("kk_long_to_ubyte")
            case ("toUByte", uintType, ubyteType): interner.intern("kk_uint_to_ubyte")
            case ("toUByte", ulongType, ubyteType): interner.intern("kk_ulong_to_ubyte")
            case ("toUShort", intType, ushortType): interner.intern("kk_int_to_ushort")
            case ("toUShort", longType, ushortType): interner.intern("kk_long_to_ushort")
            case ("toUShort", uintType, ushortType): interner.intern("kk_uint_to_ushort")
            case ("toUShort", ulongType, ushortType): interner.intern("kk_ulong_to_ushort")
            case ("toChar", uintType, charType): interner.intern("kk_uint_to_char")
            case ("toChar", ulongType, charType): interner.intern("kk_ulong_to_char")
            case ("toChar", ubyteType, charType): interner.intern("kk_ubyte_to_char")
            case ("toChar", ushortType, charType): interner.intern("kk_ushort_to_char")
            case ("toChar", charType, charType): nil // identity
            default: nil
            }
            if let callee = conversionCallee {
                instructions.append(.call(
                    symbol: nil,
                    callee: callee,
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            let isRepresentationPreservingConversion =
                (calleeStr == "toLong" && nonNullReceiverType == ulongType && nonNullResultType == longType)
                    || (calleeStr == "toUInt" && nonNullReceiverType == ulongType && nonNullResultType == uintType)
                    || (calleeStr == "toULong" && nonNullReceiverType == longType && nonNullResultType == ulongType)
                    || (calleeStr == "toInt" && nonNullReceiverType == charType && nonNullResultType == intType)
                    || (calleeStr == "toInt" && (nonNullReceiverType == byteType || nonNullReceiverType == shortType) && nonNullResultType == intType)
                    || (calleeStr == "toLong" && (nonNullReceiverType == byteType || nonNullReceiverType == shortType) && nonNullResultType == longType)
                    || (calleeStr == "toShort" && nonNullReceiverType == byteType && nonNullResultType == shortType)
            // Representation-preserving primitive conversions have no runtime callee;
            // keep them from falling through to generic member emission as raw symbols.
            if ["toInt", "toUInt", "toLong", "toULong", "toFloat", "toDouble", "toShort", "toUByte", "toUShort", "toChar"].contains(calleeStr),
               nonNullReceiverType == nonNullResultType || isRepresentationPreservingConversion,
               nonNullReceiverType == intType || nonNullReceiverType == longType
               || nonNullReceiverType == uintType || nonNullReceiverType == ulongType
               || nonNullReceiverType == ubyteType || nonNullReceiverType == ushortType
               || nonNullReceiverType == byteType || nonNullReceiverType == shortType
               || nonNullReceiverType == floatType || nonNullReceiverType == doubleType
               || nonNullReceiverType == charType
            {
                instructions.append(.copy(from: loweredReceiverID, to: result))
                return result
            }
        }

        if args.isEmpty, interner.resolve(calleeName) == "length" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_string_struct_get_length"),
                    arguments: [loweredReceiverID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            // KSP-724: `CharSequence.length` is resolved through the bundled
            // `kotlin.CharSequence` interface property, so the `kk_char_sequence_length`
            // name-string fallback is no longer needed here.
        }

        // Char.code → identity (Char is stored as its Int code point) (STDLIB-305)
        // KSP-662: bundled Kotlin (kotlin.text.CharConversions) resolves
        // digitToInt / digitToIntOrNull, so no lowering special case is needed.
        if args.isEmpty, interner.resolve(calleeName) == "code" {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            if sema.types.makeNonNullable(receiverType) == sema.types.charType {
                instructions.append(.copy(from: loweredReceiverID, to: result))
                return result
            }
        }

        if let tableDrivenStringMember = tryLowerTableDrivenStringMemberCall(
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            sema: sema,
            arena: arena,
            interner: interner,
            loweredReceiverID: loweredReceiverID,
            loweredArgIDs: loweredArgIDs,
            normalizedArgIDs: normalizedArgIDs,
            result: result,
            instructions: &instructions
        ) {
            return tableDrivenStringMember
        }

        // Migrated source-backed members must lower through their Kotlin body;
        // flat ABI exceptions are excluded by isSourceBackedMemberCall above.
        if !isSourceBackedMemberCall, !isSourceBackedIterableCollectionCall {
        // Collection nullable-receiver isNullOrEmpty fallback.
        // String.isNullOrEmpty/isNullOrBlank are bundled Kotlin source (KSP-401).
        if args.isEmpty {
            let calleeStr = interner.resolve(calleeName)
            // A source-backed Collection<T>?.isNullOrEmpty() declaration may
            // be selected once the Collection surface is bundled from Kotlin
            // source, but concrete collection receivers still need their
            // type-specific non-throwing isEmpty bridge here.
            let isSourceBackedCollectionIsNullOrEmpty: Bool = {
                guard calleeStr == "isNullOrEmpty",
                      let chosenCallee = chosenCalleeForArgumentAdaptation,
                      let symbol = sema.symbols.symbol(chosenCallee),
                      sema.symbols.isSourceBackedSymbol(chosenCallee),
                      symbol.fqName == [
                          interner.intern("kotlin"),
                          interner.intern("collections"),
                          calleeName,
                      ]
                else {
                    return false
                }
                // `kotlin.collections.isNullOrEmpty` is overloaded per receiver
                // (Collection, Map, ...); the bare package+name FQN above can't
                // tell those apart since extension receivers aren't part of it.
                // Map's own isNullOrEmpty is also source-backed and must keep
                // calling through its Kotlin declaration (which owns the
                // private kk_map_is_empty helper), so only take the
                // runtime-bridge fast path when the chosen overload's own
                // receiver is actually Collection<T>.
                guard let signatureReceiverType = sema.symbols.functionSignature(for: chosenCallee)?.receiverType,
                      let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiverType, sema: sema)
                else {
                    return false
                }
                return receiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Collection"),
                ]
            }()
            if calleeStr == "isNullOrEmpty",
               (sema.bindings.callBindings[exprID] == nil || isSourceBackedCollectionIsNullOrEmpty)
            {
                let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
                if let runtimeCallee = collectionIsNullOrEmptyRuntimeCallee(
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                )
                {
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }
        // String stdlib: 0-arg methods (STDLIB-006)
        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "lowercase" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_lowercase_flat"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "uppercase" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_string_uppercase_flat"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "toRegex" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("__kk_string_toRegex_flat"),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "first" || calleeStr == "last" || calleeStr == "single" {
                    let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
                    let kkName = calleeStr == "first" ? "kk_string_first_flat"
                        : calleeStr == "last" ? "kk_string_last_flat"
                        : "kk_string_single_flat"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID, thrownExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "firstOrNull" || calleeStr == "lastOrNull" || calleeStr == "singleOrNull" {
                    let kkName = calleeStr == "firstOrNull" ? "kk_string_firstOrNull_flat"
                        : calleeStr == "lastOrNull" ? "kk_string_lastOrNull_flat"
                        : "kk_string_singleOrNull_flat"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "first" || calleeStr == "last" || calleeStr == "single" {
                    let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
                    let kkName = calleeStr == "first" ? "kk_string_first_flat"
                        : calleeStr == "last" ? "kk_string_last_flat"
                        : "kk_string_single_flat"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID, thrownExpr],
                        result: result,
                        canThrow: true,
                        thrownResult: nil
                    ))
                    return result
                }
                if calleeStr == "firstOrNull" || calleeStr == "lastOrNull" || calleeStr == "singleOrNull" {
                    let kkName = calleeStr == "firstOrNull" ? "kk_string_firstOrNull_flat"
                        : calleeStr == "lastOrNull" ? "kk_string_lastOrNull_flat"
                        : "kk_string_singleOrNull_flat"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(kkName),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: 1-arg methods (STDLIB-006)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let calleeStr = interner.resolve(calleeName)
            let isCharSequenceReceiver: Bool = {
                guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                      case let .classType(classType) = sema.types.kind(of: nonNullReceiverType)
                else {
                    return false
                }
                return classType.classSymbol == charSequenceSymbol
            }()
            let isCharSequenceTextHelper = calleeStr == "ifBlank"
                || calleeStr == "ifEmpty"
            let usesStringFlatABI = sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
            if usesStringFlatABI || (isCharSequenceTextHelper && isCharSequenceReceiver)
            {
                if calleeStr == "toRegex" {
                    let argType = sema.bindings.exprTypes[args[0].expr]
                    let isSetArg: Bool = {
                        guard let argType,
                              let (_, sym) = resolveClassTypeSymbol(argType, sema: sema)
                        else { return false }
                        let knownNames = KnownCompilerNames(interner: interner)
                        return knownNames.isSetLikeSymbol(sym)
                    }()
                    let rtName = isSetArg
                        ? "__kk_string_toRegex_with_options_flat"
                        : "__kk_string_toRegex_with_option_flat"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(rtName),
                        arguments: [loweredReceiverID, loweredArgIDs[0]],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
                let runtimeCall: (callee: String, arguments: [KIRExprID])? = switch calleeStr {
                case "split":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        nil
                    } else {
                        nil
                    }
                case "contains":
                    if isRegexLikeType(sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType, sema: sema, interner: interner) {
                        ("__kk_string_contains_regex_flat", [loweredReceiverID, loweredArgIDs[0]])
                    } else {
                        nil
                    }
                case "get":
                    ("kk_string_get_flat", [loweredReceiverID, loweredArgIDs[0]])
                case "compareTo":
                    ("kk_string_compareTo_flat", [loweredReceiverID, loweredArgIDs[0]])
                case "matches":
                    ("__kk_string_matches_regex_flat", [loweredReceiverID, loweredArgIDs[0]])

                default:
                    nil
                }
                if let runtimeCall {
                    let stringHOFCanThrow = calleeStr == "ifBlank"
                        || calleeStr == "ifEmpty"
                    let stringHOFThrownResult: KIRExprID? = nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCall.callee),
                        arguments: runtimeCall.arguments,
                        result: result,
                        canThrow: stringHOFCanThrow,
                        thrownResult: stringHOFThrownResult
                    ))
                    return result
                }
            }
        }

        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                if calleeStr == "get" {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get"),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }

                let rawRuntimeCallee: String? = switch calleeStr {
                case "fill":
                    "kk_array_fill"
                case "firstNotNullOf":
                    "__kk_iterable_firstNotNullOf"
                case "firstNotNullOfOrNull":
                    "__kk_iterable_firstNotNullOfOrNull"
                default:
                    nil
                }
                if let runtimeCallee = rawRuntimeCallee {
                    let canThrow = runtimeCallee == "__kk_iterable_firstNotNullOf"
                        || runtimeCallee == "__kk_iterable_firstNotNullOfOrNull"
                    let thrownResult = canThrow
                        ? arena.appendExpr(
                            .temporary(Int32(arena.expressions.count)),
                            type: sema.types.nullableAnyType
                        )
                        : nil
                    let hofArgIDs: [KIRExprID]
                    if (calleeStr == "firstNotNullOf" || calleeStr == "firstNotNullOfOrNull"),
                       normalizedArgIDs.count < 2
                    {
                        let closureRawExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                        instructions.append(.constValue(result: closureRawExpr, value: .intLiteral(0)))
                        hofArgIDs = normalizedArgIDs + [closureRawExpr]
                    } else {
                        hofArgIDs = normalizedArgIDs
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + hofArgIDs,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForCollectionFallback = !isSourceBackedTerminalCall
                && !isSourceBackedSequenceCall
                && isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
            let useIterableRuntimeForCollectionFallback = !isSourceBackedTerminalCall
                && !isSourceBackedSequenceCall
                && (sema.bindings.isCollectionExpr(receiverExpr)
                    || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
                let runtimeCallee: String?
                let mapName = interner.intern("map")
                let filterName = interner.intern("filter")
                let forEachName = interner.intern("forEach")
                let flatMapName = interner.intern("flatMap")
                let flatMapIndexedName = interner.intern("flatMapIndexed")
                let takeLastWhileName = interner.intern("takeLastWhile")
                let sortedByName = interner.intern("sortedBy")
                let sortedByDescendingName = interner.intern("sortedByDescending")
                let firstNotNullOfName = interner.intern("firstNotNullOf")
                let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
                let containsName = interner.intern("contains")
                let indexOfName = interner.intern("indexOf")
                let indexOfFirstName = interner.intern("indexOfFirst")
                let lastIndexOfName = interner.intern("lastIndexOf")
                let indexOfLastName = interner.intern("indexOfLast")
                let elementAtName = interner.intern("elementAt")
                let elementAtOrElseName = interner.intern("elementAtOrElse")
                let elementAtOrNullName = interner.intern("elementAtOrNull")
                let filterIndexedName = interner.intern("filterIndexed")
                let lastName = interner.intern("last")
                let minName = interner.intern("min")
                if calleeName == mapName {
                    runtimeCallee = "kk_sequence_map"
                } else if calleeName == filterName {
                    runtimeCallee = "kk_sequence_filter"
                } else if calleeName == interner.intern("takeLast") {
                    runtimeCallee = "kk_sequence_takeLast"
                } else if calleeName == forEachName {
                    runtimeCallee = "kk_sequence_forEach"
                } else if calleeName == flatMapName {
                    runtimeCallee = "kk_sequence_flatMap"
                } else if calleeName == flatMapIndexedName {
                    runtimeCallee = "kk_sequence_flatMapIndexed"
                } else if calleeName == takeLastWhileName {
                    runtimeCallee = "kk_sequence_takeLastWhile"
                } else if calleeName == sortedByName {
                    runtimeCallee = "kk_sequence_sortedBy"
                } else if calleeName == sortedByDescendingName {
                    runtimeCallee = "kk_sequence_sortedByDescending"
                } else if calleeName == firstNotNullOfName {
                    runtimeCallee = "kk_sequence_firstNotNullOf"
                } else if calleeName == firstNotNullOfOrNullName {
                    runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
                } else if calleeName == containsName {
                    runtimeCallee = "kk_sequence_contains"
                } else if calleeName == indexOfName {
                    runtimeCallee = "kk_sequence_indexOf"
                } else if calleeName == indexOfFirstName {
                    runtimeCallee = "kk_sequence_indexOfFirst"
                } else if calleeName == lastIndexOfName {
                    runtimeCallee = "kk_sequence_lastIndexOf"
                } else if calleeName == indexOfLastName {
                    runtimeCallee = "kk_sequence_indexOfLast"
                } else if calleeName == elementAtName {
                    runtimeCallee = "kk_sequence_elementAt"
                } else if calleeName == elementAtOrElseName {
                    runtimeCallee = "kk_sequence_elementAtOrElse"
                } else if calleeName == elementAtOrNullName {
                    runtimeCallee = "kk_sequence_elementAtOrNull"
                } else if calleeName == interner.intern("elementAtOrElse") {
                    runtimeCallee = "kk_sequence_elementAtOrElse"
                } else if calleeName == filterIndexedName {
                    runtimeCallee = "kk_sequence_filterIndexed"
                } else if calleeName == lastName {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_last" : "kk_sequence_last"
                } else if calleeName == minName {
                    runtimeCallee = "kk_sequence_min"
                } else if calleeName == interner.intern("max") {
                    runtimeCallee = "kk_sequence_max"
                } else if calleeName == interner.intern("intersect") {
                    runtimeCallee = "kk_sequence_intersect"
                } else if calleeName == interner.intern("any") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_any" : "kk_sequence_any"
                } else if calleeName == interner.intern("all") {
                    runtimeCallee = useIterableRuntimeForCollectionFallback ? "__kk_iterable_all" : "kk_sequence_all"
                } else if calleeName == interner.intern("none") {
                    runtimeCallee = "kk_sequence_none"
                } else if calleeName == interner.intern("mapNotNull") {
                    runtimeCallee = "kk_sequence_mapNotNull"
                } else if calleeName == interner.intern("mapIndexedNotNull") {
                    runtimeCallee = "kk_sequence_mapIndexedNotNull"
                } else if calleeName == interner.intern("firstNotNullOf") {
                    runtimeCallee = "kk_sequence_firstNotNullOf"
                } else if calleeName == interner.intern("firstNotNullOfOrNull") {
                    runtimeCallee = "kk_sequence_firstNotNullOfOrNull"
                } else if calleeName == interner.intern("random") {
                    runtimeCallee = "kk_sequence_random"
                } else if calleeName == interner.intern("randomOrNull") {
                    runtimeCallee = "kk_sequence_randomOrNull"
                } else if calleeName == interner.intern("requireNoNulls") {
                    runtimeCallee = "kk_sequence_requireNoNulls"
                } else if calleeName == interner.intern("reversed") {
                    runtimeCallee = "kk_sequence_reversed"
                } else if calleeName == interner.intern("mapIndexed") {
                    runtimeCallee = "kk_sequence_mapIndexed"
                } else if calleeName == interner.intern("flatMapIndexed") {
                    runtimeCallee = "kk_sequence_flatMapIndexed"
                } else if calleeName == interner.intern("onEach") {
                    runtimeCallee = "kk_sequence_onEach"
                } else if calleeName == interner.intern("onEachIndexed") {
                    runtimeCallee = "kk_sequence_onEachIndexed"
                } else if calleeName == interner.intern("plus") {
                    if let firstArg = args.first {
                        let argType = sema.types.makeNonNullable(
                            sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
                        )
                        runtimeCallee = (sema.bindings.isCollectionExpr(firstArg.expr)
                            || isSequenceLikeType(argType, sema: sema, interner: interner)
                            || isIterableOrCollectionInterfaceType(argType, sema: sema, interner: interner)
                            || isConcreteCollectionLikeType(argType, sema: sema, interner: interner))
                            ? "kk_sequence_plus"
                            : "kk_sequence_plus_element"
                    } else {
                        runtimeCallee = "kk_sequence_plus_element"
                    }
                } else if calleeName == interner.intern("plusElement") {
                    runtimeCallee = "kk_sequence_plus_element"
                } else if calleeName == interner.intern("minus") || calleeName == interner.intern("minusElement") {
                    runtimeCallee = "kk_sequence_minus"
                } else if calleeName == interner.intern("reduceOrNull") {
                    runtimeCallee = "kk_sequence_reduceOrNull"
                } else if calleeName == interner.intern("union") {
                    runtimeCallee = "kk_sequence_union"
                } else if calleeName == interner.intern("subtract") {
                    runtimeCallee = "kk_sequence_subtract"
                } else if calleeName == interner.intern("reduceRight") {
                    runtimeCallee = "kk_sequence_reduceRight"
                } else if calleeName == interner.intern("reduce") {
                    runtimeCallee = "kk_sequence_reduce"
                } else if calleeName == interner.intern("runningReduceIndexed") {
                    runtimeCallee = "kk_sequence_runningReduceIndexed"
                } else if calleeName == interner.intern("reduceRightIndexed") {
                    runtimeCallee = "kk_sequence_reduceRightIndexed"
                } else if calleeName == interner.intern("reduceRightOrNull") {
                    runtimeCallee = "kk_sequence_reduceRightOrNull"
                } else if calleeName == interner.intern("reduceRightIndexedOrNull") {
                    runtimeCallee = "kk_sequence_reduceRightIndexedOrNull"
                } else if calleeName == interner.intern("shuffled") {
                    switch normalizedArgIDs.count {
                    case 0: runtimeCallee = "kk_sequence_shuffled"
                    case 1: runtimeCallee = "kk_sequence_shuffled_random"
                    default: runtimeCallee = nil
                    }
                } else if calleeName == interner.intern("ifEmpty") {
                    runtimeCallee = "kk_sequence_ifEmpty"
                } else if calleeName == interner.intern("forEachIndexed") {
                    runtimeCallee = "kk_sequence_forEachIndexed"
                } else {
                    runtimeCallee = nil
                }
                if let runtimeCallee {
                    let canThrow = runtimeCallee == "kk_sequence_sortedBy"
                        || runtimeCallee == "kk_sequence_sortedByDescending"
                        || runtimeCallee == "kk_sequence_takeLastWhile"
                        || runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_takeLast"
                        || runtimeCallee == "kk_sequence_elementAt"
                        || runtimeCallee == "kk_sequence_elementAtOrElse"
                        || runtimeCallee == "kk_sequence_last"
                        || runtimeCallee == "__kk_iterable_last"
                        || runtimeCallee == "kk_sequence_min"
                        || runtimeCallee == "kk_sequence_max"
                        || runtimeCallee == "kk_sequence_any"
                        || runtimeCallee == "__kk_iterable_any"
                        || runtimeCallee == "kk_sequence_all"
                        || runtimeCallee == "__kk_iterable_all"
                        || runtimeCallee == "kk_sequence_none"
                        || runtimeCallee == "kk_sequence_indexOfFirst"
                        || runtimeCallee == "kk_sequence_indexOfLast"
                        || runtimeCallee == "kk_sequence_mapNotNull"
                        || runtimeCallee == "kk_sequence_mapIndexedNotNull"
                        || runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_random"
                        || runtimeCallee == "kk_sequence_randomOrNull"
                        || runtimeCallee == "kk_sequence_mapIndexed"
                        || runtimeCallee == "kk_sequence_filterIndexed"
                        || runtimeCallee == "kk_sequence_onEach"
                        || runtimeCallee == "kk_sequence_onEachIndexed"
                        || runtimeCallee == "kk_sequence_reduceOrNull"
                        || runtimeCallee == "kk_sequence_reduce"
                        || runtimeCallee == "kk_sequence_reduceRightIndexed"
                        || runtimeCallee == "kk_sequence_reduceRight"
                        || runtimeCallee == "kk_sequence_reduceRightOrNull"
                        || runtimeCallee == "kk_sequence_reduceRightIndexedOrNull"
                        || runtimeCallee == "kk_sequence_runningReduceIndexed"
                        || runtimeCallee == "kk_sequence_ifEmpty"
                    var runtimeArguments = [loweredReceiverID] + normalizedArgIDs
                    if runtimeCallee == "kk_sequence_firstNotNullOf"
                        || runtimeCallee == "kk_sequence_firstNotNullOfOrNull"
                        || runtimeCallee == "kk_sequence_takeLastWhile",
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_reduceOrNull",
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_indexOfFirst"
                        || runtimeCallee == "kk_sequence_reduceRightIndexed"
                        || runtimeCallee == "kk_sequence_reduceRightOrNull",
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_indexOfLast",
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_reduceRight",
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_reduceRightOrNull",
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_reduce", normalizedArgIDs.count == 1 {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_reduceRightIndexedOrNull",
                       normalizedArgIDs.count == 1
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[0],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, fnPtrExpr, envPtrExpr]
                    }
                    if runtimeCallee == "kk_sequence_elementAtOrElse",
                       normalizedArgIDs.count == 2
                    {
                        let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                            normalizedArgIDs[1],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        runtimeArguments = [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr]
                    }
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: runtimeArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let isSourceBackedListCall: Bool = {
                    guard let sourceCallee = chosenBase64Callee,
                          let symbol = sema.symbols.symbol(sourceCallee),
                          symbol.kind == .function,
                          sema.symbols.isSourceBackedSymbol(sourceCallee)
                    else {
                        return false
                    }
                    return true
                }()
                if !isSourceBackedListCall {
                let calleeStr = interner.resolve(calleeName)
                let primitiveSelectorKind = collectionSelectorPrimitiveCompareKind(of: args.first?.expr, sema: sema)
                let runtimeCallee: String? = switch calleeStr {
                case "sortedBy":
                    primitiveSelectorKind != nil ? "kk_list_sortedBy_primitive" : "kk_list_sortedBy"
                case "sortedByDescending":
                    primitiveSelectorKind != nil ? "kk_list_sortedByDescending_primitive" : "kk_list_sortedByDescending"
                case "sortedWith":
                    "kk_list_sortedWith"
                case "maxOf":
                    "kk_list_maxOf"
                case "minOf":
                    "kk_list_minOf"
                case "max":
                    "kk_list_max"
                case "min":
                    "kk_list_min"
                case "maxWith":
                    "kk_list_maxWith"
                case "maxWithOrNull":
                    "kk_list_maxWithOrNull"
                case "minWith":
                    "kk_list_minWith"
                case "minWithOrNull":
                    "kk_list_minWithOrNull"
                case "maxOfWith":
                    "kk_list_maxOfWith"
                case "maxOfWithOrNull":
                    "kk_list_maxOfWithOrNull"
                case "minOfWith":
                    "kk_list_minOfWith"
                case "minOfWithOrNull":
                    "kk_list_minOfWithOrNull"
                case "minBy":
                    "kk_list_minBy"
                case "partition":
                    "kk_list_partition"
                default:
                    nil
                }
                if let runtimeCallee {
                    var callArguments = [loweredReceiverID] + normalizedArgIDs
                    if let primitiveSelectorKind,
                       runtimeCallee == "kk_list_sortedBy_primitive" || runtimeCallee == "kk_list_sortedByDescending_primitive"
                    {
                        let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveSelectorKind.rawValue)), type: sema.types.intType)
                        instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveSelectorKind.rawValue))))
                        callArguments.append(kindExpr)
                    }
                    let canThrow = runtimeCallee == "kk_list_minBy"
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: callArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                    }
                }
            }
            if isRegexLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let calleeStr = interner.resolve(calleeName)
                let runtimeCallee: String? = switch calleeStr {
                case "find":
                    "__kk_regex_find_flat"
                case "findAll":
                    "__kk_regex_findAll_flat"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        let hasHOFLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false

        // KSP-307: ListWindowChunk public functions are source-backed, but codegen
        // still lowers their executable path to private runtime bridges.
        do {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            let isListWindowChunkReceiver = isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || isSetLikeType(nonNullReceiverType, sema: sema, interner: interner)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner)
                || isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner)

            if isListWindowChunkReceiver {
                func appendBridgeCall(
                    _ name: String,
                    _ runtimeArguments: [KIRExprID],
                    canThrow: Bool = false
                ) -> KIRExprID {
                    let thrownResult = canThrow ? arena.appendTemporary(type: sema.types.nullableAnyType) : nil
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(name),
                        arguments: runtimeArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult
                    ))
                    return result
                }

                func intLiteral(_ value: Int64) -> KIRExprID {
                    let expr = arena.appendExpr(.intLiteral(value), type: sema.types.intType)
                    instructions.append(.constValue(result: expr, value: .intLiteral(value)))
                    return expr
                }

                func windowedTransformRuntimeArguments() -> [KIRExprID]? {
                    guard hasHOFLambdaArg else {
                        return nil
                    }
                    let valueArgCount = args.count - 1
                    guard (1...3).contains(valueArgCount),
                          normalizedArgIDs.count > valueArgCount
                    else {
                        return nil
                    }

                    let sizeArg = normalizedArgIDs[0]
                    let stepArg = valueArgCount >= 2 ? normalizedArgIDs[1] : intLiteral(1)
                    let partialArg = valueArgCount >= 3 ? normalizedArgIDs[2] : intLiteral(0)
                    let fnPtrExpr: KIRExprID
                    let envPtrExpr: KIRExprID
                    if normalizedArgIDs.count > valueArgCount + 1 {
                        fnPtrExpr = normalizedArgIDs[valueArgCount]
                        envPtrExpr = normalizedArgIDs[valueArgCount + 1]
                    } else {
                        let split = splitCallableLambdaArgument(
                            normalizedArgIDs[valueArgCount],
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                        fnPtrExpr = split.fnPtrExpr
                        envPtrExpr = split.envPtrExpr
                    }
                    return [loweredReceiverID, sizeArg, stepArg, partialArg, fnPtrExpr, envPtrExpr]
                }

                switch interner.resolve(calleeName) {
                case "chunked" where !hasHOFLambdaArg && normalizedArgIDs.count == 1:
                    return appendBridgeCall("__kk_list_chunked", [loweredReceiverID, normalizedArgIDs[0]])
                case "chunked" where hasHOFLambdaArg && normalizedArgIDs.count == 2:
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return appendBridgeCall(
                        "__kk_list_chunked_transform",
                        [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr],
                        canThrow: true
                    )
                case "windowed" where !hasHOFLambdaArg && (1...3).contains(normalizedArgIDs.count):
                    let sizeArg = normalizedArgIDs[0]
                    let stepArg = normalizedArgIDs.count >= 2 ? normalizedArgIDs[1] : intLiteral(1)
                    let partialArg = normalizedArgIDs.count >= 3 ? normalizedArgIDs[2] : intLiteral(0)
                    return appendBridgeCall("__kk_list_windowed", [loweredReceiverID, sizeArg, stepArg, partialArg])
                case "windowed" where hasHOFLambdaArg:
                    guard let runtimeArguments = windowedTransformRuntimeArguments() else {
                        break
                    }
                    return appendBridgeCall(
                        "__kk_list_windowed_transform",
                        runtimeArguments,
                        canThrow: true
                    )
                case "zip" where !hasHOFLambdaArg && normalizedArgIDs.count == 1:
                    return appendBridgeCall("__kk_list_zip", [loweredReceiverID, normalizedArgIDs[0]])
                case "zip" where hasHOFLambdaArg && normalizedArgIDs.count == 2:
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[1],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return appendBridgeCall(
                        "__kk_list_zip_transform",
                        [loweredReceiverID, normalizedArgIDs[0], fnPtrExpr, envPtrExpr],
                        canThrow: true
                    )
                case "zipWithNext" where normalizedArgIDs.isEmpty:
                    return appendBridgeCall("__kk_list_zipWithNext", [loweredReceiverID])
                case "zipWithNext" where hasHOFLambdaArg && normalizedArgIDs.count == 1:
                    let (fnPtrExpr, envPtrExpr) = splitCallableLambdaArgument(
                        normalizedArgIDs[0],
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    return appendBridgeCall(
                        "__kk_list_zipWithNextTransform",
                        [loweredReceiverID, fnPtrExpr, envPtrExpr],
                        canThrow: true
                    )
                default:
                    break
                }
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let runtimeCallee: String? = switch interner.resolve(calleeName) {
                case "toList":
                    isSourceBackedArrayToListCall ? nil : "__kk_array_toList"
                case "toMutableList":
                    "kk_array_toMutableList"
                case "toTypedArray":
                    isSourceBackedArrayConversionCall ? nil : "__kk_array_copyOf"
                case "copyOf":
                    isSourceBackedArrayCopyCall ? nil : "__kk_array_copyOf"
                case "concatToString":
                    "kk_chararray_concatToString"
                default:
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            let useSequenceRuntimeForTerminalFallback = !isSourceBackedTerminalCall
                && !isSourceBackedSequenceCall
                && isSequenceLikeType(
                    nonNullReceiverType,
                    sema: sema,
                    interner: interner
                )
            let useIterableRuntimeForTerminalFallback = !isSourceBackedTerminalCall
                && (sema.bindings.isCollectionExpr(receiverExpr)
                || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
                && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            if useSequenceRuntimeForTerminalFallback || useIterableRuntimeForTerminalFallback {
                let toListID = interner.intern("toList")
                let constrainOnceID = interner.intern("constrainOnce")
                let sortedID = interner.intern("sorted")
                let sortedDescendingID = interner.intern("sortedDescending")
                let filterNotNullID = interner.intern("filterNotNull")
                let requireNoNullsID = interner.intern("requireNoNulls")
                let withIndexID = interner.intern("withIndex")
                let firstID = interner.intern("first")
                let firstOrNullID = interner.intern("firstOrNull")
                let lastID = interner.intern("last")
                let lastOrNullID = interner.intern("lastOrNull")
                let countID = interner.intern("count")
                let sumID = interner.intern("sum")
                let averageID = interner.intern("average")
                let toMutableListID = interner.intern("toMutableList")
                let toMutableSetID = interner.intern("toMutableSet")
                let toSortedSetID = interner.intern("toSortedSet")
                let toHashSetID = interner.intern("toHashSet")
                let unzipID = interner.intern("unzip")
                let anyID = interner.intern("any")
                let noneID = interner.intern("none")

                let seqFirstCallee = interner.intern("kk_sequence_first")
                let seqFirstOrNullCallee = interner.intern("kk_sequence_firstOrNull")
                let seqLastCallee = interner.intern("kk_sequence_last")
                let seqLastOrNullCallee = interner.intern("kk_sequence_lastOrNull")
                let seqSingleCallee = interner.intern("kk_sequence_single")
                let seqSingleOrNullCallee = interner.intern("kk_sequence_singleOrNull")
                let seqCountCallee = interner.intern("kk_sequence_count")
                let seqAnyCallee = interner.intern("kk_sequence_any")
                let seqNoneCallee = interner.intern("kk_sequence_none")
                let seqToListCallee = interner.intern("kk_sequence_to_list")

                let runtimeCallee: InternedString? = switch calleeName {
                case toListID:
                    useIterableRuntimeForTerminalFallback
                        ? interner.intern("__kk_collection_toList")
                        : seqToListCallee
                case constrainOnceID:
                    interner.intern("kk_sequence_constrainOnce")
                case sortedID:
                    interner.intern("kk_sequence_sorted")
                case sortedDescendingID:
                    interner.intern("kk_sequence_sortedDescending")
                case interner.intern("shuffled") where args.isEmpty:
                    interner.intern("kk_sequence_shuffled")
                case filterNotNullID:
                    interner.intern("kk_sequence_filterNotNull")
                case requireNoNullsID:
                    interner.intern("kk_sequence_requireNoNulls")
                case withIndexID:
                    interner.intern("kk_sequence_withIndex")
                case firstID:
                    seqFirstCallee
                case firstOrNullID:
                    seqFirstOrNullCallee
                case lastID:
                    seqLastCallee
                case lastOrNullID:
                    seqLastOrNullCallee
                case interner.intern("single"):
                    seqSingleCallee
                case interner.intern("singleOrNull"):
                    seqSingleOrNullCallee
                case countID:
                    seqCountCallee
                case sumID:
                    interner.intern("kk_sequence_sum")
                case averageID:
                    interner.intern("kk_sequence_average")
                case toMutableListID:
                    toMutableListRuntimeCalleeForSequenceOrIterableFallback(
                        useIterableFallback: useIterableRuntimeForTerminalFallback,
                        interner: interner
                    )
                case toMutableSetID:
                    interner.intern(useIterableRuntimeForTerminalFallback
                        ? "__kk_iterable_toMutableSet"
                        : "kk_sequence_toMutableSet")
                case toSortedSetID:
                    interner.intern("kk_sequence_toSortedSet")
                case toHashSetID:
                    interner.intern("kk_sequence_toHashSet")
                case unzipID:
                    interner.intern("kk_sequence_unzip")
                case anyID:
                    seqAnyCallee
                case noneID:
                    seqNoneCallee
                default:
                    nil
                }
                if let runtimeCallee {
                    // any()/none() with no predicate: pass fnPtr=0, closure=0 sentinel
                    if runtimeCallee == seqAnyCallee || runtimeCallee == seqNoneCallee {
                        let zeroExpr = arena.appendExpr(.intLiteral(0), type: nil)
                        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        instructions.append(.call(
                            symbol: nil,
                            callee: runtimeCallee,
                            arguments: [loweredReceiverID, zeroExpr, zeroExpr],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        return result
                    }
                    let canThrow = runtimeCallee == seqFirstCallee
                        || runtimeCallee == seqFirstOrNullCallee
                        || runtimeCallee == seqLastCallee
                        || runtimeCallee == seqLastOrNullCallee
                        || runtimeCallee == seqCountCallee
                        || runtimeCallee == seqToListCallee
                    instructions.append(.call(
                        symbol: nil,
                        callee: runtimeCallee,
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: canThrow,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // String stdlib: format(vararg args) (STDLIB-006)
        if interner.resolve(calleeName) == "format",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "__kk_string_format_flat"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                func boxedFormatArgument(_ argExpr: ExprID, loweredArgID: KIRExprID) -> KIRExprID {
                    let argType = sema.bindings.exprTypes[argExpr] ?? sema.types.anyType
                    let nonNullArgType = sema.types.makeNonNullable(argType)
                    return boxValueForAnySlot(
                        loweredArgID,
                        sourceType: nonNullArgType,
                        types: sema.types,
                        symbols: sema.symbols,
                        interner: interner,
                        arena: arena,
                        resultType: sema.types.nullableAnyType,
                        into: &instructions
                    )
                }

                let boxedArgIDs = zip(args, loweredArgIDs).map { arg, loweredArgID in
                    boxedFormatArgument(arg.expr, loweredArgID: loweredArgID)
                }

                let packedArgs: KIRExprID
                if boxedArgIDs.count == 1, args.first?.isSpread == true {
                    packedArgs = boxedArgIDs[0]
                } else {
                    packedArgs = driver.callSupportLowerer.packVarargArguments(
                        argIndices: Array(boxedArgIDs.indices),
                        providedArguments: boxedArgIDs,
                        spreadFlags: args.map(\.isSpread),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.nullableAnyType,
                        types: sema.types,
                        symbols: sema.symbols,
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_string_format_flat"),
                    arguments: [loweredReceiverID, packedArgs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }
        }

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)

        // Extract qualified super type information for super<Interface> calls
        var qualifiedSuperType: SymbolID?
        if isSuperCall, case let .superRef(interfaceQualifier, _) = ast.arena.expr(receiverExpr) {
            if let qualifier = interfaceQualifier {
                // Find the interface symbol that matches the qualifier
                if let currentReceiverType = sema.bindings.exprTypes[receiverExpr],
                   let classType = resolveClassType(currentReceiverType, sema: sema) {
                    let classSymbol = classType.classSymbol
                    let directSupertypes = sema.symbols.directSupertypes(for: classSymbol)
                    let qualifierStr = interner.resolve(qualifier)
                    for superID in directSupertypes {
                        guard let superSym = sema.symbols.symbol(superID) else { continue }
                        if superSym.kind == SymbolKind.interface && interner.resolve(superSym.name) == qualifierStr {
                            qualifiedSuperType = superID
                            break
                        }
                    }
                }
            }
        }

        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            argumentExprs: args.map(\.expr),
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        if qualifiedSuperType == nil,
           isSuperCall,
           case let .superRef(interfaceQualifier?, _) = ast.arena.expr(receiverExpr),
           let chosenCallee = callBinding?.chosenCallee,
           chosenCallee != .invalid,
           let ownerSymbol = sema.symbols.parentSymbol(for: chosenCallee),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .interface,
           interner.resolve(ownerInfo.name) == interner.resolve(interfaceQualifier)
        {
            qualifiedSuperType = ownerSymbol
        }
        let chosen: SymbolID? = if let chosenCallee = callBinding?.chosenCallee, chosenCallee != .invalid {
            chosenCallee
        } else {
            SymbolID?.none
        }
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: normalizedArgIDs,
            callBinding: callBinding,
            chosenCallee: chosen,
            spreadFlags: args.map(\.isSpread),
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        var finalArguments = normalized.arguments
        appendReceiverToMemberArguments(
            loweredReceiverID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            chosenCallee: chosen,
            prependReceiverForUnresolvedCollectionCall: prependReceiverForUnresolvedCollectionCall,
            sema: sema,
            interner: interner,
            arguments: &finalArguments
        )
        emitMemberCallInstruction(
            normalized: normalized,
            callBinding: callBinding,
            chosenCallee: chosen,
            calleeName: calleeName,
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: loweredReceiverID),
            result: result,
            isSuperCall: isSuperCall,
            qualifiedSuperType: qualifiedSuperType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: finalArguments,
            sourceArgExprs: args.map(\.expr),
            sourceArgLabels: args.map(\.label)
        )
        return result
    }
}
