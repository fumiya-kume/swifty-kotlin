import Foundation

// swiftformat:disable redundantMemberwiseInit
struct CollectionLiteralLookupTables {
    // Source-level callee names
    let listOfName: InternedString
    let mutableListOfName: InternedString
    let emptyListName: InternedString
    let listOfNotNullName: InternedString
    let arrayOfName: InternedString
    let intArrayOfName: InternedString
    let longArrayOfName: InternedString
    let doubleArrayOfName: InternedString
    let booleanArrayOfName: InternedString
    let charArrayOfName: InternedString
    let mapOfName: InternedString
    let mutableMapOfName: InternedString
    let emptyMapName: InternedString
    let setOfName: InternedString
    let mutableSetOfName: InternedString
    let emptySetName: InternedString

    // Runtime ABI names
    let kkListOfName: InternedString
    let kkListSizeName: InternedString
    let kkListGetName: InternedString
    let kkListContainsName: InternedString
    let kkListIsEmptyName: InternedString
    let kkListIteratorName: InternedString
    let kkListIteratorHasNextName: InternedString
    let kkListIteratorNextName: InternedString
    let kkListToStringName: InternedString
    let kkSetOfName: InternedString
    let kkSetSizeName: InternedString
    let kkSetContainsName: InternedString
    let kkSetIsEmptyName: InternedString
    let kkSetToStringName: InternedString
    let kkStringSplitName: InternedString

    // Higher-order collection function ABI names (FUNC-003)
    let kkListMapName: InternedString
    let kkListFilterName: InternedString
    let kkListMapNotNullName: InternedString
    let kkListFilterNotNullName: InternedString
    let kkListForEachName: InternedString
    let kkListFlatMapName: InternedString
    let kkListAnyName: InternedString
    let kkListNoneName: InternedString
    let kkListAllName: InternedString

    // Additional higher-order collection function ABI names (STDLIB-005)
    let kkListFoldName: InternedString
    let kkListReduceName: InternedString
    let kkListGroupByName: InternedString
    let kkListSortedByName: InternedString
    let kkListAssociateByName: InternedString
    let kkListAssociateWithName: InternedString
    let kkListAssociateName: InternedString
    let kkListCountName: InternedString
    let kkListFirstName: InternedString
    let kkListLastName: InternedString
    let kkListFindName: InternedString
    let kkListZipName: InternedString
    let kkListUnzipName: InternedString
    let kkListWithIndexName: InternedString
    let kkListForEachIndexedName: InternedString
    let kkListMapIndexedName: InternedString
    let kkListSumOfName: InternedString
    let kkListMaxOrNullName: InternedString
    let kkListMinOrNullName: InternedString
    let kkListTakeName: InternedString
    let kkListDropName: InternedString
    let kkListReversedName: InternedString
    let kkListSortedName: InternedString
    let kkListDistinctName: InternedString
    let kkListShuffledName: InternedString
    let kkListRandomName: InternedString
    let kkListRandomOrNullName: InternedString
    let kkListFlattenName: InternedString
    let kkListIndexOfName: InternedString
    let kkListLastIndexOfName: InternedString
    let kkListIndexOfFirstName: InternedString
    let kkListIndexOfLastName: InternedString
    let kkListChunkedName: InternedString
    let kkListWindowedName: InternedString
    let kkListSortedDescendingName: InternedString
    let kkListSortedByDescendingName: InternedString
    let kkListSortedWithName: InternedString
    let kkListPartitionName: InternedString

    // Comparator ABI names (STDLIB-175, STDLIB-177)
    let kkComparatorFromSelectorName: InternedString
    let kkComparatorFromSelectorDescendingName: InternedString
    let kkComparatorFromSelectorTrampolineName: InternedString
    let kkComparatorFromSelectorDescendingTrampolineName: InternedString
    let kkComparatorNaturalOrderName: InternedString
    let kkComparatorReverseOrderName: InternedString
    let kkComparatorNaturalOrderTrampolineName: InternedString
    let kkComparatorReverseOrderTrampolineName: InternedString

    // Sequence ABI names (STDLIB-003)
    let kkSequenceFromListName: InternedString
    let kkSequenceMapName: InternedString
    let kkSequenceFilterName: InternedString
    let kkSequenceTakeName: InternedString
    let kkSequenceToListName: InternedString
    let kkSequenceBuilderBuildName: InternedString
    let kkSequenceBuilderYieldName: InternedString

