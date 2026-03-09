import Foundation

struct CollectionLiteralLookupTables {
    // Source-level callee names
    let listOfName: InternedString
    let mutableListOfName: InternedString
    let emptyListName: InternedString
    let listOfNotNullName: InternedString
    let arrayOfName: InternedString
    let intArrayOfName: InternedString
    let longArrayOfName: InternedString
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
    let kkListTakeName: InternedString
    let kkListDropName: InternedString
    let kkListReversedName: InternedString
    let kkListSortedName: InternedString
    let kkListDistinctName: InternedString

    // Sequence ABI names (STDLIB-003)
    let kkSequenceFromListName: InternedString
    let kkSequenceMapName: InternedString
    let kkSequenceFilterName: InternedString
    let kkSequenceTakeName: InternedString
    let kkSequenceToListName: InternedString
    let kkSequenceBuilderBuildName: InternedString
    let kkSequenceBuilderYieldName: InternedString

    let kkMapOfName: InternedString
    let kkMapSizeName: InternedString
    let kkMapGetName: InternedString
    let kkMapContainsKeyName: InternedString
    let kkMapIsEmptyName: InternedString
    let kkMapToStringName: InternedString
    let kkMapIteratorName: InternedString
    let kkMapIteratorHasNextName: InternedString
    let kkMapIteratorNextName: InternedString

    let kkArraySizeName: InternedString
    let kkArrayNewName: InternedString
    let kkArraySetName: InternedString

    // Range iterator names (emitted by ForLoweringPass)
    let kkRangeIteratorName: InternedString
    let kkRangeHasNextName: InternedString
    let kkRangeNextName: InternedString

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
    let zipName: InternedString
    let unzipName: InternedString
    let dropName: InternedString
    let reversedName: InternedString
    let sortedName: InternedString
    let distinctName: InternedString
    let firstName: InternedString
    let lastName: InternedString

    // Sequence member names (STDLIB-003)
    let asSequenceName: InternedString
    let toListName: InternedString
    let takeName: InternedString
    let sequenceName: InternedString
    let yieldName: InternedString

    // println support
    let printlnName: InternedString
    let kkPrintlnAnyName: InternedString
    let kkAnyToStringName: InternedString

    // Pair / `to` infix (FUNC-002)
    let toName: InternedString
    let kkPairNewName: InternedString
    let kkPairFirstName: InternedString
    let kkPairSecondName: InternedString

    // Builder DSL names (STDLIB-002)
    let buildStringName: InternedString
    let buildListName: InternedString
    let buildMapName: InternedString
    let kkBuildStringName: InternedString
    let kkBuildListName: InternedString
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
        kkListTakeName = interner.intern("kk_list_take")
        kkListDropName = interner.intern("kk_list_drop")
        kkListReversedName = interner.intern("kk_list_reversed")
        kkListSortedName = interner.intern("kk_list_sorted")
        kkListDistinctName = interner.intern("kk_list_distinct")

        kkSequenceFromListName = interner.intern("kk_sequence_from_list")
        kkSequenceMapName = interner.intern("kk_sequence_map")
        kkSequenceFilterName = interner.intern("kk_sequence_filter")
        kkSequenceTakeName = interner.intern("kk_sequence_take")
        kkSequenceToListName = interner.intern("kk_sequence_to_list")
        kkSequenceBuilderBuildName = interner.intern("kk_sequence_builder_build")
        kkSequenceBuilderYieldName = interner.intern("kk_sequence_builder_yield")

        kkMapOfName = interner.intern("kk_map_of")
        kkMapSizeName = interner.intern("kk_map_size")
        kkMapGetName = interner.intern("kk_map_get")
        kkMapContainsKeyName = interner.intern("kk_map_contains_key")
        kkMapIsEmptyName = interner.intern("kk_map_is_empty")
        kkMapToStringName = interner.intern("kk_map_to_string")
        kkMapIteratorName = interner.intern("kk_map_iterator")
        kkMapIteratorHasNextName = interner.intern("kk_map_iterator_hasNext")
        kkMapIteratorNextName = interner.intern("kk_map_iterator_next")

        kkArraySizeName = interner.intern("kk_array_size")
        kkArrayNewName = interner.intern("kk_array_new")
        kkArraySetName = interner.intern("kk_array_set")

        kkRangeIteratorName = interner.intern("kk_range_iterator")
        kkRangeHasNextName = interner.intern("kk_range_hasNext")
        kkRangeNextName = interner.intern("kk_range_next")

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
        zipName = interner.intern("zip")
        unzipName = interner.intern("unzip")
        dropName = interner.intern("drop")
        reversedName = interner.intern("reversed")
        sortedName = interner.intern("sorted")
        distinctName = interner.intern("distinct")
        firstName = interner.intern("first")
        lastName = interner.intern("last")

        asSequenceName = interner.intern("asSequence")
        toListName = interner.intern("toList")
        takeName = interner.intern("take")
        sequenceName = interner.intern("sequence")
        yieldName = interner.intern("yield")

        printlnName = interner.intern("println")
        kkPrintlnAnyName = interner.intern("kk_println_any")
        kkAnyToStringName = interner.intern("kk_any_to_string")

        toName = interner.intern("to")
        kkPairNewName = interner.intern("kk_pair_new")
        kkPairFirstName = interner.intern("kk_pair_first")
        kkPairSecondName = interner.intern("kk_pair_second")

        buildStringName = interner.intern("buildString")
        buildListName = interner.intern("buildList")
        buildMapName = interner.intern("buildMap")
        kkBuildStringName = interner.intern("kk_build_string")
        kkBuildListName = interner.intern("kk_build_list")
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
        arrayOfFactoryNames = [arrayOfName, intArrayOfName, longArrayOfName]
        builderDSLNames = [buildStringName, buildListName, buildMapName]
    }
}
