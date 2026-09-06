// swiftlint:disable file_length

/// Name-based fallback resolution for unresolved synthetic and collection members.
extension CallLowerer {
    /// Returns true only for the source-backed HashSet declaration. Other set
    /// types may provide their own source implementation and must retain the
    /// resolved symbol for ABI return-type handling.
    func isSourceBackedHashSetType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(receiverType), sema: sema
        ) else {
            return false
        }
        return symbol.fqName == knownNames.kotlinCollectionsHashSetFQName
    }

    /// HashSet is source-backed for its nominal API, but its instances are
    /// RuntimeSetBox values without a Kotlin vtable. Keep the mutating and
    /// membership operations on their runtime ABI entry points.
    func runtimeBackedSetMemberCallee(
        memberName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if isSourceBackedHashSetType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "equals":
                return interner.intern("kk_any_member_equals")
            case "hashCode":
                return interner.intern("kk_any_member_hashCode")
            default:
                break
            }
        }
        if memberName == "contains",
           isSetLikeType(nonNullReceiverType, sema: sema, interner: interner)
        {
            return interner.intern("__kk_set_contains")
        }
        if isMutableSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "add":
                return interner.intern("__kk_mutable_set_add")
            case "remove":
                return interner.intern("__kk_mutable_set_remove")
            case "clear":
                return interner.intern("__kk_mutable_set_clear")
            default:
                break
            }
        }
        return nil
    }

    // swiftlint:disable cyclomatic_complexity
    func unresolvedSyntheticMemberCallee(
        memberName: String,
        receiverExpr: ExprID,
        receiverType: TypeID,
        argumentCount: Int,
        sourceArgumentCount: Int? = nil,
        hasHOFLambdaArg: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        // HOF arity is the number of source-level arguments (excluding the receiver).
        // When the caller already prepended the receiver into argumentCount, the source
        // count must be supplied separately so StdlibSurfaceSpec arity entries (which
        // count lambda args only) are matched correctly.
        let hofArity = sourceArgumentCount ?? argumentCount
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        // OpenEndRange's generic contains member is still a compiler residual
        // (KSP-652). Keep its source-backed cross-type overloads executable by
        // lowering the residual call to the existing range bridge.
        if memberName == "contains",
           let (_, receiverSymbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema),
           interner.resolve(receiverSymbol.name) == "OpenEndRange"
        {
            return interner.intern("__kk_range_contains")
        }
        if let rangeKind = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ),
           let runtimeLinkName = MemberRuntimeDispatch.rangeRuntimeLinkName(for: MemberDispatchKey(
               receiverKind: rangeKind,
               memberName: memberName,
               arity: hofArity,
               lambdaShape: hasHOFLambdaArg ? .hofLambda : .none
           ))
        {
            return interner.intern(runtimeLinkName)
        }
        if let collectionKind = MemberRuntimeDispatch.collectionReceiverKind(
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) {
            switch collectionKind {
            case .set, .collection, .iterable:
                // List sorting is source-backed, but Iterable/Collection/Set
                // receivers still use the collection-compatible runtime ABI.
                switch memberName {
                case "sortedBy":
                    return interner.intern("kk_list_sortedBy")
                default:
                    break
                }
            default:
                break
            }
        }
        if let collectionKind = MemberRuntimeDispatch.collectionReceiverKind(
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ),
           // Only allow the early-return for kinds that map cleanly to their own
           // surface-spec entries (.list, .map, .sequence).  .set, .collection,
           // and .iterable all map to .list inside stdlibSurfaceOwnerKind, so
           // collectionRuntimeLinkName would return a *List* runtime function for
           // those receivers when hofArity==1 (SOURCE count), bypassing the
           // isSetLikeType block and the bundled Kotlin Set declarations that
           // correctly implement them.
           collectionKind == .list || collectionKind == .map || collectionKind == .sequence,
           let runtimeLinkName = MemberRuntimeDispatch.collectionRuntimeLinkName(for: MemberDispatchKey(
               receiverKind: collectionKind,
               memberName: memberName,
               arity: hofArity,
               lambdaShape: hasHOFLambdaArg ? .hofLambda : .none
           ))
        {
            return interner.intern(runtimeLinkName)
        }
        if memberName == "length",
           sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
        {
            return interner.intern("__kk_string_struct_get_length")
        }
        // KSP-724: `CharSequence.length` is resolved through the bundled
        // `kotlin.CharSequence` interface, so the `kk_char_sequence_length`
        // fallback is no longer needed.
        if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
            switch memberName {
            case "compareTo":
                return interner.intern("kk_string_compareTo_flat")
            case "get":
                return interner.intern("kk_string_get_flat")
            case "toRegex":
                return argumentCount == 0
                    ? interner.intern("__kk_string_toRegex_flat")
                    : interner.intern("__kk_string_toRegex_with_option_flat")
            default:
                break
            }
        }

        if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            // KSP-426: List sorting and extrema HOFs are bundled Kotlin source.
            case "sortedByDescending":
                return interner.intern("kk_list_sortedByDescending")
            case "sortedWith":
                return interner.intern("kk_list_sortedWith")

            case "maxBy":
                return interner.intern("kk_list_maxBy")
            case "maxByOrNull":
                return interner.intern("kk_list_maxByOrNull")
            case "minByOrNull":
                return interner.intern("kk_list_minByOrNull")
            case "minBy":
                return interner.intern("kk_list_minBy")
            case "maxOf":
                return interner.intern("kk_list_maxOf")
            case "minOf":
                return interner.intern("kk_list_minOf")
            case "max":
                return interner.intern("kk_list_max")
            case "min":
                return interner.intern("kk_list_min")
            case "maxWith":
                return interner.intern("kk_list_maxWith")
            case "maxWithOrNull":
                return interner.intern("kk_list_maxWithOrNull")
            case "minWith":
                return interner.intern("kk_list_minWith")
            case "minWithOrNull":
                return interner.intern("kk_list_minWithOrNull")
            case "maxOfWith":
                return interner.intern("kk_list_maxOfWith")
            case "maxOfWithOrNull":
                return interner.intern("kk_list_maxOfWithOrNull")
            case "minOfWith":
                return interner.intern("kk_list_minOfWith")
            case "minOfWithOrNull":
                return interner.intern("kk_list_minOfWithOrNull")
            default:
                break
            }
        }

        if isMutableSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "addAll":
                return interner.intern("__kk_mutable_set_addAll")
            case "removeAll":
                return interner.intern("__kk_mutable_set_removeAll")
            case "retainAll":
                return interner.intern("__kk_mutable_set_retainAll")
            default:
                break
            }
        }

        if isMutableListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            // KSP-426: MutableList sorting HOFs are bundled Kotlin source.
            case "add" where argumentCount == 1:
                return interner.intern("__kk_mutable_list_add")
            case "addAll":
                return interner.intern("__kk_mutable_list_addAll")
            case "removeAll":
                return interner.intern("__kk_mutable_list_removeAll")
            case "retainAll":
                return interner.intern("__kk_mutable_list_retainAll")
            case "removeFirst":
                return interner.intern("__kk_mutable_list_removeFirst")
            case "removeFirstOrNull":
                return interner.intern("__kk_mutable_list_removeFirstOrNull")
            case "removeLast":
                return interner.intern("__kk_mutable_list_removeLast")
            case "removeLastOrNull":
                return interner.intern("__kk_mutable_list_removeLastOrNull")
            default:
                break
            }
        }

        if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "get":
                return interner.intern("kk_array_get")
            case "toList":
                return interner.intern("__kk_array_toList")
            case "toMutableList":
                return interner.intern("kk_array_toMutableList")
            case "toTypedArray":
                return interner.intern("__kk_array_copyOf")
            case "fill":
                return interner.intern("kk_array_fill")
            case "asSequence":
                return interner.intern("kk_array_asSequence")
            default:
                break
            }
        }

        // Set receivers keep only the element-storage bridge; everything else is
        // declared in the bundled Kotlin stdlib (Stdlib/kotlin/collections/SetHOF.kt).
        if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "toTypedArray":
                return interner.intern("__kk_collection_toTypedArray")
            case "contains":
                return interner.intern("__kk_set_contains")
            default:
                break
            }
        }

        switch memberName {
        // KSP-426: List sorting/extrema HOFs are bundled Kotlin source.
        case "sortedByDescending":
            return interner.intern("kk_list_sortedByDescending")
        case "maxBy":
            return interner.intern("kk_list_maxBy")
        case "maxByOrNull":
            return interner.intern("kk_list_maxByOrNull")
        case "minByOrNull":
            return interner.intern("kk_list_minByOrNull")
        case "minBy":
            return interner.intern("kk_list_minBy")
        case "maxOf":
            return interner.intern("kk_list_maxOf")
        case "minOf":
            return interner.intern("kk_list_minOf")
        case "max":
            return interner.intern("kk_list_max")
        case "min":
            return interner.intern("kk_list_min")
        case "maxWith":
            return interner.intern("kk_list_maxWith")
        case "maxWithOrNull":
            return interner.intern("kk_list_maxWithOrNull")
        case "minWith":
            return interner.intern("kk_list_minWith")
        case "minWithOrNull":
            return interner.intern("kk_list_minWithOrNull")
        case "maxOfWith":
            return interner.intern("kk_list_maxOfWith")
        case "maxOfWithOrNull":
            return interner.intern("kk_list_maxOfWithOrNull")
        case "minOfWith":
            return interner.intern("kk_list_minOfWith")
        case "minOfWithOrNull":
            return interner.intern("kk_list_minOfWithOrNull")
        case "sortedWith":
            return interner.intern("kk_list_sortedWith")
        default:
            break
        }

        let useSequenceRuntimeForCollectionFallback = isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
        let useIterableRuntimeForCollectionFallback = (sema.bindings.isCollectionExpr(receiverExpr)
            || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
            && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
        // Bare Iterable/Collection/Set interfaces are also matched by
        // isConcreteCollectionLikeType, so the gate above excludes them. That is
        // intentional for general HOF routing: Set members resolve through the
        // bundled Kotlin declarations instead of kk_sequence_* (mapNotNull/flatMap/
        // count on a set handle would return empty or 0). joinTo/joinToString also
        // resolve to bundled Kotlin source (KSP-435).
        if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
            let internedMemberName = interner.intern(memberName)
            let mapName = interner.intern("map")
            let filterName = interner.intern("filter")
            let toListName = interner.intern("toList")
            let forEachName = interner.intern("forEach")
            let flatMapName = interner.intern("flatMap")
            let flatMapIndexedName = interner.intern("flatMapIndexed")
            let takeLastWhileName = interner.intern("takeLastWhile")
            let sortedName = interner.intern("sorted")
            let sortedByName = interner.intern("sortedBy")
            let sortedByDescendingName = interner.intern("sortedByDescending")
            let sortedDescendingName = interner.intern("sortedDescending")
            let firstNotNullOfName = interner.intern("firstNotNullOf")
            let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
            let firstName = interner.intern("first")
            let firstOrNullName = interner.intern("firstOrNull")
            let lastName = interner.intern("last")
            let countName = interner.intern("count")
            switch internedMemberName {
            case mapName:
                return interner.intern("kk_sequence_map")
            case filterName:
                return interner.intern("kk_sequence_filter")
            case interner.intern("takeLast"):
                return interner.intern("kk_sequence_takeLast")
            case toListName:
                return interner.intern("kk_sequence_to_list")
            case interner.intern("constrainOnce"):
                return interner.intern("kk_sequence_constrainOnce")
            case forEachName:
                return interner.intern("kk_sequence_forEach")
            case flatMapName:
                return interner.intern("kk_sequence_flatMap")
            case flatMapIndexedName:
                return interner.intern("kk_sequence_flatMapIndexed")
            case takeLastWhileName:
                return interner.intern("kk_sequence_takeLastWhile")
            case sortedName:
                return interner.intern("kk_sequence_sorted")
            case sortedByName:
                return interner.intern("kk_sequence_sortedBy")
            case sortedByDescendingName:
                return interner.intern("kk_sequence_sortedByDescending")
            case sortedDescendingName:
                return interner.intern("kk_sequence_sortedDescending")
            case interner.intern("shuffled"):
                switch argumentCount {
                case 0:
                    return interner.intern("kk_sequence_shuffled")
                case 1:
                    return interner.intern("kk_sequence_shuffled_random")
                default:
                    return nil
                }
            case firstNotNullOfName:
                return interner.intern("kk_sequence_firstNotNullOf")
            case firstNotNullOfOrNullName:
                return interner.intern("kk_sequence_firstNotNullOfOrNull")
            case interner.intern("contains"):
                return interner.intern("kk_sequence_contains")
            case interner.intern("indexOf"):
                return interner.intern("kk_sequence_indexOf")
            case interner.intern("indexOfFirst"):
                return interner.intern("kk_sequence_indexOfFirst")
            case interner.intern("lastIndexOf"):
                return interner.intern("kk_sequence_lastIndexOf")
            case interner.intern("indexOfLast"):
                return interner.intern("kk_sequence_indexOfLast")
            case interner.intern("intersect"):
                return interner.intern("kk_sequence_intersect")
            case interner.intern("elementAt"):
                return interner.intern("kk_sequence_elementAt")
            case interner.intern("elementAtOrNull"):
                return interner.intern("kk_sequence_elementAtOrNull")
            case interner.intern("single"):
                return interner.intern("kk_sequence_single")
            case interner.intern("singleOrNull"):
                return interner.intern("kk_sequence_singleOrNull")
            case interner.intern("any"):
                return interner.intern("kk_sequence_any")
            case interner.intern("all"):
                return interner.intern("kk_sequence_all")
            case interner.intern("none"):
                return interner.intern("kk_sequence_none")
            case interner.intern("mapNotNull"):
                return interner.intern("kk_sequence_mapNotNull")
            case interner.intern("mapIndexedNotNull"):
                return interner.intern("kk_sequence_mapIndexedNotNull")
            case interner.intern("firstNotNullOf"):
                return interner.intern("kk_sequence_firstNotNullOf")
            case interner.intern("firstNotNullOfOrNull"):
                return interner.intern("kk_sequence_firstNotNullOfOrNull")
            case interner.intern("filterNot"):
                return interner.intern("kk_sequence_filterNot")
            case interner.intern("filterNotNull"):
                return interner.intern("kk_sequence_filterNotNull")
            case interner.intern("requireNoNulls"):
                return interner.intern("kk_sequence_requireNoNulls")
            case interner.intern("reversed"):
                return interner.intern("kk_sequence_reversed")
            case interner.intern("mapIndexed"):
                return interner.intern("kk_sequence_mapIndexed")
            case interner.intern("filterIndexed"):
                return interner.intern("kk_sequence_filterIndexed")
            case interner.intern("flatMapIndexed"):
                return interner.intern("kk_sequence_flatMapIndexed")
            case interner.intern("withIndex"):
                return interner.intern("kk_sequence_withIndex")
            case interner.intern("onEach"):
                return interner.intern("kk_sequence_onEach")
            case interner.intern("onEachIndexed"):
                return interner.intern("kk_sequence_onEachIndexed")
            case interner.intern("plus"), interner.intern("plusElement"):
                return interner.intern("kk_sequence_plus_element")
            case interner.intern("minus"), interner.intern("minusElement"):
                return interner.intern("kk_sequence_minus")
            case interner.intern("union"):
                return interner.intern("kk_sequence_union")
            case interner.intern("subtract"):
                return interner.intern("kk_sequence_subtract")
            case interner.intern("ifEmpty"):
                return interner.intern("kk_sequence_ifEmpty")
            case firstName:
                return interner.intern("kk_sequence_first")
            case firstOrNullName:
                return interner.intern("kk_sequence_firstOrNull")
            case interner.intern("random"):
                return interner.intern("kk_sequence_random")
            case interner.intern("randomOrNull"):
                return interner.intern("kk_sequence_randomOrNull")
            case lastName:
                return interner.intern("kk_sequence_last")
            case interner.intern("lastOrNull"):
                return interner.intern("kk_sequence_lastOrNull")
            case countName:
                return interner.intern("kk_sequence_count")
            case interner.intern("max"):
                return interner.intern("kk_sequence_max")
            case interner.intern("sum"):
                return interner.intern("kk_sequence_sum")
            case interner.intern("average"):
                return interner.intern("kk_sequence_average")
            case interner.intern("toCollection"):
                return interner.intern("kk_sequence_toCollection")
            case interner.intern("toMutableList"):
                return toMutableListRuntimeCalleeForSequenceOrIterableFallback(
                    useIterableFallback: useIterableRuntimeForCollectionFallback,
                    interner: interner
                )
            case interner.intern("toMutableSet"):
                return interner.intern("kk_sequence_toMutableSet")
            case interner.intern("toSortedSet"):
                return interner.intern("kk_sequence_toSortedSet")
            case interner.intern("toHashSet"):
                return interner.intern("kk_sequence_toHashSet")
            case interner.intern("min"):
                return interner.intern("kk_sequence_min")
            case interner.intern("unzip"):
                return interner.intern("kk_sequence_unzip")
            case interner.intern("foldIndexed"):
                return interner.intern("kk_sequence_foldIndexed")
            case interner.intern("runningFold"):
                return interner.intern("kk_sequence_runningFold")
            case interner.intern("scan"):
                return interner.intern("kk_sequence_scan")
            case interner.intern("runningFoldIndexed"):
                return interner.intern("kk_sequence_runningFoldIndexed")
            case interner.intern("scanIndexed"):
                return interner.intern("kk_sequence_scanIndexed")
            case interner.intern("reduceOrNull"):
                return interner.intern("kk_sequence_reduceOrNull")
            case interner.intern("reduce"):
                return interner.intern("kk_sequence_reduce")
            case interner.intern("reduceRight"):
                return interner.intern("kk_sequence_reduceRight")
            case interner.intern("reduceIndexed"):
                return interner.intern("kk_sequence_reduceIndexed")
            case interner.intern("reduceIndexedOrNull"):
                return interner.intern("kk_sequence_reduceIndexedOrNull")
            case interner.intern("reduceRightIndexed"):
                return interner.intern("kk_sequence_reduceRightIndexed")
            case interner.intern("reduceRightOrNull"):
                return interner.intern("kk_sequence_reduceRightOrNull")
            case interner.intern("reduceRightIndexedOrNull"):
                return interner.intern("kk_sequence_reduceRightIndexedOrNull")
            case interner.intern("runningReduceIndexed"):
                return interner.intern("kk_sequence_runningReduceIndexed")
            default:
                break
            }
        }

        return nil
    }

    // swiftlint:enable cyclomatic_complexity

    /// BUG-196: user classes that extend a runtime-backed collection class
    /// (e.g. `LinkedHashSet`) are not themselves named `Set`/`List`, so look at
    /// the receiver symbol and its supertypes when classifying collection kind.
    private func collectionKindWithSupertypes(
        of symbol: SemanticSymbol,
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> KnownCollectionKind? {
        if let kind = knownNames.collectionKind(of: symbol) {
            return kind
        }
        var visited: Set<SymbolID> = []
        var queue = sema.symbols.directSupertypes(for: symbol.id)
        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            guard visited.insert(currentID).inserted else { continue }
            guard let currentSymbol = sema.symbols.symbol(currentID) else { continue }
            if let kind = knownNames.collectionKind(of: currentSymbol) {
                return kind
            }
            queue.append(contentsOf: sema.symbols.directSupertypes(for: currentID))
        }
        return nil
    }

    /// Resolves collection-level members (`size`, `isEmpty`, `iterator`) to
    /// their concrete runtime callee by mapping receiver kind to the
    /// corresponding runtime symbol (e.g. `.list` -> `kk_list_size`).
    func unresolvedCollectionMemberCallee(
        memberName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard memberName == "size"
              || memberName == "isEmpty"
              || memberName == "isNotEmpty"
              || memberName == "iterator"
              || memberName == "firstNotNullOf"
              || memberName == "firstNotNullOfOrNull"
              || memberName == "requireNoNulls"
              || memberName == "reduce"
              || memberName == "reduceRight"
              || memberName == "reduceIndexed"
              || memberName == "reduceRightIndexed"
              || memberName == "reduceRightOrNull"
              || memberName == "reduceRightIndexedOrNull"
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        if memberName == "size" || memberName == "isEmpty" {
            func collectionKind(
                for type: TypeID,
                visitedTypeParams: inout Set<SymbolID>
            ) -> KnownCollectionKind? {
                let nonNullType = sema.types.makeNonNullable(type)
                switch sema.types.kind(of: nonNullType) {
                case let .classType(classType):
                    guard let symbol = sema.symbols.symbol(classType.classSymbol) else {
                        return nil
                    }
                    return collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames)
                case let .intersection(parts):
                    for part in parts {
                        if let kind = collectionKind(for: part, visitedTypeParams: &visitedTypeParams) {
                            return kind
                        }
                    }
                    return nil
                case let .typeParam(typeParam):
                    guard visitedTypeParams.insert(typeParam.symbol).inserted else {
                        return nil
                    }
                    for bound in sema.symbols.typeParameterUpperBounds(for: typeParam.symbol) {
                        if let kind = collectionKind(for: bound, visitedTypeParams: &visitedTypeParams) {
                            return kind
                        }
                    }
                    return nil
                default:
                    return nil
                }
            }

            var visitedTypeParams = Set<SymbolID>()
            switch (memberName, collectionKind(for: receiverType, visitedTypeParams: &visitedTypeParams)) {
            case ("size", .map?):
                return interner.intern("kk_map_size")
            case ("size", .set?):
                return interner.intern("__kk_set_size")
            case ("size", .array?):
                return interner.intern("__kk_array_size")
            case ("size", .list?):
                return interner.intern("__kk_list_size")
            case ("size", .collection?):
                return interner.intern("__kk_collection_size")
            case ("isEmpty", .map?):
                return interner.intern("kk_map_is_empty")
            case ("isEmpty", .set?):
                return interner.intern("__kk_set_is_empty")
            case ("isEmpty", .array?):
                return interner.intern("kk_array_is_empty")
            case ("isEmpty", .list?):
                return interner.intern("kk_list_is_empty")
            case ("isEmpty", .collection?):
                return interner.intern("__kk_collection_isEmpty")
            default:
                return nil
            }
        }

        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return nil
        }

        switch memberName {
        case "size":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .map?:
                return interner.intern("kk_map_size")
            case .set?:
                return interner.intern("__kk_set_size")
            case .array?:
                return interner.intern("__kk_array_size")
            case .list?:
                return interner.intern("__kk_list_size")
            case .collection?:
                // A bare `Collection<T>` receiver can be backed by either a list
                // or a set box, so it needs the type-tag dispatching bridge.
                return interner.intern("__kk_collection_size")
            default:
                break
            }
        case "isEmpty":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .map?:
                return interner.intern("kk_map_is_empty")
            case .set?:
                return interner.intern("__kk_set_is_empty")
            case .array?:
                return interner.intern("kk_array_is_empty")
            case .list?, .collection?:
                return interner.intern("kk_list_is_empty")
            default:
                break
            }
        case "iterator":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_list_iterator")
            default:
                break
            }
        case "firstNotNullOf":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?, .array?:
                return interner.intern("__kk_iterable_firstNotNullOf")
            default:
                break
            }
        case "firstNotNullOfOrNull":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?, .array?:
                return interner.intern("__kk_iterable_firstNotNullOfOrNull")
            default:
                break
            }
        case "reduce":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_sequence_reduce")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_sequence_reduce")
                }
            }
        case "requireNoNulls":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("__kk_iterable_requireNoNulls")
            default:
                break
            }
        case "reduceRight":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_sequence_reduceRight")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_sequence_reduceRight")
                }
            }
        case "reduceIndexed":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_sequence_reduceIndexed")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_sequence_reduceIndexed")
                }
            }
        case "reduceRightIndexed":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_sequence_reduceRightIndexed")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_sequence_reduceRightIndexed")
                }
            }
        case "reduceRightOrNull":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_sequence_reduceRightOrNull")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_sequence_reduceRightOrNull")
                }
            }
        case "reduceRightIndexedOrNull":
            switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_sequence_reduceRightIndexedOrNull")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_sequence_reduceRightIndexedOrNull")
                }
            }
        default:
            break
        }

        return nil
    }

    func unresolvedMapMemberCallee(
        memberName: String,
        receiverType: TypeID,
        argumentCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema),
              knownNames.isMapLikeSymbol(symbol)
        else {
            return nil
        }
        switch memberName {
        case "count":
            return argumentCount == 0 ? interner.intern("kk_map_size") : nil
        case "putAll":
            guard knownNames.isMutableMapSymbol(symbol) else {
                return nil
            }
            return interner.intern("__kk_mutable_map_putAll")
        default:
            return nil
        }
    }

    func collectionIsNullOrEmptyRuntimeCallee(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch collectionKindWithSupertypes(of: symbol, sema: sema, knownNames: knownNames) {
        case .map?:
            return interner.intern("kk_map_is_empty")
        case .set?:
            return interner.intern("__kk_set_is_empty")
        case .array?:
            return interner.intern("kk_array_is_empty")
        case .list?, .collection?:
            return interner.intern("kk_list_is_empty")
        case .sequence?, nil:
            return nil
        }
    }
}