    // Sequence ABI names (STDLIB-095/096/097)
    let kkSequenceOfName: InternedString
    let kkSequenceGenerateName: InternedString
    let kkSequenceForEachName: InternedString
    let kkSequenceFlatMapName: InternedString
    let kkSequenceDropName: InternedString
    let kkSequenceDistinctName: InternedString
    let kkSequenceZipName: InternedString

    let kkMapOfName: InternedString
    let kkMapSizeName: InternedString
    let kkMapGetName: InternedString
    let kkMapContainsKeyName: InternedString
    let kkMapIsEmptyName: InternedString
    let kkMapForEachName: InternedString
    let kkMapMapName: InternedString
    let kkMapFilterName: InternedString
    let kkMapMapValuesName: InternedString
    let kkMapMapKeysName: InternedString
    let kkMapToListName: InternedString
    let kkMapToStringName: InternedString
    let kkMapIteratorName: InternedString
    let kkMapIteratorHasNextName: InternedString
    let kkMapIteratorNextName: InternedString

    let kkArraySizeName: InternedString
    let kkArrayNewName: InternedString
    let kkArraySetName: InternedString

    // Array conversion / HOF / utility ABI names (STDLIB-087/088/089)
    let kkArrayToListName: InternedString
    let kkArrayToMutableListName: InternedString
    let kkListToTypedArrayName: InternedString
    let kkArrayMapName: InternedString
    let kkArrayFilterName: InternedString
    let kkArrayForEachName: InternedString
    let kkArrayAnyName: InternedString
    let kkArrayNoneName: InternedString
    let kkArrayCopyOfName: InternedString
    let kkArrayCopyOfRangeName: InternedString
    let kkArrayFillName: InternedString

    // Range iterator names (emitted by ForLoweringPass)
    let kkRangeIteratorName: InternedString
    let kkRangeHasNextName: InternedString
    let kkRangeNextName: InternedString

    // Range factory / member ABI names (STDLIB-090/091/092/093)
    let kkOpRangeToName: InternedString
    let kkOpRangeUntilName: InternedString
    let kkOpDownToName: InternedString
    let kkOpStepName: InternedString
    let kkRangeFirstName: InternedString
    let kkRangeLastName: InternedString
    let kkRangeCountName: InternedString
    let kkRangeToListName: InternedString
    let kkRangeForEachName: InternedString
    let kkRangeMapName: InternedString
    let kkRangeReversedName: InternedString
    let kkOpContainsName: InternedString

    // Member names
    let sizeName: InternedString
    let getName: InternedString
    let containsName: InternedString
    let containsKeyName: InternedString
    let isEmptyName: InternedString
    let countName: InternedString
    let addName: InternedString
    let removeName: InternedString

    // Higher-order collection member names (FUNC-003)
    let mapName: InternedString
    let filterName: InternedString
    let mapNotNullName: InternedString
    let filterNotNullName: InternedString
    let forEachName: InternedString
    let flatMapName: InternedString
    let anyName: InternedString
    let noneName: InternedString
    let allName: InternedString

    // Additional higher-order collection member names (STDLIB-005)
    let foldName: InternedString
    let reduceName: InternedString
    let groupByName: InternedString
    let sortedByName: InternedString
    let findName: InternedString
    let associateByName: InternedString
    let associateWithName: InternedString
    let associateName: InternedString
    let mapValuesName: InternedString
    let mapKeysName: InternedString
    let zipName: InternedString
    let unzipName: InternedString
    let withIndexName: InternedString
    let forEachIndexedName: InternedString
    let mapIndexedName: InternedString
    let sumOfName: InternedString
    let maxOrNullName: InternedString
    let minOrNullName: InternedString
    let dropName: InternedString
    let reversedName: InternedString
    let sortedName: InternedString
    let distinctName: InternedString
    let shuffledName: InternedString
    let flattenName: InternedString
    let firstName: InternedString
    let lastName: InternedString
    let indexOfName: InternedString
    let lastIndexOfName: InternedString
    let indexOfFirstName: InternedString
    let indexOfLastName: InternedString
    let chunkedName: InternedString
    let windowedName: InternedString
    let sortedDescendingName: InternedString
    let sortedByDescendingName: InternedString
    let sortedWithName: InternedString
    let partitionName: InternedString

