import RuntimeABI

/// List lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct ListLookupNames {
    // Source-level callee names
    let listOfName: InternedString
    let mutableListOfName: InternedString
    let arrayListOfName: InternedString
    let emptyListName: InternedString
    // Type alias constructor names (STDLIB-245)
    let arrayListName: InternedString
    // Runtime ABI names
    let kkListOfName: InternedString
    let kkEmptyListName: InternedString
    let kkListSizeName: InternedString
    let kkListGetName: InternedString
    let kkListIsEmptyName: InternedString
    let kkListIteratorName: InternedString
    let kkListIteratorHasNextName: InternedString
    let kkListIteratorNextName: InternedString
    let kkListIteratorHasPreviousName: InternedString
    let kkListIteratorPreviousName: InternedString
    let kkListIteratorNextIndexName: InternedString
    let kkListIteratorPreviousIndexName: InternedString
    let kkListToStringName: InternedString
    let kkCollectionToMutableListName: InternedString
    // Higher-order collection function ABI names (FUNC-003)
    let kkListAssociateToName: InternedString
    let kkListForEachName: InternedString
    let kkCollectionToCollectionName: InternedString
    // Additional higher-order collection function ABI names (STDLIB-005)
    let kkListGroupByName: InternedString
    let kkListGroupByTransformName: InternedString
    let kkListSortedByName: InternedString
    let kkListAssociateByName: InternedString
    let kkListAssociateByTransformName: InternedString
    let kkListAssociateWithName: InternedString
    let kkListAssociateName: InternedString
    let kkListAssociateByToName: InternedString
    let kkListAssociateWithToName: InternedString
    let kkListGroupByToName: InternedString
    let kkListZipBridgeName: InternedString
    let kkListZipTransformBridgeName: InternedString
    let kkListZipWithNextBridgeName: InternedString
    let kkListZipWithNextTransformBridgeName: InternedString
    let kkListUnzipName: InternedString
    let kkIndexingIterableIteratorName: InternedString
    let kkIndexingIterableHasNextName: InternedString
    let kkIndexingIterableNextName: InternedString
    let kkListOnEachName: InternedString
    let kkListOnEachIndexedName: InternedString
    let kkListMaxOrNullName: InternedString
    let kkListMinOrNullName: InternedString
    let kkListMaxByName: InternedString
    let kkListMinName: InternedString
    let kkListMaxByOrNullName: InternedString
    let kkListMinByOrNullName: InternedString
    let kkListMinByName: InternedString
    let kkListMaxOfOrNullName: InternedString
    let kkListMinOfOrNullName: InternedString
    let kkListMaxOfName: InternedString
    let kkListMinOfName: InternedString
    let kkListMaxWithName: InternedString
    let kkListMaxWithOrNullName: InternedString
    let kkListMinWithName: InternedString
    let kkListMinWithOrNullName: InternedString
    let kkListMaxOfWithName: InternedString
    let kkListMaxOfWithOrNullName: InternedString
    let kkListMinOfWithName: InternedString
    let kkListMinOfWithOrNullName: InternedString
    let kkListSortedName: InternedString
    let kkListShuffledName: InternedString
    let kkListShuffledRandomName: InternedString
    let kkListChunkedBridgeName: InternedString
    let kkListChunkedTransformBridgeName: InternedString
    let kkListWindowedBridgeName: InternedString
    let kkListWindowedTransformBridgeName: InternedString
    let kkListSortedDescendingName: InternedString
    let kkListSortedByDescendingName: InternedString
    let kkListSortedWithName: InternedString
    let kkListPartitionName: InternedString
    // ListIterator member names (STDLIB-538)
    let listIteratorMemberName: InternedString
    let hasPreviousName: InternedString
    let previousName: InternedString
    let nextIndexName: InternedString
    let previousIndexName: InternedString
    // Common lookup sets
    let listFactoryNames: Set<InternedString>
    let mutableListConstructorNames: Set<InternedString>

    init(interner: StringInterner) {
        listOfName = interner.intern("listOf")
        mutableListOfName = interner.intern("mutableListOf")
        arrayListOfName = interner.intern("arrayListOf")
        emptyListName = interner.intern("emptyList")
        arrayListName = interner.intern("ArrayList")
        kkListOfName = interner.intern("__kk_list_of")
        kkEmptyListName = interner.intern("__kk_emptyList")
        kkListSizeName = interner.intern("__kk_list_size")
        kkListGetName = interner.intern("__kk_list_get")
        kkListIsEmptyName = interner.intern("kk_list_is_empty")
        kkListIteratorName = interner.intern("kk_list_iterator")
        kkListIteratorHasNextName = interner.intern("kk_list_iterator_hasNext")
        kkListIteratorNextName = interner.intern("kk_list_iterator_next")
        kkListIteratorHasPreviousName = interner.intern("kk_list_iterator_hasPrevious")
        kkListIteratorPreviousName = interner.intern("kk_list_iterator_previous")
        kkListIteratorNextIndexName = interner.intern("kk_list_iterator_nextIndex")
        kkListIteratorPreviousIndexName = interner.intern("kk_list_iterator_previousIndex")
        kkListToStringName = interner.intern("kk_list_to_string")
        kkCollectionToMutableListName = interner.intern("__kk_collection_toMutableList")
        kkListAssociateToName = .invalid
        kkListForEachName = interner.intern("kk_list_forEach")
        kkCollectionToCollectionName = interner.intern("__kk_collection_toCollection")
        kkListGroupByName = .invalid
        kkListGroupByTransformName = .invalid
        kkListSortedByName = interner.intern("kk_list_sortedBy")
        kkListAssociateByName = .invalid
        kkListAssociateByTransformName = .invalid
        kkListAssociateWithName = .invalid
        kkListAssociateName = .invalid
        kkListAssociateByToName = .invalid
        kkListAssociateWithToName = .invalid
        kkListGroupByToName = .invalid
        kkListZipBridgeName = interner.intern("__kk_list_zip")
        kkListZipTransformBridgeName = interner.intern("__kk_list_zip_transform")
        kkListZipWithNextBridgeName = interner.intern("__kk_list_zipWithNext")
        kkListZipWithNextTransformBridgeName = interner.intern("__kk_list_zipWithNextTransform")
        kkListUnzipName = .invalid
        kkIndexingIterableIteratorName = interner.intern("kk_indexing_iterable_iterator")
        kkIndexingIterableHasNextName = interner.intern("kk_indexing_iterable_hasNext")
        kkIndexingIterableNextName = interner.intern("kk_indexing_iterable_next")
        kkListOnEachName = .invalid
        kkListOnEachIndexedName = .invalid
        kkListMaxOrNullName = interner.intern("kk_list_maxOrNull")
        kkListMinOrNullName = interner.intern("kk_list_minOrNull")
        kkListMaxByName = interner.intern("kk_list_maxBy")
        kkListMinName = interner.intern("kk_list_min")
        kkListMaxByOrNullName = interner.intern("kk_list_maxByOrNull")
        kkListMinByOrNullName = interner.intern("kk_list_minByOrNull")
        kkListMinByName = interner.intern("kk_list_minBy")
        kkListMaxOfOrNullName = interner.intern("kk_list_maxOfOrNull")
        kkListMinOfOrNullName = interner.intern("kk_list_minOfOrNull")
        kkListMaxOfName = interner.intern("kk_list_maxOf")
        kkListMinOfName = interner.intern("kk_list_minOf")
        kkListMaxWithName = interner.intern("kk_list_maxWith")
        kkListMaxWithOrNullName = interner.intern("kk_list_maxWithOrNull")
        kkListMinWithName = interner.intern("kk_list_minWith")
        kkListMinWithOrNullName = interner.intern("kk_list_minWithOrNull")
        kkListMaxOfWithName = interner.intern("kk_list_maxOfWith")
        kkListMaxOfWithOrNullName = interner.intern("kk_list_maxOfWithOrNull")
        kkListMinOfWithName = interner.intern("kk_list_minOfWith")
        kkListMinOfWithOrNullName = interner.intern("kk_list_minOfWithOrNull")
        kkListSortedName = interner.intern("kk_list_sorted")
        kkListShuffledName = interner.intern("kk_list_shuffled")
        kkListShuffledRandomName = interner.intern("kk_list_shuffled_random")
        kkListChunkedBridgeName = interner.intern("__kk_list_chunked")
        kkListChunkedTransformBridgeName = interner.intern("__kk_list_chunked_transform")
        kkListWindowedBridgeName = interner.intern("__kk_list_windowed")
        kkListWindowedTransformBridgeName = interner.intern("__kk_list_windowed_transform")
        kkListSortedDescendingName = interner.intern("kk_list_sortedDescending")
        kkListSortedByDescendingName = interner.intern("kk_list_sortedByDescending")
        kkListSortedWithName = interner.intern("kk_list_sortedWith")
        kkListPartitionName = .invalid
        // ListIterator member names (STDLIB-538)
        listIteratorMemberName = interner.intern("listIterator")
        hasPreviousName = interner.intern("hasPrevious")
        previousName = interner.intern("previous")
        nextIndexName = interner.intern("nextIndex")
        previousIndexName = interner.intern("previousIndex")
        listFactoryNames = [listOfName, mutableListOfName, arrayListOfName, emptyListName]
        mutableListConstructorNames = [arrayListName]
    }
}
