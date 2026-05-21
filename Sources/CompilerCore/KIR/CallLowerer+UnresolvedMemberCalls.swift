// swiftlint:disable file_length
import Foundation

/// Name-based fallback resolution for unresolved synthetic and collection members.
extension CallLowerer {
    // swiftlint:disable cyclomatic_complexity
    func unresolvedSyntheticMemberCallee(
        memberName: String,
        receiverExpr: ExprID,
        receiverType: TypeID,
        argumentCount: Int,
        hasHOFLambdaArg: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if let rangeKind = MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ),
           let runtimeLinkName = MemberRuntimeDispatch.rangeRuntimeLinkName(for: MemberDispatchKey(
               receiverKind: rangeKind,
               memberName: memberName,
               arity: argumentCount,
               lambdaShape: hasHOFLambdaArg ? .hofLambda : .none
           ))
        {
            return interner.intern(runtimeLinkName)
        }
        if let collectionKind = MemberRuntimeDispatch.collectionReceiverKind(
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ),
           let runtimeLinkName = MemberRuntimeDispatch.collectionRuntimeLinkName(for: MemberDispatchKey(
               receiverKind: collectionKind,
               memberName: memberName,
               arity: argumentCount,
               lambdaShape: hasHOFLambdaArg ? .hofLambda : .none
           ))
        {
            return interner.intern(runtimeLinkName)
        }
        if memberName == "toString",
           argumentCount == 0,
           isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner)
        {
            return interner.intern("kk_string_builder_toString")
        }

        if memberName == "length",
           sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
        {
            return interner.intern("kk_string_length")
        }

        if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
            switch memberName {
            case "compareTo":
                return interner.intern("kk_string_compareTo_member")
            case "get":
                return interner.intern("kk_string_get")
            case "lines":
                return interner.intern("kk_string_lines")
            case "lineSequence":
                return interner.intern("kk_string_lineSequence")
            case "toRegex":
                return interner.intern("kk_string_toRegex")
            default:
                break
            }
        }

        if memberName == "binarySearch",
           let runtimeName = arrayBinarySearchRuntimeName(
               for: nonNullReceiverType,
               sema: sema,
               interner: interner
           )
        {
            if argumentCount == 5,
               isGenericArrayLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                return interner.intern("kk_array_binarySearch_compare")
            }
            return runtimeName
        }

        if isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "flatMapIndexed":
                return interner.intern("kk_list_flatMapIndexed")
            case "sorted":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_list_sorted_primitive")
                }
                return interner.intern("kk_list_sorted")
            case "sortedDescending":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_list_sortedDescending_primitive")
                }
                return interner.intern("kk_list_sortedDescending")
            case "sortedBy":
                return interner.intern("kk_list_sortedBy")
            case "distinctBy":
                return interner.intern("kk_list_distinctBy")
            case "sortedByDescending":
                return interner.intern("kk_list_sortedByDescending")
            case "first":
                return interner.intern("kk_list_first")
            case "firstOrNull":
                return interner.intern("kk_list_firstOrNull")
            case "lastOrNull":
                return interner.intern("kk_list_lastOrNull")
            case "single":
                return interner.intern("kk_list_single")
            case "singleOrNull":
                return interner.intern("kk_list_singleOrNull")
            case "sortedWith":
                return interner.intern("kk_list_sortedWith")
            case "indexOf":
                return interner.intern("kk_list_indexOf")
            case "lastIndexOf":
                return interner.intern("kk_list_lastIndexOf")
            case "indexOfFirst":
                return interner.intern("kk_list_indexOfFirst")
            case "indexOfLast":
                return interner.intern("kk_list_indexOfLast")
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
            case "any":
                return interner.intern("kk_list_any")
            case "all":
                return interner.intern("kk_list_all")
            case "none":
                return interner.intern("kk_list_none")
            case "onEach":
                return interner.intern("kk_list_onEach")
            case "onEachIndexed":
                return interner.intern("kk_list_onEachIndexed")
            case "partition":
                return interner.intern("kk_list_partition")
            case "zipWithNext":
                return interner.intern(hasHOFLambdaArg
                    ? "kk_list_zipWithNextTransform"
                    : "kk_list_zipWithNext")
            case "getOrNull":
                return interner.intern("kk_list_getOrNull")
            case "elementAtOrNull":
                return interner.intern("kk_list_elementAtOrNull")
            case "elementAt":
                return interner.intern("kk_list_elementAt")
            case "elementAtOrElse":
                return interner.intern("kk_list_elementAtOrElse")
            case "getOrElse":
                return interner.intern("kk_list_getOrElse")
            case "subList":
                return interner.intern("kk_list_subList")
            case "toTypedArray":
                return interner.intern("kk_list_toTypedArray")
            case "containsAll":
                return interner.intern("kk_list_containsAll")
            case "binarySearch":
                if hasHOFLambdaArg && argumentCount == 2 {
                    return interner.intern("kk_list_binarySearch_compare")
                }
                if argumentCount > 2 {
                    return interner.intern("kk_list_binarySearch_comparator")
                }
                return interner.intern("kk_list_binarySearch")
            case "binarySearchBy":
                switch argumentCount {
                case 2:
                    return interner.intern("kk_list_binarySearchBy")
                case 3:
                    return interner.intern("kk_list_binarySearchBy_fromIndex")
                case 4:
                    return interner.intern("kk_list_binarySearchBy_range")
                default:
                    break
                }
            case "reduce":
                return interner.intern("kk_list_reduce")
            case "reduceIndexed":
                return interner.intern("kk_list_reduceIndexed")
            case "reduceIndexedOrNull":
                return interner.intern("kk_list_reduceIndexedOrNull")
            case "foldRight":
                return interner.intern("kk_list_foldRight")
            case "foldRightIndexed":
                return interner.intern("kk_list_foldRightIndexed")
            case "reduceRight":
                return interner.intern("kk_list_reduceRight")
            case "reduceRightIndexed":
                return interner.intern("kk_list_reduceRightIndexed")
            case "reduceRightIndexedOrNull":
                return interner.intern("kk_list_reduceRightIndexedOrNull")
            case "reduceRightOrNull":
                return interner.intern("kk_list_reduceRightOrNull")
            case "runningFold":
                return interner.intern("kk_list_runningFold")
            case "runningReduce":
                return interner.intern("kk_list_runningReduce")
            case "scan":
                return interner.intern("kk_list_scan")
            case "runningFoldIndexed":
                return interner.intern("kk_list_runningFoldIndexed")
            case "runningReduceIndexed":
                return interner.intern("kk_list_runningReduceIndexed")
            case "scanIndexed":
                return interner.intern("kk_list_scanIndexed")
            default:
                break
            }
        }

        if isMutableSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "addAll":
                return interner.intern("kk_mutable_set_addAll")
            case "removeAll":
                return interner.intern("kk_mutable_set_removeAll")
            case "retainAll":
                return interner.intern("kk_mutable_set_retainAll")
            default:
                break
            }
        }

        if isMutableListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "sort":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_mutable_list_sort_primitive")
                }
                return interner.intern("kk_mutable_list_sort")
            case "sortWith":
                return interner.intern("kk_mutable_list_sortWith")
            case "sortBy":
                return interner.intern("kk_mutable_list_sortBy")
            case "sortByDescending":
                return interner.intern("kk_mutable_list_sortByDescending")
            case "sortDescending":
                if collectionElementPrimitiveCompareKind(of: nonNullReceiverType, sema: sema) != nil {
                    return interner.intern("kk_mutable_list_sortDescending_primitive")
                }
                return interner.intern("kk_mutable_list_sortDescending")
            case "add" where argumentCount == 1:
                return interner.intern("kk_mutable_list_add")
            case "addAll":
                return interner.intern("kk_mutable_list_addAll")
            case "removeAll":
                return interner.intern("kk_mutable_list_removeAll")
            case "retainAll":
                return interner.intern("kk_mutable_list_retainAll")
            case "fill":
                return interner.intern("kk_mutable_list_fill")
            case "replaceAll":
                return interner.intern("kk_mutable_list_replaceAll")
            case "removeIf":
                return interner.intern("kk_mutable_list_removeIf")
            case "removeFirst":
                return interner.intern("kk_mutable_list_removeFirst")
            case "removeFirstOrNull":
                return interner.intern("kk_mutable_list_removeFirstOrNull")
            case "removeLast":
                return interner.intern("kk_mutable_list_removeLast")
            case "removeLastOrNull":
                return interner.intern("kk_mutable_list_removeLastOrNull")
            default:
                break
            }
        }

        if isArrayDequeLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "addFirst":
                return interner.intern("kk_arraydeque_addFirst")
            case "addLast":
                return interner.intern("kk_arraydeque_addLast")
            case "removeFirst":
                return interner.intern("kk_arraydeque_removeFirst")
            case "removeLast":
                return interner.intern("kk_arraydeque_removeLast")
            case "first":
                return interner.intern("kk_arraydeque_first")
            case "last":
                return interner.intern("kk_arraydeque_last")
            case "size":
                return interner.intern("kk_arraydeque_size")
            case "isEmpty":
                return interner.intern("kk_arraydeque_isEmpty")
            case "toString":
                return interner.intern("kk_arraydeque_toString")
            default:
                break
            }
        }

        if isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "get":
                return interner.intern("kk_array_get")
            case "map":
                return interner.intern("kk_array_map")
            case "filter":
                return interner.intern("kk_array_filter")
            case "toList":
                return interner.intern("kk_array_toList")
            case "toMutableList":
                return interner.intern("kk_array_toMutableList")
            case "toTypedArray":
                return interner.intern("kk_array_copyOf")
            case "forEach":
                return interner.intern("kk_array_forEach")
            case "any":
                return interner.intern("kk_array_any")
            case "all":
                return interner.intern("kk_array_all")
            case "none":
                return interner.intern("kk_array_none")
            case "count":
                return interner.intern("kk_array_count")
            case "copyOf":
                switch argumentCount {
                case 0:
                    return interner.intern("kk_array_copyOf")
                case 1:
                    return interner.intern("kk_array_copyOf_newSize")
                case 2:
                    return interner.intern("kk_array_copyOf_newSize_init")
                default:
                    break
                }
            case "fill":
                return interner.intern("kk_array_fill")
            case "binarySearch":
                return arrayBinarySearchRuntimeName(
                    for: nonNullReceiverType,
                    sema: sema,
                    interner: interner
                )
            case "sortedArrayWith":
                return interner.intern("kk_array_sortedArrayWith")
            default:
                break
            }
        }

        // Set receivers: sorted/toList/contains route to set-specific runtime
        if isSetLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "sorted":
                return interner.intern("kk_set_sorted")
            case "sortedDescending":
                return interner.intern("kk_set_sortedDescending")
            case "toList":
                return interner.intern("kk_set_toList")
            case "toTypedArray":
                return interner.intern("kk_collection_toTypedArray")
            case "contains":
                return interner.intern("kk_set_contains")
            case "containsAll":
                return interner.intern("kk_set_containsAll")
            case "first":
                return interner.intern("kk_set_first")
            case "firstOrNull":
                return interner.intern("kk_set_firstOrNull")
            case "last":
                return interner.intern("kk_set_last")
            case "lastOrNull":
                return interner.intern("kk_set_lastOrNull")
            case "singleOrNull":
                return interner.intern("kk_set_singleOrNull")
            case "any":
                return interner.intern("kk_set_any")
            case "all":
                return interner.intern("kk_set_all")
            case "none":
                return interner.intern("kk_set_none")
            default:
                break
            }
        }

        if memberName == "flatMapIndexed",
           isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            return interner.intern("kk_list_flatMapIndexed")
        }

        switch memberName {
        case "sorted":
            return interner.intern("kk_list_sorted")
        case "sortedDescending":
            return interner.intern("kk_list_sortedDescending")
        case "sortedBy":
            return interner.intern("kk_list_sortedBy")
        case "distinctBy":
            return interner.intern("kk_list_distinctBy")
        case "sortedByDescending":
            return interner.intern("kk_list_sortedByDescending")
        case "partition":
            return interner.intern("kk_list_partition")
        case "zipWithNext":
            return interner.intern(hasHOFLambdaArg
                ? "kk_list_zipWithNextTransform"
                : "kk_list_zipWithNext")
        case "indexOf":
            return interner.intern("kk_list_indexOf")
        case "lastIndexOf":
            return interner.intern("kk_list_lastIndexOf")
        case "indexOfFirst":
            return interner.intern("kk_list_indexOfFirst")
        case "indexOfLast":
            return interner.intern("kk_list_indexOfLast")
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
        case "any":
            return interner.intern("kk_list_any")
        case "all":
            return interner.intern("kk_list_all")
        case "none":
            return interner.intern("kk_list_none")
        case "onEach":
            return interner.intern("kk_list_onEach")
        case "onEachIndexed":
            return interner.intern("kk_list_onEachIndexed")
        case "firstOrNull":
            return interner.intern("kk_list_firstOrNull")
        case "lastOrNull":
            return interner.intern("kk_list_lastOrNull")
        case "single":
            return interner.intern("kk_list_single")
        case "singleOrNull":
            return interner.intern("kk_list_singleOrNull")
        case "sortedWith":
            return interner.intern("kk_list_sortedWith")
        case "getOrNull":
            return interner.intern("kk_list_getOrNull")
        case "elementAtOrNull":
            return interner.intern("kk_list_elementAtOrNull")
        case "elementAt":
            return interner.intern("kk_list_elementAt")
        case "elementAtOrElse":
            return interner.intern("kk_list_elementAtOrElse")
        case "getOrElse":
            return interner.intern("kk_list_getOrElse")
        case "containsAll":
            return interner.intern("kk_list_containsAll")
        case "binarySearch":
            if argumentCount == 5,
               isConcreteArrayLikeType(nonNullReceiverType, sema: sema, interner: interner)
            {
                return interner.intern("kk_array_binarySearch_compare")
            }
            if hasHOFLambdaArg && argumentCount == 2 {
                return interner.intern("kk_list_binarySearch_compare")
            }
            if argumentCount > 2 {
                return interner.intern("kk_list_binarySearch_comparator")
            }
            return interner.intern("kk_list_binarySearch")
        case "groupingBy" where isConcreteListLikeType(nonNullReceiverType, sema: sema, interner: interner)
            || isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
            || sema.bindings.isCollectionExpr(receiverExpr):
            return interner.intern("kk_list_groupingBy")
        default:
            break
        }

        if isGroupingLikeType(nonNullReceiverType, sema: sema, interner: interner) {
            switch memberName {
            case "eachCount":
                return interner.intern("kk_grouping_eachCount")
            case "eachCountTo":
                return interner.intern("kk_grouping_eachCountTo")
            case "aggregate":
                return interner.intern("kk_grouping_aggregate")
            case "aggregateTo":
                return interner.intern("kk_grouping_aggregateTo")
            case "fold":
                return interner.intern(argumentCount >= 4
                    ? "kk_grouping_fold_initialValueSelector"
                    : "kk_grouping_fold")
            case "foldTo":
                return interner.intern(hasHOFLambdaArg
                    ? "kk_grouping_foldTo_selector"
                    : "kk_grouping_foldTo")
            case "reduce":
                return interner.intern("kk_grouping_reduce")
            case "reduceTo":
                return interner.intern("kk_grouping_reduceTo")
            default:
                break
            }
        }

        let useSequenceRuntimeForCollectionFallback = isSequenceLikeType(nonNullReceiverType, sema: sema, interner: interner)
        let useIterableRuntimeForCollectionFallback = (sema.bindings.isCollectionExpr(receiverExpr)
            || isIterableOrCollectionInterfaceType(nonNullReceiverType, sema: sema, interner: interner))
            && !isConcreteCollectionLikeType(nonNullReceiverType, sema: sema, interner: interner)
        if useSequenceRuntimeForCollectionFallback || useIterableRuntimeForCollectionFallback {
            let internedMemberName = interner.intern(memberName)
            let mapName = interner.intern("map")
            let filterName = interner.intern("filter")
            let takeName = interner.intern("take")
            let toListName = interner.intern("toList")
            let forEachName = interner.intern("forEach")
            let flatMapName = interner.intern("flatMap")
            let flatMapIndexedName = interner.intern("flatMapIndexed")
            let dropName = interner.intern("drop")
            let distinctName = interner.intern("distinct")
            let zipName = interner.intern("zip")
            let takeWhileName = interner.intern("takeWhile")
            let takeLastWhileName = interner.intern("takeLastWhile")
            let dropWhileName = interner.intern("dropWhile")
            let sortedName = interner.intern("sorted")
            let sortedByName = interner.intern("sortedBy")
            let sortedDescendingName = interner.intern("sortedDescending")
            let joinToName = interner.intern("joinTo")
            let joinToStringName = interner.intern("joinToString")
            let sumOfName = interner.intern("sumOf")
            let sumByName = interner.intern("sumBy")
            let sumByDoubleName = interner.intern("sumByDouble")
            let firstNotNullOfName = interner.intern("firstNotNullOf")
            let firstNotNullOfOrNullName = interner.intern("firstNotNullOfOrNull")
            let associateName = interner.intern("associate")
            let associateByName = interner.intern("associateBy")
            let firstName = interner.intern("first")
            let firstOrNullName = interner.intern("firstOrNull")
            let lastName = interner.intern("last")
            let countName = interner.intern("count")
            switch internedMemberName {
            case mapName:
                return interner.intern("kk_sequence_map")
            case filterName:
                return interner.intern("kk_sequence_filter")
            case takeName:
                return interner.intern("kk_sequence_take")
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
            case dropName:
                return interner.intern("kk_sequence_drop")
            case distinctName:
                return interner.intern("kk_sequence_distinct")
            case zipName:
                return interner.intern("kk_sequence_zip")
            case takeWhileName:
                return interner.intern("kk_sequence_takeWhile")
            case takeLastWhileName:
                return interner.intern("kk_sequence_takeLastWhile")
            case dropWhileName:
                return interner.intern("kk_sequence_dropWhile")
            case sortedName:
                return interner.intern("kk_sequence_sorted")
            case sortedByName:
                return interner.intern("kk_sequence_sortedBy")
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
            case joinToName:
                return interner.intern("kk_sequence_joinTo")
            case joinToStringName:
                return interner.intern("kk_sequence_joinToString")
            case sumOfName:
                return interner.intern("kk_sequence_sumOf")
            case sumByName:
                return interner.intern("kk_sequence_sumBy")
            case sumByDoubleName:
                return interner.intern("kk_sequence_sumByDouble")
            case firstNotNullOfName:
                return interner.intern("kk_sequence_firstNotNullOf")
            case firstNotNullOfOrNullName:
                return interner.intern("kk_sequence_firstNotNullOfOrNull")
            case associateName:
                return interner.intern("kk_sequence_associate")
            case associateByName:
                return interner.intern("kk_sequence_associateBy")
            case interner.intern("associateTo"):
                return interner.intern("kk_sequence_associateTo")
            case interner.intern("associateByTo"):
                return interner.intern("kk_sequence_associateByTo")
            case interner.intern("associateWith"):
                return interner.intern("kk_sequence_associateWith")
            case interner.intern("associateWithTo"):
                return interner.intern("kk_sequence_associateWithTo")
            case interner.intern("groupByTo"):
                return interner.intern("kk_sequence_groupByTo")
            case interner.intern("flatMapIndexedTo"):
                return interner.intern("kk_sequence_flatMapIndexedTo")
            case interner.intern("flatMapTo"):
                return interner.intern("kk_sequence_flatMapTo")
            case interner.intern("contains"):
                return interner.intern("kk_sequence_contains")
            case interner.intern("indexOf"):
                return interner.intern("kk_sequence_indexOf")
            case interner.intern("elementAt"):
                return interner.intern("kk_sequence_elementAt")
            case interner.intern("elementAtOrNull"):
                return interner.intern("kk_sequence_elementAtOrNull")
            case interner.intern("findLast"):
                return interner.intern("kk_sequence_findLast")
            case interner.intern("find"):
                return interner.intern("kk_sequence_find")
            case interner.intern("singleOrNull"):
                return interner.intern("kk_sequence_singleOrNull")
            case interner.intern("any"):
                return interner.intern(useIterableRuntimeForCollectionFallback ? "kk_iterable_any" : "kk_sequence_any")
            case interner.intern("all"):
                return interner.intern(useIterableRuntimeForCollectionFallback ? "kk_iterable_all" : "kk_sequence_all")
            case interner.intern("none"):
                return interner.intern("kk_sequence_none")
            case interner.intern("mapNotNull"):
                return interner.intern("kk_sequence_mapNotNull")
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
            case interner.intern("asIterable"):
                return interner.intern("kk_sequence_asIterable")
            case interner.intern("mapIndexed"):
                return interner.intern("kk_sequence_mapIndexed")
            case interner.intern("filterIndexed"):
                return interner.intern("kk_sequence_filterIndexed")
            case interner.intern("flatMapIndexed"):
                return interner.intern("kk_sequence_flatMapIndexed")
            case interner.intern("withIndex"):
                return interner.intern("kk_sequence_withIndex")
            case interner.intern("chunked"):
                return interner.intern(hasHOFLambdaArg
                    ? "kk_sequence_chunked_transform"
                    : "kk_sequence_chunked")
            case interner.intern("windowed"):
                return interner.intern("kk_sequence_windowed")
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
            case interner.intern("ifEmpty"):
                return interner.intern("kk_sequence_ifEmpty")
            case firstName:
                return interner.intern("kk_sequence_first")
            case firstOrNullName:
                return interner.intern("kk_sequence_firstOrNull")
            case interner.intern("randomOrNull"):
                return interner.intern("kk_sequence_randomOrNull")
            case lastName:
                return interner.intern(useIterableRuntimeForCollectionFallback ? "kk_iterable_last" : "kk_sequence_last")
            case interner.intern("lastOrNull"):
                return interner.intern("kk_sequence_lastOrNull")
            case countName:
                return interner.intern("kk_sequence_count")
            case interner.intern("sum"):
                return interner.intern("kk_sequence_sum")
            case interner.intern("average"):
                return interner.intern("kk_sequence_average")
            case interner.intern("toCollection"):
                return interner.intern("kk_sequence_toCollection")
            case interner.intern("toMutableList"):
                return toMutableListRuntimeCalleeForSequenceOrIterableFallback(
                    chosenCallee: nil,
                    useIterableFallback: useIterableRuntimeForCollectionFallback,
                    sema: sema,
                    interner: interner
                )
            case interner.intern("toMutableSet"):
                return interner.intern(useIterableRuntimeForCollectionFallback
                    ? "kk_iterable_toMutableSet"
                    : "kk_sequence_toMutableSet")
            case interner.intern("toSortedSet"):
                return interner.intern("kk_sequence_toSortedSet")
            case interner.intern("toHashSet"):
                return interner.intern("kk_sequence_toHashSet")
            case interner.intern("partition"):
                return interner.intern("kk_sequence_partition")
            case interner.intern("maxBy"):
                return interner.intern("kk_sequence_maxBy")
            case interner.intern("minByOrNull"):
                return interner.intern("kk_sequence_minByOrNull")
            case interner.intern("maxByOrNull"):
                return interner.intern("kk_sequence_maxByOrNull")
            case interner.intern("maxWithOrNull"):
                return interner.intern("kk_sequence_maxWithOrNull")
            case interner.intern("minOf"):
                return interner.intern("kk_sequence_minOf")
            case interner.intern("minOfOrNull"):
                return interner.intern("kk_sequence_minOfOrNull")
            case interner.intern("maxOfOrNull"):
                return interner.intern("kk_sequence_maxOfOrNull")
            case interner.intern("maxOf"):
                return interner.intern("kk_sequence_maxOf")
            case interner.intern("unzip"):
                return interner.intern("kk_sequence_unzip")
            case interner.intern("foldIndexed"):
                return interner.intern("kk_sequence_foldIndexed")
            case interner.intern("runningFoldIndexed"):
                return interner.intern("kk_sequence_runningFoldIndexed")
            case interner.intern("scanIndexed"):
                return interner.intern("kk_sequence_scanIndexed")
            case interner.intern("reduceIndexed"):
                return interner.intern("kk_sequence_reduceIndexed")
            case interner.intern("reduceIndexedOrNull"):
                return interner.intern("kk_sequence_reduceIndexedOrNull")
            case interner.intern("reduceRightIndexed"):
                return interner.intern(useIterableRuntimeForCollectionFallback
                    ? "kk_list_reduceRightIndexed"
                    : "kk_sequence_reduceRightIndexed")
            case interner.intern("runningReduceIndexed"):
                return interner.intern("kk_sequence_runningReduceIndexed")
            default:
                break
            }
        }

        return nil
    }

    // swiftlint:enable cyclomatic_complexity

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
              || memberName == "reduceRightIndexed",
              case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch memberName {
        case "size":
            switch knownNames.collectionKind(of: symbol) {
            case .map?:
                return interner.intern("kk_map_size")
            case .set?:
                return interner.intern("kk_set_size")
            case .array?:
                return interner.intern("kk_array_size")
            case .list?, .collection?:
                return interner.intern("kk_list_size")
            default:
                break
            }
        case "isEmpty":
            switch knownNames.collectionKind(of: symbol) {
            case .map?:
                return interner.intern("kk_map_is_empty")
            case .set?:
                return interner.intern("kk_set_is_empty")
            case .array?:
                return interner.intern("kk_array_is_empty")
            case .list?, .collection?:
                return interner.intern("kk_list_is_empty")
            default:
                break
            }
        case "isNotEmpty":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .collection?:
                return interner.intern("kk_list_is_not_empty")
            default:
                break
            }
        case "iterator":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_list_iterator")
            default:
                break
            }
        case "firstNotNullOf":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_iterable_firstNotNullOf")
            default:
                break
            }
        case "firstNotNullOfOrNull":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_iterable_firstNotNullOfOrNull")
            default:
                break
            }
        case "reduce":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_list_reduce")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_list_reduce")
                }
            }
        case "requireNoNulls":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_iterable_requireNoNulls")
            default:
                break
            }
        case "reduceRight":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_list_reduceRight")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_list_reduceRight")
                }
            }
        case "reduceIndexed":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_list_reduceIndexed")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_list_reduceIndexed")
                }
            }
        case "reduceRightIndexed":
            switch knownNames.collectionKind(of: symbol) {
            case .list?, .set?, .collection?:
                return interner.intern("kk_list_reduceRightIndexed")
            default:
                if symbol.name == interner.intern("Iterable")
                    || symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                {
                    return interner.intern("kk_list_reduceRightIndexed")
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
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              knownNames.isMapLikeSymbol(symbol)
        else {
            return nil
        }
        switch memberName {
        case "count":
            return interner.intern(argumentCount == 0 ? "kk_map_size" : "kk_map_count")
        case "any":
            return interner.intern("kk_map_any")
        case "all":
            return interner.intern("kk_map_all")
        case "none":
            return interner.intern("kk_map_none")
        case "getValue":
            return interner.intern("kk_map_getValue")
        case "getOrDefault":
            return interner.intern("kk_map_getOrDefault")
        case "getOrElse":
            return interner.intern("kk_map_getOrElse")
        case "maxByOrNull":
            return interner.intern("kk_map_maxByOrNull")
        case "minByOrNull":
            return interner.intern("kk_map_minByOrNull")
        case "plus":
            return interner.intern("kk_map_plus")
        case "minus":
            return interner.intern("kk_map_minus")
        case "filterNot":
            return interner.intern("kk_map_filterNot")
        case "filterKeys":
            return interner.intern("kk_map_filterKeys")
        case "filterValues":
            return interner.intern("kk_map_filterValues")
        case "mapNotNull":
            return interner.intern("kk_map_mapNotNull")
        case "mapKeysTo":
            return interner.intern("kk_map_mapKeysTo")
        case "mapValuesTo":
            return interner.intern("kk_map_mapValuesTo")
        case "getOrPut":
            guard knownNames.isMutableMapSymbol(symbol) else {
                return nil
            }
            return interner.intern("kk_mutable_map_getOrPut")
        case "putAll":
            guard knownNames.isMutableMapSymbol(symbol) else {
                return nil
            }
            return interner.intern("kk_mutable_map_putAll")
        default:
            return nil
        }
    }

    func collectionIsNullOrEmptyRuntimeCallee(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch knownNames.collectionKind(of: symbol) {
        case .map?:
            return interner.intern("kk_map_is_empty")
        case .set?:
            return interner.intern("kk_set_is_empty")
        case .array?:
            return interner.intern("kk_array_is_empty")
        case .list?, .collection?:
            return interner.intern("kk_list_is_empty")
        case .sequence?, nil:
            return nil
        }
    }
}