    // Array member names (STDLIB-087/088/089)
    let toMutableListName: InternedString
    let toTypedArrayName: InternedString
    let copyOfName: InternedString
    let copyOfRangeName: InternedString
    let fillName: InternedString

    // Sequence member names (STDLIB-003)
    let asSequenceName: InternedString
    let toListName: InternedString
    let takeName: InternedString
    let sequenceName: InternedString
    let yieldName: InternedString

    // Sequence factory names (STDLIB-097)
    let sequenceOfName: InternedString
    let generateSequenceName: InternedString

    // println support
    let printlnName: InternedString
    let kkPrintlnAnyName: InternedString
    let kkAnyToStringName: InternedString

    // Pair / `to` infix (FUNC-002)
    let toName: InternedString
    let kkPairNewName: InternedString
    let kkPairFirstName: InternedString
    let kkPairSecondName: InternedString

    // Triple (STDLIB-120)
    let tripleName: InternedString
    let kkTripleNewName: InternedString

    // Builder DSL names (STDLIB-002)
    let buildStringName: InternedString
    let buildListName: InternedString
    let buildMapName: InternedString
    let kkBuildStringName: InternedString
    let kkBuildListName: InternedString
    let kkBuildListWithCapacityName: InternedString
    let kkBuildMapName: InternedString

    // Builder member function names (STDLIB-002)
    let appendName: InternedString
    let putName: InternedString
    let kkStringBuilderAppendName: InternedString
    let kkBuilderListAddName: InternedString
    let kkBuilderMapPutName: InternedString
    let kkMutableSetAddName: InternedString
    let kkMutableSetRemoveName: InternedString
    let kkMutableMapPutName: InternedString

    // Common lookup sets
    let listFactoryNames: Set<InternedString>
    let setFactoryNames: Set<InternedString>
    let mapFactoryNames: Set<InternedString>
    let arrayOfFactoryNames: Set<InternedString>
    let builderDSLNames: Set<InternedString>

    init(interner: StringInterner) {
        listOfName = interner.intern("listOf")
        mutableListOfName = interner.intern("mutableListOf")
        emptyListName = interner.intern("emptyList")
        listOfNotNullName = interner.intern("listOfNotNull")
        arrayOfName = interner.intern("arrayOf")
        intArrayOfName = interner.intern("intArrayOf")
        longArrayOfName = interner.intern("longArrayOf")
        doubleArrayOfName = interner.intern("doubleArrayOf")
        booleanArrayOfName = interner.intern("booleanArrayOf")
        charArrayOfName = interner.intern("charArrayOf")
        mapOfName = interner.intern("mapOf")
        mutableMapOfName = interner.intern("mutableMapOf")
        emptyMapName = interner.intern("emptyMap")
        setOfName = interner.intern("setOf")
        mutableSetOfName = interner.intern("mutableSetOf")
        emptySetName = interner.intern("emptySet")

        kkListOfName = interner.intern("kk_list_of")
        kkListSizeName = interner.intern("kk_list_size")
        kkListGetName = interner.intern("kk_list_get")
        kkListContainsName = interner.intern("kk_list_contains")
        kkListIsEmptyName = interner.intern("kk_list_is_empty")
        kkListIteratorName = interner.intern("kk_list_iterator")
        kkListIteratorHasNextName = interner.intern("kk_list_iterator_hasNext")
        kkListIteratorNextName = interner.intern("kk_list_iterator_next")
        kkListToStringName = interner.intern("kk_list_to_string")
        kkSetOfName = interner.intern("kk_set_of")
        kkSetSizeName = interner.intern("kk_set_size")
        kkSetContainsName = interner.intern("kk_set_contains")
        kkSetIsEmptyName = interner.intern("kk_set_is_empty")
        kkSetToStringName = interner.intern("kk_set_to_string")
        kkStringSplitName = interner.intern("kk_string_split")

        kkListMapName = interner.intern("kk_list_map")
        kkListFilterName = interner.intern("kk_list_filter")
        kkListMapNotNullName = interner.intern("kk_list_mapNotNull")
        kkListFilterNotNullName = interner.intern("kk_list_filterNotNull")
        kkListForEachName = interner.intern("kk_list_forEach")
        kkListFlatMapName = interner.intern("kk_list_flatMap")
        kkListAnyName = interner.intern("kk_list_any")
        kkListNoneName = interner.intern("kk_list_none")
        kkListAllName = interner.intern("kk_list_all")

        kkListFoldName = interner.intern("kk_list_fold")
        kkListReduceName = interner.intern("kk_list_reduce")
        kkListGroupByName = interner.intern("kk_list_groupBy")
        kkListSortedByName = interner.intern("kk_list_sortedBy")
        kkListAssociateByName = interner.intern("kk_list_associateBy")
        kkListAssociateWithName = interner.intern("kk_list_associateWith")
        kkListAssociateName = interner.intern("kk_list_associate")
        kkListCountName = interner.intern("kk_list_count")
        kkListFirstName = interner.intern("kk_list_first")
        kkListLastName = interner.intern("kk_list_last")
        kkListFindName = interner.intern("kk_list_find")
        kkListZipName = interner.intern("kk_list_zip")
        kkListUnzipName = interner.intern("kk_list_unzip")
        kkListWithIndexName = interner.intern("kk_list_withIndex")
        kkListForEachIndexedName = interner.intern("kk_list_forEachIndexed")
        kkListMapIndexedName = interner.intern("kk_list_mapIndexed")
        kkListSumOfName = interner.intern("kk_list_sumOf")
        kkListMaxOrNullName = interner.intern("kk_list_maxOrNull")
        kkListMinOrNullName = interner.intern("kk_list_minOrNull")
        kkListTakeName = interner.intern("kk_list_take")
        kkListDropName = interner.intern("kk_list_drop")
        kkListReversedName = interner.intern("kk_list_reversed")
        kkListSortedName = interner.intern("kk_list_sorted")
        kkListDistinctName = interner.intern("kk_list_distinct")
        kkListShuffledName = interner.intern("kk_list_shuffled")
        kkListRandomName = interner.intern("kk_list_random")
        kkListRandomOrNullName = interner.intern("kk_list_randomOrNull")
        kkListFlattenName = interner.intern("kk_list_flatten")
        kkListIndexOfName = interner.intern("kk_list_indexOf")
        kkListLastIndexOfName = interner.intern("kk_list_lastIndexOf")
        kkListIndexOfFirstName = interner.intern("kk_list_indexOfFirst")
        kkListIndexOfLastName = interner.intern("kk_list_indexOfLast")
        kkListChunkedName = interner.intern("kk_list_chunked")
        kkListWindowedName = interner.intern("kk_list_windowed")
        kkListSortedDescendingName = interner.intern("kk_list_sortedDescending")
        kkListSortedByDescendingName = interner.intern("kk_list_sortedByDescending")
        kkListSortedWithName = interner.intern("kk_list_sortedWith")
        kkListPartitionName = interner.intern("kk_list_partition")

        kkComparatorFromSelectorName = interner.intern("kk_comparator_from_selector")
        kkComparatorFromSelectorDescendingName = interner.intern("kk_comparator_from_selector_descending")
        kkComparatorFromSelectorTrampolineName = interner.intern("kk_comparator_from_selector_trampoline")
        kkComparatorFromSelectorDescendingTrampolineName = interner.intern("kk_comparator_from_selector_descending_trampoline")
        kkComparatorNaturalOrderName = interner.intern("kk_comparator_natural_order")
        kkComparatorReverseOrderName = interner.intern("kk_comparator_reverse_order")
        kkComparatorNaturalOrderTrampolineName = interner.intern("kk_comparator_natural_order_trampoline")
        kkComparatorReverseOrderTrampolineName = interner.intern("kk_comparator_reverse_order_trampoline")

        kkSequenceFromListName = interner.intern("kk_sequence_from_list")
        kkSequenceMapName = interner.intern("kk_sequence_map")
        kkSequenceFilterName = interner.intern("kk_sequence_filter")
        kkSequenceTakeName = interner.intern("kk_sequence_take")
        kkSequenceToListName = interner.intern("kk_sequence_to_list")
        kkSequenceBuilderBuildName = interner.intern("kk_sequence_builder_build")
        kkSequenceBuilderYieldName = interner.intern("kk_sequence_builder_yield")

        kkSequenceOfName = interner.intern("kk_sequence_of")
        kkSequenceGenerateName = interner.intern("kk_sequence_generate")
        kkSequenceForEachName = interner.intern("kk_sequence_forEach")
        kkSequenceFlatMapName = interner.intern("kk_sequence_flatMap")
        kkSequenceDropName = interner.intern("kk_sequence_drop")
        kkSequenceDistinctName = interner.intern("kk_sequence_distinct")
        kkSequenceZipName = interner.intern("kk_sequence_zip")

        kkMapOfName = interner.intern("kk_map_of")
        kkMapSizeName = interner.intern("kk_map_size")
        kkMapGetName = interner.intern("kk_map_get")
        kkMapContainsKeyName = interner.intern("kk_map_contains_key")
        kkMapIsEmptyName = interner.intern("kk_map_is_empty")
        kkMapForEachName = interner.intern("kk_map_forEach")
        kkMapMapName = interner.intern("kk_map_map")
        kkMapFilterName = interner.intern("kk_map_filter")
        kkMapMapValuesName = interner.intern("kk_map_mapValues")
        kkMapMapKeysName = interner.intern("kk_map_mapKeys")
        kkMapToListName = interner.intern("kk_map_toList")
        kkMapToStringName = interner.intern("kk_map_to_string")
        kkMapIteratorName = interner.intern("kk_map_iterator")
        kkMapIteratorHasNextName = interner.intern("kk_map_iterator_hasNext")
        kkMapIteratorNextName = interner.intern("kk_map_iterator_next")

        kkArraySizeName = interner.intern("kk_array_size")
        kkArrayNewName = interner.intern("kk_array_new")
        kkArraySetName = interner.intern("kk_array_set")

        kkArrayToListName = interner.intern("kk_array_toList")
        kkArrayToMutableListName = interner.intern("kk_array_toMutableList")
        kkListToTypedArrayName = interner.intern("kk_list_toTypedArray")
        kkArrayMapName = interner.intern("kk_array_map")
        kkArrayFilterName = interner.intern("kk_array_filter")
        kkArrayForEachName = interner.intern("kk_array_forEach")
        kkArrayAnyName = interner.intern("kk_array_any")
        kkArrayNoneName = interner.intern("kk_array_none")
        kkArrayCopyOfName = interner.intern("kk_array_copyOf")
        kkArrayCopyOfRangeName = interner.intern("kk_array_copyOfRange")
        kkArrayFillName = interner.intern("kk_array_fill")

        kkRangeIteratorName = interner.intern("kk_range_iterator")
        kkRangeHasNextName = interner.intern("kk_range_hasNext")
        kkRangeNextName = interner.intern("kk_range_next")

        kkOpRangeToName = interner.intern("kk_op_rangeTo")
        kkOpRangeUntilName = interner.intern("kk_op_rangeUntil")
        kkOpDownToName = interner.intern("kk_op_downTo")
        kkOpStepName = interner.intern("kk_op_step")
        kkRangeFirstName = interner.intern("kk_range_first")
        kkRangeLastName = interner.intern("kk_range_last")
        kkRangeCountName = interner.intern("kk_range_count")
        kkRangeToListName = interner.intern("kk_range_toList")
        kkRangeForEachName = interner.intern("kk_range_forEach")
        kkRangeMapName = interner.intern("kk_range_map")
        kkRangeReversedName = interner.intern("kk_range_reversed")
        kkOpContainsName = interner.intern("kk_op_contains")

        sizeName = interner.intern("size")
        getName = interner.intern("get")
        containsName = interner.intern("contains")
        containsKeyName = interner.intern("containsKey")
        isEmptyName = interner.intern("isEmpty")
        countName = interner.intern("count")
        addName = interner.intern("add")
        removeName = interner.intern("remove")

        mapName = interner.intern("map")
        filterName = interner.intern("filter")
        mapNotNullName = interner.intern("mapNotNull")
        filterNotNullName = interner.intern("filterNotNull")
        forEachName = interner.intern("forEach")
        flatMapName = interner.intern("flatMap")
        anyName = interner.intern("any")
        noneName = interner.intern("none")
        allName = interner.intern("all")

        foldName = interner.intern("fold")
        reduceName = interner.intern("reduce")
        groupByName = interner.intern("groupBy")
        sortedByName = interner.intern("sortedBy")
        findName = interner.intern("find")
        associateByName = interner.intern("associateBy")
        associateWithName = interner.intern("associateWith")
        associateName = interner.intern("associate")
        mapValuesName = interner.intern("mapValues")
        mapKeysName = interner.intern("mapKeys")
        zipName = interner.intern("zip")
        unzipName = interner.intern("unzip")
        withIndexName = interner.intern("withIndex")
        forEachIndexedName = interner.intern("forEachIndexed")
        mapIndexedName = interner.intern("mapIndexed")
        sumOfName = interner.intern("sumOf")
        maxOrNullName = interner.intern("maxOrNull")
        minOrNullName = interner.intern("minOrNull")
        dropName = interner.intern("drop")
        reversedName = interner.intern("reversed")
        sortedName = interner.intern("sorted")
        distinctName = interner.intern("distinct")
        shuffledName = interner.intern("shuffled")
        flattenName = interner.intern("flatten")
        firstName = interner.intern("first")
        lastName = interner.intern("last")
        indexOfName = interner.intern("indexOf")
        lastIndexOfName = interner.intern("lastIndexOf")
        indexOfFirstName = interner.intern("indexOfFirst")
        indexOfLastName = interner.intern("indexOfLast")
        chunkedName = interner.intern("chunked")
        windowedName = interner.intern("windowed")
        sortedDescendingName = interner.intern("sortedDescending")
        sortedByDescendingName = interner.intern("sortedByDescending")
        sortedWithName = interner.intern("sortedWith")
        partitionName = interner.intern("partition")

        toMutableListName = interner.intern("toMutableList")
        toTypedArrayName = interner.intern("toTypedArray")
        copyOfName = interner.intern("copyOf")
        copyOfRangeName = interner.intern("copyOfRange")
        fillName = interner.intern("fill")

        asSequenceName = interner.intern("asSequence")
        toListName = interner.intern("toList")
        takeName = interner.intern("take")
        sequenceName = interner.intern("sequence")
        yieldName = interner.intern("yield")

        sequenceOfName = interner.intern("sequenceOf")
        generateSequenceName = interner.intern("generateSequence")

        printlnName = interner.intern("println")
        kkPrintlnAnyName = interner.intern("kk_println_any")
        kkAnyToStringName = interner.intern("kk_any_to_string")

        toName = interner.intern("to")
        kkPairNewName = interner.intern("kk_pair_new")
        kkPairFirstName = interner.intern("kk_pair_first")
        kkPairSecondName = interner.intern("kk_pair_second")

        tripleName = interner.intern("Triple")
        kkTripleNewName = interner.intern("kk_triple_new")

        buildStringName = interner.intern("buildString")
        buildListName = interner.intern("buildList")
        buildMapName = interner.intern("buildMap")
        kkBuildStringName = interner.intern("kk_build_string")
        kkBuildListName = interner.intern("kk_build_list")
        kkBuildListWithCapacityName = interner.intern("kk_build_list_with_capacity")
        kkBuildMapName = interner.intern("kk_build_map")

        appendName = interner.intern("append")
        putName = interner.intern("put")
        kkStringBuilderAppendName = interner.intern("kk_string_builder_append")
        kkBuilderListAddName = interner.intern("kk_builder_list_add")
        kkBuilderMapPutName = interner.intern("kk_builder_map_put")
        kkMutableSetAddName = interner.intern("kk_mutable_set_add")
        kkMutableSetRemoveName = interner.intern("kk_mutable_set_remove")
        kkMutableMapPutName = interner.intern("kk_mutable_map_put")

        listFactoryNames = [listOfName, mutableListOfName, emptyListName, listOfNotNullName]
        setFactoryNames = [setOfName, mutableSetOfName, emptySetName]
        mapFactoryNames = [mapOfName, mutableMapOfName, emptyMapName]
        arrayOfFactoryNames = [arrayOfName, intArrayOfName, longArrayOfName, doubleArrayOfName, booleanArrayOfName, charArrayOfName]
        builderDSLNames = [buildStringName, buildListName, buildMapName]
    }
}

// swiftformat:enable redundantMemberwiseInit
