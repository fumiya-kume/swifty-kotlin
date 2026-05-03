import Foundation

// swiftformat:disable redundantMemberwiseInit
struct CollectionLiteralLookupTables {
    // Source-level callee names
    let listOfName: InternedString
    let mutableListOfName: InternedString
    let arrayListOfName: InternedString
    let emptyListName: InternedString
    let listOfNotNullName: InternedString
    let arrayOfName: InternedString
    let emptyArrayName: InternedString
    let intArrayOfName: InternedString
    let longArrayOfName: InternedString
    let shortArrayOfName: InternedString
    let byteArrayOfName: InternedString
    let uintArrayOfName: InternedString
    let doubleArrayOfName: InternedString
    let floatArrayOfName: InternedString
    let booleanArrayOfName: InternedString
    let charArrayOfName: InternedString
    let mapOfName: InternedString
    let mutableMapOfName: InternedString
    let hashMapOfName: InternedString
    let linkedMapOfName: InternedString
    let emptyMapName: InternedString
    let setOfName: InternedString
    let setOfNotNullName: InternedString
    let mutableSetOfName: InternedString
    let linkedSetOfName: InternedString
    let hashSetOfName: InternedString
    let emptySetName: InternedString

    // Type alias constructor names (STDLIB-245)
    let arrayListName: InternedString
    let hashMapName: InternedString
    let hashSetName: InternedString
    let linkedHashMapName: InternedString
    let linkedHashSetName: InternedString

    // Runtime ABI names
    let kkListOfName: InternedString
    let kkListOfNotNullName: InternedString
    let kkEmptyListName: InternedString
    let kkEmptyArrayName: InternedString
    let kkEmptySetName: InternedString
    let kkEmptyMapName: InternedString
    let kkListSizeName: InternedString
    let kkListGetName: InternedString
    let kkListContainsName: InternedString
    let kkListContainsAllName: InternedString
    let kkListBinarySearchName: InternedString
    let kkListBinarySearchCompareName: InternedString
    let kkListIsEmptyName: InternedString
    let kkListIteratorName: InternedString
    let kkListIteratorHasNextName: InternedString
    let kkListIteratorNextName: InternedString
    let kkListIteratorHasPreviousName: InternedString
    let kkListIteratorPreviousName: InternedString
    let kkListToStringName: InternedString
    let kkSetOfName: InternedString
    let kkSetOfNotNullName: InternedString
    let kkSetSizeName: InternedString
    let kkSetContainsName: InternedString
    let kkSetContainsAllName: InternedString
    let kkSetIsEmptyName: InternedString
    let kkSetToStringName: InternedString
    // Set higher-order function ABI names (STDLIB-268)
    let kkSetMapName: InternedString
    let kkSetFilterName: InternedString
    let kkSetForEachName: InternedString
    let kkSetToListName: InternedString
    let kkSetFilterNotName: InternedString
    let kkSetMapNotNullName: InternedString
    let kkSetFlatMapName: InternedString
    // Set predicate HOF ABI names (STDLIB-SET-PRED)
    let kkSetAnyName: InternedString
    let kkSetNoneName: InternedString
    let kkSetAllName: InternedString
    let kkSetCountPredicateName: InternedString

    let kkStringSplitName: InternedString
    let kkStringChunkedName: InternedString
    let kkStringWindowedName: InternedString
    let kkStringAsSequenceName: InternedString
    let kkStringAsIterableName: InternedString
    let kkStringWindowedPartialName: InternedString
    let kkStringIteratorName: InternedString
    let kkStringIteratorHasNextName: InternedString
    let kkStringIteratorNextName: InternedString
    let kkStringFilterName: InternedString
    let kkStringMapName: InternedString
    let kkStringCountName: InternedString
    let kkStringAnyName: InternedString
    let kkStringAllName: InternedString
    let kkStringNoneName: InternedString

    // Higher-order collection function ABI names (FUNC-003)
    let kkListMapName: InternedString
    let kkListFilterName: InternedString
    let kkListFilterNotName: InternedString
    let kkListMapNotNullName: InternedString
    let kkListFilterNotNullName: InternedString
    let kkListFilterToName: InternedString
    let kkListFilterNotToName: InternedString
    let kkListMapToName: InternedString
    let kkListFlatMapToName: InternedString
    let kkListMapNotNullToName: InternedString
    let kkListMapIndexedToName: InternedString
    let kkListFlatMapIndexedToName: InternedString
    let kkListAssociateToName: InternedString
    let kkListFilterIsInstanceToName: InternedString
    let kkListForEachName: InternedString
    let kkListFlatMapName: InternedString
    let kkListAnyName: InternedString
    let kkListNoneName: InternedString
    let kkListAllName: InternedString
    let kkCollectionToCollectionName: InternedString

    // Additional higher-order collection function ABI names (STDLIB-005)
    let kkListFoldName: InternedString
    let kkListFoldRightName: InternedString
    let kkListReduceName: InternedString
    let kkListReduceRightName: InternedString
    let kkListReduceRightIndexedName: InternedString
    let kkListReduceRightIndexedOrNullName: InternedString
    let kkListReduceRightOrNullName: InternedString
    let kkListReduceOrNullName: InternedString
    let kkListScanName: InternedString
    let kkListRunningFoldName: InternedString
    let kkListRunningReduceName: InternedString
    let kkListScanReduceName: InternedString
    let kkListGroupByName: InternedString
    let kkListGroupByTransformName: InternedString
    let kkListSortedByName: InternedString
    let kkListAssociateByName: InternedString
    let kkListAssociateWithName: InternedString
    let kkListAssociateName: InternedString
    let kkListAssociateByToName: InternedString
    let kkListAssociateWithToName: InternedString
    let kkListGroupByToName: InternedString
    let kkListCountName: InternedString
    let kkListFirstName: InternedString
    let kkListLastName: InternedString
    let kkListFindName: InternedString
    let kkListZipName: InternedString
    let kkListZipWithNextName: InternedString
    let kkListZipWithNextTransformName: InternedString
    let kkListUnzipName: InternedString
    let kkListWithIndexName: InternedString
    let kkIndexingIterableIteratorName: InternedString
    let kkIndexingIterableHasNextName: InternedString
    let kkIndexingIterableNextName: InternedString
    let kkListForEachIndexedName: InternedString
    let kkListOnEachName: InternedString
    let kkListOnEachIndexedName: InternedString
    let kkListMapIndexedName: InternedString
    let kkListFilterIndexedName: InternedString
    let kkListFoldIndexedName: InternedString
    let kkListFoldRightIndexedName: InternedString
    let kkListReduceIndexedName: InternedString
    let kkListReduceIndexedOrNullName: InternedString
    let kkListRunningFoldIndexedName: InternedString
    let kkListRunningReduceIndexedName: InternedString
    let kkListScanIndexedName: InternedString
    let kkListSumOfName: InternedString
    let kkListSumByName: InternedString
    let kkListSumByDoubleName: InternedString
    let kkListMaxOrNullName: InternedString
    let kkListMinOrNullName: InternedString
    let kkListMaxByOrNullName: InternedString
    let kkListMinByOrNullName: InternedString
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
    let kkListTakeName: InternedString
    let kkListDropName: InternedString
    let kkListSumName: InternedString
    let kkListReversedName: InternedString
    let kkListAsReversedName: InternedString
    let kkListSortedName: InternedString
    let kkSetSortedName: InternedString
    let kkListDistinctName: InternedString
    let kkListDistinctByName: InternedString
    let kkListShuffledName: InternedString
    let kkListShuffledRandomName: InternedString
    let kkListPlusElementName: InternedString
    let kkListPlusCollectionName: InternedString
    let kkListMinusElementName: InternedString
    let kkListMinusCollectionName: InternedString
    let kkListRandomName: InternedString
    let kkListRandomOrNullName: InternedString
    let kkListFlattenName: InternedString
    let kkListIndexOfName: InternedString
    let kkListLastIndexOfName: InternedString
    let kkListIndexOfFirstName: InternedString
    let kkListIndexOfLastName: InternedString
    let kkListChunkedName: InternedString
    let kkListChunkedTransformName: InternedString
    let kkListWindowedDefaultName: InternedString
    let kkListWindowedName: InternedString
    let kkListWindowedPartialName: InternedString
    let kkListWindowedTransformName: InternedString
    let kkListSortedDescendingName: InternedString
    let kkListSortedByDescendingName: InternedString
    let kkListSortedWithName: InternedString
    let kkListPartitionName: InternedString
    let kkListTakeWhileName: InternedString
    let kkListDropWhileName: InternedString
    let kkListTakeLastWhileName: InternedString
    let kkListDropLastWhileName: InternedString

    // Comparator ABI names (STDLIB-175, STDLIB-177, STDLIB-613)
    let kkComparatorFromSelectorName: InternedString
    let kkComparatorFromSelectorDescendingName: InternedString
    let kkComparatorFromSelectorTrampolineName: InternedString
    let kkComparatorFromSelectorDescendingTrampolineName: InternedString
    let kkComparatorFromMultiSelectorsName: InternedString
    let kkComparatorFromMultiSelectors3Name: InternedString
    let kkComparatorFromMultiSelectorsVarargName: InternedString
    let kkComparatorFromMultiSelectorsTrampolineName: InternedString
    let kkComparatorNaturalOrderName: InternedString
    let kkComparatorReverseOrderName: InternedString
    let kkComparatorNaturalOrderTrampolineName: InternedString
    let kkComparatorReverseOrderTrampolineName: InternedString
    let kkComparatorThenByName: InternedString
    let kkComparatorThenByDescendingName: InternedString
    let kkComparatorThenDescendingName: InternedString
    let kkComparatorThenComparatorName: InternedString
    let kkComparatorThenByTrampolineName: InternedString
    let kkComparatorThenByDescendingTrampolineName: InternedString
    let kkComparatorThenDescendingTrampolineName: InternedString
    let kkComparatorThenComparatorTrampolineName: InternedString
    let kkComparatorNullsFirstName: InternedString
    let kkComparatorNullsLastName: InternedString
    let kkComparatorNullsFirstTrampolineName: InternedString
    let kkComparatorNullsLastTrampolineName: InternedString
    let kkComparatorReversedName: InternedString
    let kkComparatorReversedTrampolineName: InternedString
    let kkCompareValuesName: InternedString
    let kkCompareValuesBy1Name: InternedString
    let kkCompareValuesByName: InternedString
    let kkCompareValuesBy3Name: InternedString

    // Sequence ABI names (STDLIB-003)
    let kkSequenceFromListName: InternedString
    let kkSequenceMapName: InternedString
    let kkSequenceFilterName: InternedString
    let kkSequenceTakeName: InternedString
    let kkSequenceToListName: InternedString
    let kkSequenceConstrainOnceName: InternedString
    let kkSequenceBuilderBuildName: InternedString
    let kkSequenceBuilderYieldName: InternedString
    let kkSequenceBuilderYieldAllName: InternedString
    let kkIteratorBuilderBuildName: InternedString
    let kkIteratorBuilderYieldName: InternedString
    let kkIteratorBuilderHasNextName: InternedString
    let kkIteratorBuilderNextName: InternedString

    // Sequence ABI names (STDLIB-095/096/097)
    let kkSequenceOfName: InternedString
    let kkSequenceGenerateName: InternedString
    let kkSequenceGenerateNoArgName: InternedString
    let kkSequenceForEachName: InternedString
    let kkSequenceFlatMapName: InternedString
    let kkSequenceFlatMapIndexedName: InternedString
    let kkSequenceDropName: InternedString
    let kkSequenceDistinctName: InternedString
    let kkSequenceZipName: InternedString
    let kkSequenceSortedName: InternedString
    let kkSequenceSortedByName: InternedString
    let kkSequenceSortedDescendingName: InternedString
    let kkSequenceShuffledName: InternedString
    let kkSequenceShuffledRandomName: InternedString
    let kkSequenceMapNotNullName: InternedString
    let kkSequenceFilterNotNullName: InternedString
    let kkSequenceMapIndexedName: InternedString
    let kkSequenceWithIndexName: InternedString
    let kkSequenceJoinToStringName: InternedString
    let kkSequenceSumOfName: InternedString
    let kkSequenceAssociateName: InternedString
    let kkSequenceAssociateByName: InternedString
    let kkSequenceAssociateToName: InternedString
    let kkSequenceAssociateByToName: InternedString
    let kkSequenceAssociateWithToName: InternedString
    let kkSequenceChunkedName: InternedString
    let kkSequenceWindowedName: InternedString
    let kkSequenceOnEachName: InternedString
    let kkEmptySequenceName: InternedString
    let kkSequenceIfEmptyName: InternedString
    let kkSequenceForEachIndexedName: InternedString
    let kkSequenceZipWithNextName: InternedString
    let kkSequenceZipWithNextTransformName: InternedString
    let kkSequenceFirstName: InternedString
    let kkSequenceFirstOrNullName: InternedString
    let kkSequenceLastName: InternedString
    let kkSequenceCountName: InternedString

    // STDLIB-558, 559, 560: Sequence scan / runningFold / runningReduce
    let kkSequenceScanName: InternedString
    let kkSequenceRunningFoldName: InternedString
    let kkSequenceRunningReduceName: InternedString

    // STDLIB-470: Sequence terminal ops
    let kkSequenceToSetName: InternedString
    let kkSequenceToMapName: InternedString
    let kkSequenceToCollectionName: InternedString
    let kkSequenceGroupByName: InternedString
    let kkSequenceGroupByToName: InternedString
    let kkSequenceMaxOrNullName: InternedString
    let kkSequenceMinOrNullName: InternedString
    let kkSequenceFlattenName: InternedString
    let kkSequenceFoldName: InternedString
    let kkSequenceFoldIndexedName: InternedString
    let kkSequenceRunningFoldIndexedName: InternedString
    let kkSequenceReduceIndexedName: InternedString
    let kkSequenceReduceIndexedOrNullName: InternedString
    let kkSequenceRunningReduceIndexedName: InternedString

    // STDLIB-561/562: Sequence plus/minus
    let kkSequencePlusName: InternedString
    let kkSequencePlusElementName: InternedString
    let kkSequenceMinusName: InternedString
    let kkSequenceOfSingleName: InternedString

    // STDLIB-SEQ-012: Sequence partition
    let kkSequencePartitionName: InternedString
    // STDLIB-SEQ-021: Sequence destination-collection filter operations
    let kkSequenceFilterToName: InternedString
    let kkSequenceFilterNotToName: InternedString
    // STDLIB-SEQ-022: Sequence destination-collection mapping operations
    let kkSequenceMapToName: InternedString
    let kkSequenceMapIndexedNotNullToName: InternedString
    let kkSequenceFilterIndexedToName: InternedString
    let kkSequenceFilterNotNullToName: InternedString
    let kkSequenceFilterIsInstanceToName: InternedString

    let kkMapOfName: InternedString
    let kkMapSizeName: InternedString
    let kkMapGetName: InternedString
    let kkMapContainsKeyName: InternedString
    let kkMapContainsValueName: InternedString
    let kkMapIsEmptyName: InternedString
    let kkMapForEachName: InternedString
    let kkMapMapName: InternedString
    let kkMapFilterName: InternedString
    let kkMapFilterNotName: InternedString
    let kkMapFilterKeysName: InternedString
    let kkMapFilterValuesName: InternedString
    let kkMapMapValuesName: InternedString
    let kkMapMapKeysName: InternedString
    let kkMapMapNotNullName: InternedString
    let kkMapCountName: InternedString
    let kkMapAnyName: InternedString
    let kkMapAllName: InternedString
    let kkMapNoneName: InternedString
    let kkMapFlatMapName: InternedString
    let kkMapMaxByOrNullName: InternedString
    let kkMapMinByOrNullName: InternedString
    let kkMapToListName: InternedString
    let kkMapToStringName: InternedString
    let kkMapIteratorName: InternedString
    let kkMapIteratorHasNextName: InternedString
    let kkMapIteratorNextName: InternedString
    let kkMutableMapPutAllName: InternedString
    let kkMapKeysName: InternedString
    let kkMapValuesName: InternedString
    let kkMapEntriesName: InternedString

    let kkArraySizeName: InternedString
    let kkArrayNewName: InternedString
    let kkArraySetName: InternedString

    // Array conversion / HOF / utility ABI names (STDLIB-087/088/089)
    let kkArrayToListName: InternedString
    let kkArrayToMutableListName: InternedString
    let kkListToTypedArrayName: InternedString
    let kkListToIntArrayName: InternedString
    let kkListToLongArrayName: InternedString
    let kkListToByteArrayName: InternedString
    let kkListToUByteArrayName: InternedString
    let kkListToUShortArrayName: InternedString
    let kkListToUIntArrayName: InternedString
    let kkListToULongArrayName: InternedString
    let kkArrayMapName: InternedString
    let kkArrayFilterName: InternedString
    let kkArrayForEachName: InternedString
    let kkArrayAnyName: InternedString
    let kkArrayNoneName: InternedString
    let kkArrayCopyOfName: InternedString
    let kkArrayCopyOfNewSizeName: InternedString
    let kkArrayCopyOfNewSizeInitName: InternedString
    let kkArrayCopyOfRangeName: InternedString
    let kkArrayFillName: InternedString
    let kkListAsSequenceName: InternedString
    let kkArrayAsSequenceName: InternedString

    // Range iterator names (emitted by ForLoweringPass)
    let kkRangeIteratorName: InternedString
    let kkRangeHasNextName: InternedString
    let kkRangeNextName: InternedString

    // Range factory / member ABI names (STDLIB-090/091/092/093)
    let kkOpRangeToName: InternedString
    let kkOpRangeUntilName: InternedString
    let kkOpULongRangeUntilName: InternedString
    let kkOpDownToName: InternedString
    let kkOpStepName: InternedString
    let kkRangeFirstName: InternedString
    let kkRangeLastName: InternedString
    let kkRangeEndExclusiveName: InternedString
    let kkRangeCountName: InternedString
    let kkRangeToListName: InternedString
    let kkRangeForEachName: InternedString
    let kkRangeMapName: InternedString
    let kkRangeMapIndexedName: InternedString
    let kkRangeMapNotNullName: InternedString
    let kkRangeFilterName: InternedString
    let kkRangeFilterIndexedName: InternedString
    let kkRangeFilterNotName: InternedString
    let kkRangeReduceName: InternedString
    let kkRangeReduceIndexedName: InternedString
    let kkRangeFoldName: InternedString
    let kkRangeFoldIndexedName: InternedString
    let kkRangeFindName: InternedString
    let kkRangeFindLastName: InternedString
    let kkRangeFirstPredicateName: InternedString
    let kkRangeFirstOrNullPredicateName: InternedString
    let kkRangeLastPredicateName: InternedString
    let kkRangeLastOrNullPredicateName: InternedString
    let kkRangeAnyName: InternedString
    let kkRangeAllName: InternedString
    let kkRangeNoneName: InternedString
    let kkRangeChunkedName: InternedString
    let kkRangeWindowedName: InternedString
    let kkRangeStepName: InternedString
    let kkRangeReversedName: InternedString
    let kkRangeIsEmptyName: InternedString
    let kkRangeSumName: InternedString
    let kkRangeToIntArrayName: InternedString
    let kkRangeTakeName: InternedString
    let kkRangeDropName: InternedString
    let kkRangeAverageName: InternedString
    let kkRangeSortedName: InternedString
    let kkOpContainsName: InternedString

    // Member names (STDLIB-637)
    let sumName: InternedString

    // CharRange (STDLIB-290)
    let kkBoxCharName: InternedString
    let kkCharRangeToListName: InternedString
    let kkCharRangeForEachName: InternedString

    // ULongRange (STDLIB-524, STDLIB-RANGE-037)
    let kkULongRangeToListName: InternedString
    let kkULongRangeContainsName: InternedString
    let kkULongRangeFirstName: InternedString
    let kkULongRangeLastName: InternedString
    let kkULongRangeStepName: InternedString
    let kkULongRangeIsEmptyName: InternedString
    let kkULongRangeReversedName: InternedString
    let kkULongRangeToULongArrayName: InternedString
    let kkULongRangeCountName: InternedString
    let kkULongRangeIteratorName: InternedString
    let kkULongRangeHasNextName: InternedString
    let kkULongRangeNextName: InternedString
    let kkULongRangeForEachName: InternedString
    let kkULongRangeMapName: InternedString

    let sizeName: InternedString
    let getName: InternedString
    let containsName: InternedString
    let containsAllName: InternedString
    let containsKeyName: InternedString
    let containsValueName: InternedString
    let isEmptyName: InternedString
    let countName: InternedString
    let addName: InternedString
    let removeName: InternedString
    let firstName: InternedString
    let lastName: InternedString
    let startName: InternedString
    let endInclusiveName: InternedString
    let endExclusiveName: InternedString
    let stepName: InternedString
    let iteratorName: InternedString

    // ListIterator member names (STDLIB-538)
    let listIteratorMemberName: InternedString
    let hasPreviousName: InternedString
    let previousName: InternedString

    // Higher-order collection member names (FUNC-003)
    let mapName: InternedString
    let filterName: InternedString
    let filterNotName: InternedString
    let mapNotNullName: InternedString
    let filterNotNullName: InternedString
    let filterToName: InternedString
    let filterNotToName: InternedString
    let mapToName: InternedString
    let flatMapToName: InternedString
    let mapNotNullToName: InternedString
    let mapIndexedToName: InternedString
    let mapIndexedNotNullToName: InternedString
    let flatMapIndexedToName: InternedString
    let filterIsInstanceToName: InternedString
    let filterIndexedToName: InternedString
    let filterNotNullToName: InternedString
    let forEachName: InternedString
    let flatMapName: InternedString
    let flatMapIndexedName: InternedString
    let anyName: InternedString
    let noneName: InternedString
    let allName: InternedString

    // Additional higher-order collection member names (STDLIB-005)
    let foldName: InternedString
    let foldRightName: InternedString
    let reduceName: InternedString
    let reduceRightName: InternedString
    let reduceOrNullName: InternedString
    let scanName: InternedString
    let runningFoldName: InternedString
    let runningReduceName: InternedString
    let scanReduceName: InternedString
    let groupByName: InternedString
    let sortedByName: InternedString
    let findName: InternedString
    let findLastName: InternedString
    let associateByName: InternedString
    let associateWithName: InternedString
    let associateName: InternedString
    let associateToName: InternedString
    let associateByToName: InternedString
    let associateWithToName: InternedString
    let groupByToName: InternedString
    let mapValuesName: InternedString
    let mapKeysName: InternedString
    let filterKeysName: InternedString
    let filterValuesName: InternedString
    let zipName: InternedString
    let zipWithNextName: InternedString
    let unzipName: InternedString
    let withIndexName: InternedString
    let forEachIndexedName: InternedString
    let onEachName: InternedString
    let onEachIndexedName: InternedString
    let mapIndexedName: InternedString
    let foldIndexedName: InternedString
    let foldRightIndexedName: InternedString
    let reduceRightIndexedName: InternedString
    let reduceRightIndexedOrNullName: InternedString
    let reduceRightOrNullName: InternedString
    let reduceIndexedName: InternedString
    let filterIndexedName: InternedString
    let reduceIndexedOrNullName: InternedString
    let runningFoldIndexedName: InternedString
    let runningReduceIndexedName: InternedString
    let scanIndexedName: InternedString
    let sumOfName: InternedString
    let sumByName: InternedString
    let sumByDoubleName: InternedString
    let maxOrNullName: InternedString
    let minOrNullName: InternedString
    let maxByOrNullName: InternedString
    let minByOrNullName: InternedString
    let maxOfOrNullName: InternedString
    let minOfOrNullName: InternedString
    let maxOfName: InternedString
    let minOfName: InternedString
    let maxWithName: InternedString
    let maxWithOrNullName: InternedString
    let minWithName: InternedString
    let minWithOrNullName: InternedString
    let maxOfWithName: InternedString
    let maxOfWithOrNullName: InternedString
    let minOfWithName: InternedString
    let minOfWithOrNullName: InternedString
    let dropName: InternedString
    let reversedName: InternedString
    let asReversedName: InternedString
    let sortedName: InternedString
    let averageName: InternedString
    let distinctName: InternedString
    let distinctByName: InternedString
    let shuffledName: InternedString
    let flattenName: InternedString
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
    let takeWhileName: InternedString
    let dropWhileName: InternedString
    let takeLastWhileName: InternedString
    let dropLastWhileName: InternedString
    let firstOrNullName: InternedString
    let lastOrNullName: InternedString

    // Array member names (STDLIB-087/088/089)
    let toMutableListName: InternedString
    let toTypedArrayName: InternedString
    let copyOfName: InternedString
    let copyOfRangeName: InternedString
    let fillName: InternedString

    // Sequence plus/minus member names (STDLIB-561/562)
    let plusMemberName: InternedString
    let plusElementName: InternedString
    let minusElementName: InternedString
    let minusMemberName: InternedString

    // Sequence member names (STDLIB-003)
    let asSequenceName: InternedString
    let toListName: InternedString
    let constrainOnceName: InternedString
    let toCollectionName: InternedString
    let toUByteArrayName: InternedString
    let toUShortArrayName: InternedString
    let toUIntArrayName: InternedString
    let toULongArrayName: InternedString
    let toIntArrayName: InternedString
    let toLongArrayName: InternedString
    let toByteArrayName: InternedString
    let kkLongRangeToLongArrayName: InternedString
    let toSetName: InternedString
    let toMapName: InternedString
    let takeName: InternedString
    let sequenceName: InternedString
    let iteratorBuilderName: InternedString
    let iteratorBuilderFQName: [InternedString]
    // FQN arrays for stdlib collection factory functions (STDLIB-410)
    let emptyListFQName: [InternedString]
    let emptyArrayFQName: [InternedString]
    let emptySetFQName: [InternedString]
    let emptyMapFQName: [InternedString]
    let listOfFQName: [InternedString]
    let setOfFQName: [InternedString]
    let setOfNotNullFQName: [InternedString]
    let mapOfFQName: [InternedString]
    let mutableListOfFQName: [InternedString]
    let arrayListOfFQName: [InternedString]
    let mutableSetOfFQName: [InternedString]
    let linkedSetOfFQName: [InternedString]
    let hashSetOfFQName: [InternedString]
    let mutableMapOfFQName: [InternedString]
    let hashMapOfFQName: [InternedString]
    let linkedMapOfFQName: [InternedString]
    let listOfNotNullFQName: [InternedString]
    let yieldName: InternedString
    let yieldAllName: InternedString

    // Sequence factory names (STDLIB-097)
    let sequenceOfName: InternedString
    let generateSequenceName: InternedString

    // println support
    let printlnName: InternedString
    let kkPrintlnAnyName: InternedString
    let kkAnyToStringName: InternedString
    let kotlinName: InternedString
    let initName: InternedString

    // Pair / `to` infix (FUNC-002)
    let toName: InternedString
    let pairName: InternedString
    let kkPairNewName: InternedString
    let kkPairFirstName: InternedString
    let kkPairSecondName: InternedString

    // Triple (STDLIB-120)
    let tripleName: InternedString
    let kkTripleNewName: InternedString

    // Builder DSL names (STDLIB-002)
    let buildStringName: InternedString
    let buildListName: InternedString
    let buildSetName: InternedString
    let buildMapName: InternedString
    let kkBuildStringName: InternedString
    let kkBuildStringWithCapacityName: InternedString
    let kkBuildListName: InternedString
    let kkBuildListWithCapacityName: InternedString
    let kkBuildSetName: InternedString
    let kkBuildMapName: InternedString

    // Builder member function names (STDLIB-002)
    let appendName: InternedString
    let addAllName: InternedString
    let putName: InternedString
    let kkStringBuilderAppendName: InternedString
    let kkBuilderListAddName: InternedString
    let kkBuilderListAddAllName: InternedString
    let kkBuilderSetAddName: InternedString
    let kkBuilderSetAddAllName: InternedString
    let kkBuilderMapPutName: InternedString
    let kkMutableSetAddName: InternedString
    let kkMutableSetRemoveName: InternedString
    let kkMutableMapPutName: InternedString

    // StringBuilder enhancements (STDLIB-311)
    let appendLineName: InternedString
    let insertName: InternedString
    let deleteName: InternedString
    let lengthName: InternedString
    let appendRangeName: InternedString
    let kkStringBuilderAppendLineName: InternedString
    let kkStringBuilderAppendLineNoargName: InternedString
    let kkStringBuilderInsertName: InternedString
    let kkStringBuilderDeleteName: InternedString
    let kkStringBuilderLengthName: InternedString
    let kkStringBuilderAppendRangeName: InternedString

    // File I/O names (STDLIB-565)
    let fileConstructorName: InternedString
    let kkFileNewName: InternedString
    let readTextName: InternedString
    let kkFileReadTextName: InternedString
    let writeTextName: InternedString
    let kkFileWriteTextName: InternedString
    let appendTextName: InternedString
    let kkFileAppendTextName: InternedString
    let readLinesName: InternedString
    let kkFileReadLinesName: InternedString
    let existsName: InternedString
    let kkFileExistsName: InternedString
    let isFileName: InternedString
    let kkFileIsFileName: InternedString
    let isDirectoryName: InternedString
    let kkFileIsDirectoryName: InternedString
    let namePropertyName: InternedString
    let kkFileNameName: InternedString
    let pathPropertyName: InternedString
    let kkFilePathName: InternedString
    let forEachLineName: InternedString
    let kkFileForEachLineName: InternedString
    let useLinesName: InternedString
    let kkFileUseLinesName: InternedString
    let bufferedReaderName: InternedString
    let kkFileBufferedReaderName: InternedString
    let bufferedWriterName: InternedString
    let kkFileBufferedWriterName: InternedString
    let kkBufferedWriterWriteName: InternedString
    let kkBufferedWriterNewLineName: InternedString
    let kkBufferedWriterFlushName: InternedString
    let kkBufferedWriterCloseName: InternedString
    let kkFileDeleteName: InternedString
    let mkdirsName: InternedString
    let kkFileMkdirsName: InternedString
    let listFilesName: InternedString
    let kkFileListFilesName: InternedString
    let walkName: InternedString
    let kkFileWalkName: InternedString
    let readBytesName: InternedString
    let kkFileReadBytesName: InternedString
    // STDLIB-IO-087: Additional File operations
    let absolutePathName: InternedString
    let kkFileAbsolutePathName: InternedString
    let canonicalPathName: InternedString
    let kkFileCanonicalPathName: InternedString
    let parentName: InternedString
    let kkFileParentName: InternedString
    // Note: lengthName is shared with StringBuilder section (defined above)
    let kkFileLengthName: InternedString
    let lastModifiedName: InternedString
    let kkFileLastModifiedName: InternedString
    let createNewFileName: InternedString
    let kkFileCreateNewFileName: InternedString
    let canReadName: InternedString
    let kkFileCanReadName: InternedString
    let canWriteName: InternedString
    let kkFileCanWriteName: InternedString
    let canExecuteName: InternedString
    let kkFileCanExecuteName: InternedString
    let kkFileNewParentChildName: InternedString

    // Common lookup sets
    let listFactoryNames: Set<InternedString>
    let setFactoryNames: Set<InternedString>
    let mapFactoryNames: Set<InternedString>
    let mutableListConstructorNames: Set<InternedString>
    let mutableSetConstructorNames: Set<InternedString>
    let mutableMapConstructorNames: Set<InternedString>
    let arrayOfFactoryNames: Set<InternedString>
    let builderDSLNames: Set<InternedString>
    let stringProducingCallees: Set<InternedString>

    init(interner: StringInterner) {
        listOfName = interner.intern("listOf")
        mutableListOfName = interner.intern("mutableListOf")
        arrayListOfName = interner.intern("arrayListOf")
        emptyListName = interner.intern("emptyList")
        listOfNotNullName = interner.intern("listOfNotNull")
        arrayOfName = interner.intern("arrayOf")
        emptyArrayName = interner.intern("emptyArray")
        intArrayOfName = interner.intern("intArrayOf")
        longArrayOfName = interner.intern("longArrayOf")
        shortArrayOfName = interner.intern("shortArrayOf")
        byteArrayOfName = interner.intern("byteArrayOf")
        uintArrayOfName = interner.intern("uintArrayOf")
        doubleArrayOfName = interner.intern("doubleArrayOf")
        floatArrayOfName = interner.intern("floatArrayOf")
        booleanArrayOfName = interner.intern("booleanArrayOf")
        charArrayOfName = interner.intern("charArrayOf")
        mapOfName = interner.intern("mapOf")
        mutableMapOfName = interner.intern("mutableMapOf")
        hashMapOfName = interner.intern("hashMapOf")
        linkedMapOfName = interner.intern("linkedMapOf")
        emptyMapName = interner.intern("emptyMap")
        setOfName = interner.intern("setOf")
        setOfNotNullName = interner.intern("setOfNotNull")
        mutableSetOfName = interner.intern("mutableSetOf")
        linkedSetOfName = interner.intern("linkedSetOf")
        hashSetOfName = interner.intern("hashSetOf")
        emptySetName = interner.intern("emptySet")

        arrayListName = interner.intern("ArrayList")
        hashMapName = interner.intern("HashMap")
        hashSetName = interner.intern("HashSet")
        linkedHashMapName = interner.intern("LinkedHashMap")
        linkedHashSetName = interner.intern("LinkedHashSet")

        kkListOfName = interner.intern("kk_list_of")
        kkListOfNotNullName = interner.intern("kk_list_of_not_null")
        kkEmptyListName = interner.intern("kk_emptyList")
        kkEmptyArrayName = interner.intern("kk_empty_array")
        kkEmptySetName = interner.intern("kk_emptySet")
        kkEmptyMapName = interner.intern("kk_emptyMap")
        kkListSizeName = interner.intern("kk_list_size")
        kkListGetName = interner.intern("kk_list_get")
        kkListContainsName = interner.intern("kk_list_contains")
        kkListContainsAllName = interner.intern("kk_list_containsAll")
        kkListBinarySearchName = interner.intern("kk_list_binarySearch")
        kkListBinarySearchCompareName = interner.intern("kk_list_binarySearch_compare")
        kkListIsEmptyName = interner.intern("kk_list_is_empty")
        kkListIteratorName = interner.intern("kk_list_iterator")
        kkListIteratorHasNextName = interner.intern("kk_list_iterator_hasNext")
        kkListIteratorNextName = interner.intern("kk_list_iterator_next")
        kkListIteratorHasPreviousName = interner.intern("kk_list_iterator_hasPrevious")
        kkListIteratorPreviousName = interner.intern("kk_list_iterator_previous")
        kkListToStringName = interner.intern("kk_list_to_string")
        kkSetOfName = interner.intern("kk_set_of")
        kkSetOfNotNullName = interner.intern("kk_set_of_not_null")
        kkSetSizeName = interner.intern("kk_set_size")
        kkSetContainsName = interner.intern("kk_set_contains")
        kkSetContainsAllName = interner.intern("kk_set_containsAll")
        kkSetIsEmptyName = interner.intern("kk_set_is_empty")
        kkSetToStringName = interner.intern("kk_set_to_string")
        kkSetMapName = interner.intern("kk_set_map")
        kkSetFilterName = interner.intern("kk_set_filter")
        kkSetForEachName = interner.intern("kk_set_forEach")
        kkSetToListName = interner.intern("kk_set_toList")
        kkSetFilterNotName = interner.intern("kk_set_filterNot")
        kkSetMapNotNullName = interner.intern("kk_set_mapNotNull")
        kkSetFlatMapName = interner.intern("kk_set_flatMap")
        kkSetAnyName = interner.intern("kk_set_any")
        kkSetNoneName = interner.intern("kk_set_none")
        kkSetAllName = interner.intern("kk_set_all")
        kkSetCountPredicateName = interner.intern("kk_set_count_predicate")
        kkStringSplitName = interner.intern("kk_string_split")
        kkStringChunkedName = interner.intern("kk_string_chunked")
        kkStringWindowedName = interner.intern("kk_string_windowed")
        kkStringAsSequenceName = interner.intern("kk_string_asSequence")
        kkStringAsIterableName = interner.intern("kk_string_asIterable")
        kkStringWindowedPartialName = interner.intern("kk_string_windowed_partial")
        kkStringIteratorName = interner.intern("kk_string_iterator")
        kkStringIteratorHasNextName = interner.intern("kk_string_iterator_hasNext")
        kkStringIteratorNextName = interner.intern("kk_string_iterator_next")
        kkStringFilterName = interner.intern("kk_string_filter")
        kkStringMapName = interner.intern("kk_string_map")
        kkStringCountName = interner.intern("kk_string_count")
        kkStringAnyName = interner.intern("kk_string_any")
        kkStringAllName = interner.intern("kk_string_all")
        kkStringNoneName = interner.intern("kk_string_none")

        kkListMapName = interner.intern("kk_list_map")
        kkListFilterName = interner.intern("kk_list_filter")
        kkListFilterNotName = interner.intern("kk_list_filterNot")
        kkListMapNotNullName = interner.intern("kk_list_mapNotNull")
        kkListFilterNotNullName = interner.intern("kk_list_filterNotNull")
        kkListFilterToName = interner.intern("kk_list_filterTo")
        kkListFilterNotToName = interner.intern("kk_list_filterNotTo")
        kkListMapToName = interner.intern("kk_list_mapTo")
        kkListFlatMapToName = interner.intern("kk_list_flatMapTo")
        kkListMapNotNullToName = interner.intern("kk_list_mapNotNullTo")
        kkListMapIndexedToName = interner.intern("kk_list_mapIndexedTo")
        kkListFlatMapIndexedToName = interner.intern("kk_list_flatMapIndexedTo")
        kkListAssociateToName = interner.intern("kk_list_associateTo")
        kkListFilterIsInstanceToName = interner.intern("kk_list_filterIsInstanceTo")
        kkListForEachName = interner.intern("kk_list_forEach")
        kkListFlatMapName = interner.intern("kk_list_flatMap")
        kkListAnyName = interner.intern("kk_list_any")
        kkListNoneName = interner.intern("kk_list_none")
        kkListAllName = interner.intern("kk_list_all")
        kkCollectionToCollectionName = interner.intern("kk_collection_toCollection")

        kkListFoldName = interner.intern("kk_list_fold")
        kkListFoldRightName = interner.intern("kk_list_foldRight")
        kkListReduceName = interner.intern("kk_list_reduce")
        kkListReduceRightName = interner.intern("kk_list_reduceRight")
        kkListReduceRightIndexedName = interner.intern("kk_list_reduceRightIndexed")
        kkListReduceRightIndexedOrNullName = interner.intern("kk_list_reduceRightIndexedOrNull")
        kkListReduceRightOrNullName = interner.intern("kk_list_reduceRightOrNull")
        kkListReduceOrNullName = interner.intern("kk_list_reduceOrNull")
        kkListScanName = interner.intern("kk_list_scan")
        kkListRunningFoldName = interner.intern("kk_list_runningFold")
        kkListRunningReduceName = interner.intern("kk_list_runningReduce")
        kkListScanReduceName = interner.intern("kk_list_scanReduce")
        kkListGroupByName = interner.intern("kk_list_groupBy")
        kkListGroupByTransformName = interner.intern("kk_list_groupByTransform")
        kkListSortedByName = interner.intern("kk_list_sortedBy")
        kkListAssociateByName = interner.intern("kk_list_associateBy")
        kkListAssociateWithName = interner.intern("kk_list_associateWith")
        kkListAssociateName = interner.intern("kk_list_associate")
        kkListAssociateByToName = interner.intern("kk_list_associateByTo")
        kkListAssociateWithToName = interner.intern("kk_list_associateWithTo")
        kkListGroupByToName = interner.intern("kk_list_groupByTo")
        kkListCountName = interner.intern("kk_list_count")
        kkListFirstName = interner.intern("kk_list_first")
        kkListLastName = interner.intern("kk_list_last")
        kkListFindName = interner.intern("kk_list_find")
        kkListZipName = interner.intern("kk_list_zip")
        kkListZipWithNextName = interner.intern("kk_list_zipWithNext")
        kkListZipWithNextTransformName = interner.intern("kk_list_zipWithNextTransform")
        kkListUnzipName = interner.intern("kk_list_unzip")
        kkListWithIndexName = interner.intern("kk_list_withIndex")
        kkIndexingIterableIteratorName = interner.intern("kk_indexing_iterable_iterator")
        kkIndexingIterableHasNextName = interner.intern("kk_indexing_iterable_hasNext")
        kkIndexingIterableNextName = interner.intern("kk_indexing_iterable_next")
        kkListForEachIndexedName = interner.intern("kk_list_forEachIndexed")
        kkListOnEachName = interner.intern("kk_list_onEach")
        kkListOnEachIndexedName = interner.intern("kk_list_onEachIndexed")
        kkListMapIndexedName = interner.intern("kk_list_mapIndexed")
        kkListFilterIndexedName = interner.intern("kk_list_filterIndexed")
        kkListFoldIndexedName = interner.intern("kk_list_foldIndexed")
        kkListFoldRightIndexedName = interner.intern("kk_list_foldRightIndexed")
        kkListReduceIndexedName = interner.intern("kk_list_reduceIndexed")
        kkListReduceIndexedOrNullName = interner.intern("kk_list_reduceIndexedOrNull")
        kkListRunningFoldIndexedName = interner.intern("kk_list_runningFoldIndexed")
        kkListRunningReduceIndexedName = interner.intern("kk_list_runningReduceIndexed")
        kkListScanIndexedName = interner.intern("kk_list_scanIndexed")
        kkListSumOfName = interner.intern("kk_list_sumOf")
        kkListSumByName = interner.intern("kk_list_sumBy")
        kkListSumByDoubleName = interner.intern("kk_list_sumByDouble")
        kkListMaxOrNullName = interner.intern("kk_list_maxOrNull")
        kkListMinOrNullName = interner.intern("kk_list_minOrNull")
        kkListMaxByOrNullName = interner.intern("kk_list_maxByOrNull")
        kkListMinByOrNullName = interner.intern("kk_list_minByOrNull")
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
        kkListTakeName = interner.intern("kk_list_take")
        kkListDropName = interner.intern("kk_list_drop")
        kkListSumName = interner.intern("kk_list_sum")
        kkListReversedName = interner.intern("kk_list_reversed")
        kkListAsReversedName = interner.intern("kk_list_as_reversed")
        kkListSortedName = interner.intern("kk_list_sorted")
        kkSetSortedName = interner.intern("kk_set_sorted")
        kkListDistinctName = interner.intern("kk_list_distinct")
        kkListDistinctByName = interner.intern("kk_list_distinctBy")
        kkListShuffledName = interner.intern("kk_list_shuffled")
        kkListShuffledRandomName = interner.intern("kk_list_shuffled_random")
        kkListPlusElementName = interner.intern("kk_list_plus_element")
        kkListPlusCollectionName = interner.intern("kk_list_plus_collection")
        kkListMinusElementName = interner.intern("kk_list_minus_element")
        kkListMinusCollectionName = interner.intern("kk_list_minus_collection")
        kkListRandomName = interner.intern("kk_list_random")
        kkListRandomOrNullName = interner.intern("kk_list_randomOrNull")
        kkListFlattenName = interner.intern("kk_list_flatten")
        kkListIndexOfName = interner.intern("kk_list_indexOf")
        kkListLastIndexOfName = interner.intern("kk_list_lastIndexOf")
        kkListIndexOfFirstName = interner.intern("kk_list_indexOfFirst")
        kkListIndexOfLastName = interner.intern("kk_list_indexOfLast")
        kkListChunkedName = interner.intern("kk_list_chunked")
        kkListChunkedTransformName = interner.intern("kk_list_chunked_transform")
        kkListWindowedDefaultName = interner.intern("kk_list_windowed_default")
        kkListWindowedName = interner.intern("kk_list_windowed")
        kkListWindowedPartialName = interner.intern("kk_list_windowed_partial")
        kkListWindowedTransformName = interner.intern("kk_list_windowed_transform")
        kkListSortedDescendingName = interner.intern("kk_list_sortedDescending")
        kkListSortedByDescendingName = interner.intern("kk_list_sortedByDescending")
        kkListSortedWithName = interner.intern("kk_list_sortedWith")
        kkListPartitionName = interner.intern("kk_list_partition")
        kkListTakeWhileName = interner.intern("kk_list_takeWhile")
        kkListDropWhileName = interner.intern("kk_list_dropWhile")
        kkListTakeLastWhileName = interner.intern("kk_list_takeLastWhile")
        kkListDropLastWhileName = interner.intern("kk_list_dropLastWhile")

        kkComparatorFromSelectorName = interner.intern("kk_comparator_from_selector")
        kkComparatorFromSelectorDescendingName = interner.intern("kk_comparator_from_selector_descending")
        kkComparatorFromSelectorTrampolineName = interner.intern("kk_comparator_from_selector_trampoline")
        kkComparatorFromSelectorDescendingTrampolineName = interner.intern("kk_comparator_from_selector_descending_trampoline")
        kkComparatorFromMultiSelectorsName = interner.intern("kk_comparator_from_multi_selectors")
        kkComparatorFromMultiSelectors3Name = interner.intern("kk_comparator_from_multi_selectors3")
        kkComparatorFromMultiSelectorsVarargName = interner.intern("kk_comparator_from_multi_selectors_vararg")
        kkComparatorFromMultiSelectorsTrampolineName = interner.intern("kk_comparator_from_multi_selectors_trampoline")
        kkComparatorNaturalOrderName = interner.intern("kk_comparator_natural_order")
        kkComparatorReverseOrderName = interner.intern("kk_comparator_reverse_order")
        kkComparatorNaturalOrderTrampolineName = interner.intern("kk_comparator_natural_order_trampoline")
        kkComparatorReverseOrderTrampolineName = interner.intern("kk_comparator_reverse_order_trampoline")
        kkComparatorThenByName = interner.intern("kk_comparator_then_by")
        kkComparatorThenByDescendingName = interner.intern("kk_comparator_then_by_descending")
        kkComparatorThenDescendingName = interner.intern("kk_comparator_then_descending")
        kkComparatorThenComparatorName = interner.intern("kk_comparator_then_comparator")
        kkComparatorThenByTrampolineName = interner.intern("kk_comparator_then_by_trampoline")
        kkComparatorThenByDescendingTrampolineName = interner.intern("kk_comparator_then_by_descending_trampoline")
        kkComparatorThenDescendingTrampolineName = interner.intern("kk_comparator_then_descending_trampoline")
        kkComparatorThenComparatorTrampolineName = interner.intern("kk_comparator_then_comparator_trampoline")
        kkComparatorNullsFirstName = interner.intern("kk_comparator_nulls_first")
        kkComparatorNullsLastName = interner.intern("kk_comparator_nulls_last")
        kkComparatorNullsFirstTrampolineName = interner.intern("kk_comparator_nulls_first_trampoline")
        kkComparatorNullsLastTrampolineName = interner.intern("kk_comparator_nulls_last_trampoline")
        kkComparatorReversedName = interner.intern("kk_comparator_reversed")
        kkComparatorReversedTrampolineName = interner.intern("kk_comparator_reversed_trampoline")
        kkCompareValuesName = interner.intern("kk_compareValues")
        kkCompareValuesBy1Name = interner.intern("kk_compareValuesBy1")
        kkCompareValuesByName = interner.intern("kk_compareValuesBy")
        kkCompareValuesBy3Name = interner.intern("kk_compareValuesBy3")

        kkSequenceFromListName = interner.intern("kk_sequence_from_list")
        kkSequenceMapName = interner.intern("kk_sequence_map")
        kkSequenceFilterName = interner.intern("kk_sequence_filter")
        kkSequenceTakeName = interner.intern("kk_sequence_take")
        kkSequenceToListName = interner.intern("kk_sequence_to_list")
        kkSequenceConstrainOnceName = interner.intern("kk_sequence_constrainOnce")
        kkSequenceBuilderBuildName = interner.intern("kk_sequence_builder_build")
        kkSequenceBuilderYieldName = interner.intern("kk_sequence_builder_yield")
        kkSequenceBuilderYieldAllName = interner.intern("kk_sequence_builder_yieldAll")
        kkIteratorBuilderBuildName = interner.intern("kk_iterator_builder_build")
        kkIteratorBuilderYieldName = interner.intern("kk_iterator_builder_yield")
        kkIteratorBuilderHasNextName = interner.intern("kk_iterator_builder_hasNext")
        kkIteratorBuilderNextName = interner.intern("kk_iterator_builder_next")

        kkSequenceOfName = interner.intern("kk_sequence_of")
        kkSequenceGenerateName = interner.intern("kk_sequence_generate")
        kkSequenceGenerateNoArgName = interner.intern("kk_sequence_generate_noarg")
        kkSequenceForEachName = interner.intern("kk_sequence_forEach")
        kkSequenceFlatMapName = interner.intern("kk_sequence_flatMap")
        kkSequenceFlatMapIndexedName = interner.intern("kk_sequence_flatMapIndexed")
        kkSequenceDropName = interner.intern("kk_sequence_drop")
        kkSequenceDistinctName = interner.intern("kk_sequence_distinct")
        kkSequenceZipName = interner.intern("kk_sequence_zip")

        kkSequenceSortedName = interner.intern("kk_sequence_sorted")
        kkSequenceSortedByName = interner.intern("kk_sequence_sortedBy")
        kkSequenceSortedDescendingName = interner.intern("kk_sequence_sortedDescending")
        kkSequenceShuffledName = interner.intern("kk_sequence_shuffled")
        kkSequenceShuffledRandomName = interner.intern("kk_sequence_shuffled_random")
        kkSequenceMapNotNullName = interner.intern("kk_sequence_mapNotNull")
        kkSequenceFilterNotNullName = interner.intern("kk_sequence_filterNotNull")
        kkSequenceMapIndexedName = interner.intern("kk_sequence_mapIndexed")
        kkSequenceWithIndexName = interner.intern("kk_sequence_withIndex")
        kkSequenceJoinToStringName = interner.intern("kk_sequence_joinToString")
        kkSequenceSumOfName = interner.intern("kk_sequence_sumOf")
        kkSequenceAssociateName = interner.intern("kk_sequence_associate")
        kkSequenceAssociateByName = interner.intern("kk_sequence_associateBy")
        kkSequenceAssociateToName = interner.intern("kk_sequence_associateTo")
        kkSequenceAssociateByToName = interner.intern("kk_sequence_associateByTo")
        kkSequenceAssociateWithToName = interner.intern("kk_sequence_associateWithTo")
        kkSequenceChunkedName = interner.intern("kk_sequence_chunked")
        kkSequenceWindowedName = interner.intern("kk_sequence_windowed")
        kkSequenceOnEachName = interner.intern("kk_sequence_onEach")
        kkEmptySequenceName = interner.intern("kk_empty_sequence")
        kkSequenceIfEmptyName = interner.intern("kk_sequence_ifEmpty")
        kkSequenceForEachIndexedName = interner.intern("kk_sequence_forEachIndexed")
        kkSequenceZipWithNextName = interner.intern("kk_sequence_zipWithNext")
        kkSequenceZipWithNextTransformName = interner.intern("kk_sequence_zipWithNextTransform")
        kkSequenceFirstName = interner.intern("kk_sequence_first")
        kkSequenceFirstOrNullName = interner.intern("kk_sequence_firstOrNull")
        kkSequenceLastName = interner.intern("kk_sequence_last")
        kkSequenceCountName = interner.intern("kk_sequence_count")

        kkSequenceScanName = interner.intern("kk_sequence_scan")
        kkSequenceRunningFoldName = interner.intern("kk_sequence_runningFold")
        kkSequenceRunningReduceName = interner.intern("kk_sequence_runningReduce")

        kkSequenceToSetName = interner.intern("kk_sequence_toSet")
        kkSequenceToMapName = interner.intern("kk_sequence_toMap")
        kkSequenceToCollectionName = interner.intern("kk_sequence_toCollection")
        kkSequenceGroupByName = interner.intern("kk_sequence_groupBy")
        kkSequenceGroupByToName = interner.intern("kk_sequence_groupByTo")
        kkSequenceMaxOrNullName = interner.intern("kk_sequence_maxOrNull")
        kkSequenceMinOrNullName = interner.intern("kk_sequence_minOrNull")
        kkSequenceFlattenName = interner.intern("kk_sequence_flatten")
        kkSequenceFoldName = interner.intern("kk_sequence_fold")
        kkSequenceFoldIndexedName = interner.intern("kk_sequence_foldIndexed")
        kkSequenceRunningFoldIndexedName = interner.intern("kk_sequence_runningFoldIndexed")
        kkSequenceReduceIndexedName = interner.intern("kk_sequence_reduceIndexed")
        kkSequenceReduceIndexedOrNullName = interner.intern("kk_sequence_reduceIndexedOrNull")
        kkSequenceRunningReduceIndexedName = interner.intern("kk_sequence_runningReduceIndexed")

        kkSequencePlusName = interner.intern("kk_sequence_plus")
        kkSequencePlusElementName = interner.intern("kk_sequence_plus_element")
        kkSequenceMinusName = interner.intern("kk_sequence_minus")
        kkSequenceOfSingleName = interner.intern("kk_sequence_of_single")
        kkSequencePartitionName = interner.intern("kk_sequence_partition")

        // STDLIB-SEQ-021: Sequence destination-collection filter operations
        kkSequenceFilterToName = interner.intern("kk_sequence_filterTo")
        kkSequenceFilterNotToName = interner.intern("kk_sequence_filterNotTo")
        kkSequenceMapToName = interner.intern("kk_sequence_mapTo")
        kkSequenceMapIndexedNotNullToName = interner.intern("kk_sequence_mapIndexedNotNullTo")
        kkSequenceFilterIndexedToName = interner.intern("kk_sequence_filterIndexedTo")
        kkSequenceFilterNotNullToName = interner.intern("kk_sequence_filterNotNullTo")
        kkSequenceFilterIsInstanceToName = interner.intern("kk_sequence_filterIsInstanceTo")

        kkMapOfName = interner.intern("kk_map_of")
        kkMapSizeName = interner.intern("kk_map_size")
        kkMapGetName = interner.intern("kk_map_get")
        kkMapContainsKeyName = interner.intern("kk_map_contains_key")
        kkMapContainsValueName = interner.intern("kk_map_contains_value")
        kkMapIsEmptyName = interner.intern("kk_map_is_empty")
        kkMapForEachName = interner.intern("kk_map_forEach")
        kkMapMapName = interner.intern("kk_map_map")
        kkMapFilterName = interner.intern("kk_map_filter")
        kkMapFilterNotName = interner.intern("kk_map_filterNot")
        kkMapFilterKeysName = interner.intern("kk_map_filterKeys")
        kkMapFilterValuesName = interner.intern("kk_map_filterValues")
        kkMapMapValuesName = interner.intern("kk_map_mapValues")
        kkMapMapKeysName = interner.intern("kk_map_mapKeys")
        kkMapMapNotNullName = interner.intern("kk_map_mapNotNull")
        kkMapCountName = interner.intern("kk_map_count")
        kkMapAnyName = interner.intern("kk_map_any")
        kkMapAllName = interner.intern("kk_map_all")
        kkMapNoneName = interner.intern("kk_map_none")
        kkMapFlatMapName = interner.intern("kk_map_flatMap")
        kkMapMaxByOrNullName = interner.intern("kk_map_maxByOrNull")
        kkMapMinByOrNullName = interner.intern("kk_map_minByOrNull")
        kkMapToListName = interner.intern("kk_map_toList")
        kkMapToStringName = interner.intern("kk_map_to_string")
        kkMapIteratorName = interner.intern("kk_map_iterator")
        kkMapIteratorHasNextName = interner.intern("kk_map_iterator_hasNext")
        kkMapIteratorNextName = interner.intern("kk_map_iterator_next")
        kkMutableMapPutAllName = interner.intern("kk_mutable_map_putAll")
        kkMapKeysName = interner.intern("kk_map_keys")
        kkMapValuesName = interner.intern("kk_map_values")
        kkMapEntriesName = interner.intern("kk_map_entries")

        kkArraySizeName = interner.intern("kk_array_size")
        kkArrayNewName = interner.intern("kk_array_new")
        kkArraySetName = interner.intern("kk_array_set")

        kkArrayToListName = interner.intern("kk_array_toList")
        kkArrayToMutableListName = interner.intern("kk_array_toMutableList")
        kkListToTypedArrayName = interner.intern("kk_list_toTypedArray")
        kkListToIntArrayName = interner.intern("kk_list_toIntArray")
        kkListToLongArrayName = interner.intern("kk_list_toLongArray")
        kkListToByteArrayName = interner.intern("kk_list_toByteArray")
        kkListToUByteArrayName = interner.intern("kk_list_toUByteArray")
        kkListToUShortArrayName = interner.intern("kk_list_toUShortArray")
        kkListToUIntArrayName = interner.intern("kk_list_toUIntArray")
        kkListToULongArrayName = interner.intern("kk_list_toULongArray")
        kkArrayMapName = interner.intern("kk_array_map")
        kkArrayFilterName = interner.intern("kk_array_filter")
        kkArrayForEachName = interner.intern("kk_array_forEach")
        kkArrayAnyName = interner.intern("kk_array_any")
        kkArrayNoneName = interner.intern("kk_array_none")
        kkArrayCopyOfName = interner.intern("kk_array_copyOf")
        kkArrayCopyOfNewSizeName = interner.intern("kk_array_copyOf_newSize")
        kkArrayCopyOfNewSizeInitName = interner.intern("kk_array_copyOf_newSize_init")
        kkArrayCopyOfRangeName = interner.intern("kk_array_copyOfRange")
        kkArrayFillName = interner.intern("kk_array_fill")
        kkListAsSequenceName = interner.intern("kk_list_asSequence")
        kkArrayAsSequenceName = interner.intern("kk_array_asSequence")

        kkRangeIteratorName = interner.intern("kk_range_iterator")
        kkRangeHasNextName = interner.intern("kk_range_hasNext")
        kkRangeNextName = interner.intern("kk_range_next")

        kkOpRangeToName = interner.intern("kk_op_rangeTo")
        kkOpRangeUntilName = interner.intern("kk_op_rangeUntil")
        kkOpULongRangeUntilName = interner.intern("kk_op_ulong_rangeUntil")
        kkOpDownToName = interner.intern("kk_op_downTo")
        kkOpStepName = interner.intern("kk_op_step")
        kkRangeFirstName = interner.intern("kk_range_first")
        kkRangeLastName = interner.intern("kk_range_last")
        kkRangeEndExclusiveName = interner.intern("kk_range_endExclusive")
        kkRangeCountName = interner.intern("kk_range_count")
        kkRangeToListName = interner.intern("kk_range_toList")
        kkRangeForEachName = interner.intern("kk_range_forEach")
        kkRangeMapName = interner.intern("kk_range_map")
        kkRangeMapIndexedName = interner.intern("kk_range_mapIndexed")
        kkRangeMapNotNullName = interner.intern("kk_range_mapNotNull")
        kkRangeFilterName = interner.intern("kk_range_filter")
        kkRangeFilterIndexedName = interner.intern("kk_range_filterIndexed")
        kkRangeFilterNotName = interner.intern("kk_range_filterNot")
        kkRangeReduceName = interner.intern("kk_range_reduce")
        kkRangeReduceIndexedName = interner.intern("kk_range_reduceIndexed")
        kkRangeFoldName = interner.intern("kk_range_fold")
        kkRangeFoldIndexedName = interner.intern("kk_range_foldIndexed")
        kkRangeFindName = interner.intern("kk_range_find")
        kkRangeFindLastName = interner.intern("kk_range_findLast")
        kkRangeFirstPredicateName = interner.intern("kk_range_first_predicate")
        kkRangeFirstOrNullPredicateName = interner.intern("kk_range_firstOrNull_predicate")
        kkRangeLastPredicateName = interner.intern("kk_range_last_predicate")
        kkRangeLastOrNullPredicateName = interner.intern("kk_range_lastOrNull_predicate")
        kkRangeAnyName = interner.intern("kk_range_any")
        kkRangeAllName = interner.intern("kk_range_all")
        kkRangeNoneName = interner.intern("kk_range_none")
        kkRangeChunkedName = interner.intern("kk_range_chunked")
        kkRangeWindowedName = interner.intern("kk_range_windowed")
        kkRangeStepName = interner.intern("kk_range_step")
        kkRangeReversedName = interner.intern("kk_range_reversed")
        kkRangeIsEmptyName = interner.intern("kk_range_isEmpty")
        kkRangeSumName = interner.intern("kk_range_sum")
        kkRangeToIntArrayName = interner.intern("kk_range_toIntArray")
        kkRangeTakeName = interner.intern("kk_range_take")
        kkRangeDropName = interner.intern("kk_range_drop")
        kkRangeAverageName = interner.intern("kk_range_average")
        kkRangeSortedName = interner.intern("kk_range_sorted")
        kkOpContainsName = interner.intern("kk_op_contains")

        sumName = interner.intern("sum")

        // CharRange (STDLIB-290)
        kkBoxCharName = interner.intern("kk_box_char")
        kkCharRangeToListName = interner.intern("kk_char_range_toList")
        kkCharRangeForEachName = interner.intern("kk_char_range_forEach")

        // ULongRange (STDLIB-524, STDLIB-RANGE-037)
        kkULongRangeToListName = interner.intern("kk_ulong_range_toList")
        kkULongRangeContainsName = interner.intern("kk_ulong_range_contains")
        kkULongRangeFirstName = interner.intern("kk_ulong_range_first")
        kkULongRangeLastName = interner.intern("kk_ulong_range_last")
        kkULongRangeStepName = interner.intern("kk_ulong_range_step")
        kkULongRangeIsEmptyName = interner.intern("kk_ulong_range_isEmpty")
        kkULongRangeReversedName = interner.intern("kk_ulong_range_reversed")
        kkULongRangeToULongArrayName = interner.intern("kk_ulong_range_toULongArray")
        kkULongRangeCountName = interner.intern("kk_ulong_range_count")
        kkULongRangeIteratorName = interner.intern("kk_ulong_range_iterator")
        kkULongRangeHasNextName = interner.intern("kk_ulong_range_hasNext")
        kkULongRangeNextName = interner.intern("kk_ulong_range_next")
        kkULongRangeForEachName = interner.intern("kk_ulong_range_forEach")
        kkULongRangeMapName = interner.intern("kk_ulong_range_map")

        sizeName = interner.intern("size")
        getName = interner.intern("get")
        containsName = interner.intern("contains")
        containsAllName = interner.intern("containsAll")
        containsKeyName = interner.intern("containsKey")
        containsValueName = interner.intern("containsValue")
        isEmptyName = interner.intern("isEmpty")
        countName = interner.intern("count")
        addName = interner.intern("add")
        removeName = interner.intern("remove")
        firstName = interner.intern("first")
        lastName = interner.intern("last")
        startName = interner.intern("start")
        endInclusiveName = interner.intern("endInclusive")
        endExclusiveName = interner.intern("endExclusive")
        stepName = interner.intern("step")
        iteratorName = interner.intern("iterator")

        // ListIterator member names (STDLIB-538)
        listIteratorMemberName = interner.intern("listIterator")
        hasPreviousName = interner.intern("hasPrevious")
        previousName = interner.intern("previous")

        mapName = interner.intern("map")
        filterName = interner.intern("filter")
        filterNotName = interner.intern("filterNot")
        mapNotNullName = interner.intern("mapNotNull")
        filterNotNullName = interner.intern("filterNotNull")
        filterToName = interner.intern("filterTo")
        filterNotToName = interner.intern("filterNotTo")
        mapToName = interner.intern("mapTo")
        flatMapToName = interner.intern("flatMapTo")
        mapNotNullToName = interner.intern("mapNotNullTo")
        mapIndexedToName = interner.intern("mapIndexedTo")
        mapIndexedNotNullToName = interner.intern("mapIndexedNotNullTo")
        flatMapIndexedToName = interner.intern("flatMapIndexedTo")
        filterIsInstanceToName = interner.intern("filterIsInstanceTo")
        filterIndexedToName = interner.intern("filterIndexedTo")
        filterNotNullToName = interner.intern("filterNotNullTo")
        forEachName = interner.intern("forEach")
        flatMapName = interner.intern("flatMap")
        flatMapIndexedName = interner.intern("flatMapIndexed")
        anyName = interner.intern("any")
        noneName = interner.intern("none")
        allName = interner.intern("all")

        foldName = interner.intern("fold")
        foldRightName = interner.intern("foldRight")
        reduceName = interner.intern("reduce")
        reduceRightName = interner.intern("reduceRight")
        reduceOrNullName = interner.intern("reduceOrNull")
        scanName = interner.intern("scan")
        runningFoldName = interner.intern("runningFold")
        runningReduceName = interner.intern("runningReduce")
        scanReduceName = interner.intern("scanReduce")
        groupByName = interner.intern("groupBy")
        sortedByName = interner.intern("sortedBy")
        findName = interner.intern("find")
        findLastName = interner.intern("findLast")
        associateByName = interner.intern("associateBy")
        associateWithName = interner.intern("associateWith")
        associateName = interner.intern("associate")
        associateToName = interner.intern("associateTo")
        associateByToName = interner.intern("associateByTo")
        associateWithToName = interner.intern("associateWithTo")
        groupByToName = interner.intern("groupByTo")
        mapValuesName = interner.intern("mapValues")
        mapKeysName = interner.intern("mapKeys")
        filterKeysName = interner.intern("filterKeys")
        filterValuesName = interner.intern("filterValues")
        zipName = interner.intern("zip")
        zipWithNextName = interner.intern("zipWithNext")
        unzipName = interner.intern("unzip")
        withIndexName = interner.intern("withIndex")
        forEachIndexedName = interner.intern("forEachIndexed")
        onEachName = interner.intern("onEach")
        onEachIndexedName = interner.intern("onEachIndexed")
        mapIndexedName = interner.intern("mapIndexed")
        foldIndexedName = interner.intern("foldIndexed")
        foldRightIndexedName = interner.intern("foldRightIndexed")
        reduceRightIndexedName = interner.intern("reduceRightIndexed")
        reduceRightIndexedOrNullName = interner.intern("reduceRightIndexedOrNull")
        reduceRightOrNullName = interner.intern("reduceRightOrNull")
        reduceIndexedName = interner.intern("reduceIndexed")
        filterIndexedName = interner.intern("filterIndexed")
        reduceIndexedOrNullName = interner.intern("reduceIndexedOrNull")
        runningFoldIndexedName = interner.intern("runningFoldIndexed")
        runningReduceIndexedName = interner.intern("runningReduceIndexed")
        scanIndexedName = interner.intern("scanIndexed")
        sumOfName = interner.intern("sumOf")
        sumByName = interner.intern("sumBy")
        sumByDoubleName = interner.intern("sumByDouble")
        maxOrNullName = interner.intern("maxOrNull")
        minOrNullName = interner.intern("minOrNull")
        maxByOrNullName = interner.intern("maxByOrNull")
        minByOrNullName = interner.intern("minByOrNull")
        maxOfOrNullName = interner.intern("maxOfOrNull")
        minOfOrNullName = interner.intern("minOfOrNull")
        maxOfName = interner.intern("maxOf")
        minOfName = interner.intern("minOf")
        maxWithName = interner.intern("maxWith")
        maxWithOrNullName = interner.intern("maxWithOrNull")
        minWithName = interner.intern("minWith")
        minWithOrNullName = interner.intern("minWithOrNull")
        maxOfWithName = interner.intern("maxOfWith")
        maxOfWithOrNullName = interner.intern("maxOfWithOrNull")
        minOfWithName = interner.intern("minOfWith")
        minOfWithOrNullName = interner.intern("minOfWithOrNull")
        dropName = interner.intern("drop")
        reversedName = interner.intern("reversed")
        asReversedName = interner.intern("asReversed")
        sortedName = interner.intern("sorted")
        averageName = interner.intern("average")
        distinctName = interner.intern("distinct")
        distinctByName = interner.intern("distinctBy")
        shuffledName = interner.intern("shuffled")
        flattenName = interner.intern("flatten")
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
        takeWhileName = interner.intern("takeWhile")
        dropWhileName = interner.intern("dropWhile")
        takeLastWhileName = interner.intern("takeLastWhile")
        dropLastWhileName = interner.intern("dropLastWhile")
        firstOrNullName = interner.intern("firstOrNull")
        lastOrNullName = interner.intern("lastOrNull")

        toMutableListName = interner.intern("toMutableList")
        toTypedArrayName = interner.intern("toTypedArray")
        copyOfName = interner.intern("copyOf")
        copyOfRangeName = interner.intern("copyOfRange")
        fillName = interner.intern("fill")

        plusMemberName = interner.intern("plus")
        plusElementName = interner.intern("plusElement")
        minusElementName = interner.intern("minusElement")
        minusMemberName = interner.intern("minus")

        asSequenceName = interner.intern("asSequence")
        toListName = interner.intern("toList")
        constrainOnceName = interner.intern("constrainOnce")
        toCollectionName = interner.intern("toCollection")
        toUByteArrayName = interner.intern("toUByteArray")
        toUShortArrayName = interner.intern("toUShortArray")
        toUIntArrayName = interner.intern("toUIntArray")
        toULongArrayName = interner.intern("toULongArray")
        toIntArrayName = interner.intern("toIntArray")
        toLongArrayName = interner.intern("toLongArray")
        toByteArrayName = interner.intern("toByteArray")
        kkLongRangeToLongArrayName = interner.intern("kk_long_range_toLongArray")
        toSetName = interner.intern("toSet")
        toMapName = interner.intern("toMap")
        takeName = interner.intern("take")
        sequenceName = interner.intern("sequence")
        iteratorBuilderName = interner.intern("iterator")
        iteratorBuilderFQName = [interner.intern("kotlin"), interner.intern("sequences"), interner.intern("iterator")]
        let kotlinCollectionsPkg = [interner.intern("kotlin"), interner.intern("collections")]
        emptyListFQName = kotlinCollectionsPkg + [interner.intern("emptyList")]
        emptyArrayFQName = [interner.intern("kotlin")] + [interner.intern("emptyArray")]
        emptySetFQName = kotlinCollectionsPkg + [interner.intern("emptySet")]
        emptyMapFQName = kotlinCollectionsPkg + [interner.intern("emptyMap")]
        listOfFQName = kotlinCollectionsPkg + [interner.intern("listOf")]
        setOfFQName = kotlinCollectionsPkg + [interner.intern("setOf")]
        setOfNotNullFQName = kotlinCollectionsPkg + [interner.intern("setOfNotNull")]
        mapOfFQName = kotlinCollectionsPkg + [interner.intern("mapOf")]
        mutableListOfFQName = kotlinCollectionsPkg + [interner.intern("mutableListOf")]
        arrayListOfFQName = kotlinCollectionsPkg + [interner.intern("arrayListOf")]
        mutableSetOfFQName = kotlinCollectionsPkg + [interner.intern("mutableSetOf")]
        linkedSetOfFQName = kotlinCollectionsPkg + [interner.intern("linkedSetOf")]
        hashSetOfFQName = kotlinCollectionsPkg + [interner.intern("hashSetOf")]
        mutableMapOfFQName = kotlinCollectionsPkg + [interner.intern("mutableMapOf")]
        hashMapOfFQName = kotlinCollectionsPkg + [interner.intern("hashMapOf")]
        linkedMapOfFQName = kotlinCollectionsPkg + [interner.intern("linkedMapOf")]
        listOfNotNullFQName = kotlinCollectionsPkg + [interner.intern("listOfNotNull")]
        yieldName = interner.intern("yield")
        yieldAllName = interner.intern("yieldAll")

        sequenceOfName = interner.intern("sequenceOf")
        generateSequenceName = interner.intern("generateSequence")

        printlnName = interner.intern("println")
        kkPrintlnAnyName = interner.intern("kk_println_any")
        kkAnyToStringName = interner.intern("kk_any_to_string")
        kotlinName = interner.intern("kotlin")
        initName = interner.intern("<init>")

        toName = interner.intern("to")
        pairName = interner.intern("Pair")
        kkPairNewName = interner.intern("kk_pair_new")
        kkPairFirstName = interner.intern("kk_pair_first")
        kkPairSecondName = interner.intern("kk_pair_second")

        tripleName = interner.intern("Triple")
        kkTripleNewName = interner.intern("kk_triple_new")

        buildStringName = interner.intern("buildString")
        buildListName = interner.intern("buildList")
        buildSetName = interner.intern("buildSet")
        buildMapName = interner.intern("buildMap")
        kkBuildStringName = interner.intern("kk_build_string")
        kkBuildStringWithCapacityName = interner.intern("kk_build_string_with_capacity")
        kkBuildListName = interner.intern("kk_build_list")
        kkBuildListWithCapacityName = interner.intern("kk_build_list_with_capacity")
        kkBuildSetName = interner.intern("kk_build_set")
        kkBuildMapName = interner.intern("kk_build_map")

        appendName = interner.intern("append")
        addAllName = interner.intern("addAll")
        putName = interner.intern("put")
        kkStringBuilderAppendName = interner.intern("kk_string_builder_append")
        kkBuilderListAddName = interner.intern("kk_builder_list_add")
        kkBuilderListAddAllName = interner.intern("kk_builder_list_addAll")
        kkBuilderSetAddName = interner.intern("kk_builder_set_add")
        kkBuilderSetAddAllName = interner.intern("kk_builder_set_addAll")
        kkBuilderMapPutName = interner.intern("kk_builder_map_put")
        kkMutableSetAddName = interner.intern("kk_mutable_set_add")
        kkMutableSetRemoveName = interner.intern("kk_mutable_set_remove")
        kkMutableMapPutName = interner.intern("kk_mutable_map_put")

        // StringBuilder enhancements (STDLIB-311)
        appendLineName = interner.intern("appendLine")
        insertName = interner.intern("insert")
        deleteName = interner.intern("delete")
        lengthName = interner.intern("length")
        appendRangeName = interner.intern("appendRange")
        kkStringBuilderAppendLineName = interner.intern("kk_string_builder_append_line")
        kkStringBuilderAppendLineNoargName = interner.intern("kk_string_builder_append_line_noarg")
        kkStringBuilderInsertName = interner.intern("kk_string_builder_insert")
        kkStringBuilderDeleteName = interner.intern("kk_string_builder_delete")
        kkStringBuilderLengthName = interner.intern("kk_string_builder_length")
        kkStringBuilderAppendRangeName = interner.intern("kk_string_builder_append_range")

        // File I/O names (STDLIB-565)
        fileConstructorName = interner.intern("File")
        kkFileNewName = interner.intern("kk_file_new")
        readTextName = interner.intern("readText")
        kkFileReadTextName = interner.intern("kk_file_readText")
        writeTextName = interner.intern("writeText")
        kkFileWriteTextName = interner.intern("kk_file_writeText")
        appendTextName = interner.intern("appendText")
        kkFileAppendTextName = interner.intern("kk_file_appendText")
        readLinesName = interner.intern("readLines")
        kkFileReadLinesName = interner.intern("kk_file_readLines")
        existsName = interner.intern("exists")
        kkFileExistsName = interner.intern("kk_file_exists")
        isFileName = interner.intern("isFile")
        kkFileIsFileName = interner.intern("kk_file_isFile")
        isDirectoryName = interner.intern("isDirectory")
        kkFileIsDirectoryName = interner.intern("kk_file_isDirectory")
        namePropertyName = interner.intern("name")
        kkFileNameName = interner.intern("kk_file_name")
        pathPropertyName = interner.intern("path")
        kkFilePathName = interner.intern("kk_file_path")
        forEachLineName = interner.intern("forEachLine")
        kkFileForEachLineName = interner.intern("kk_file_forEachLine")
        useLinesName = interner.intern("useLines")
        kkFileUseLinesName = interner.intern("kk_file_useLines")
        bufferedReaderName = interner.intern("bufferedReader")
        kkFileBufferedReaderName = interner.intern("kk_file_bufferedReader")
        bufferedWriterName = interner.intern("bufferedWriter")
        kkFileBufferedWriterName = interner.intern("kk_file_bufferedWriter")
        kkBufferedWriterWriteName = interner.intern("kk_buffered_writer_write")
        kkBufferedWriterNewLineName = interner.intern("kk_buffered_writer_new_line")
        kkBufferedWriterFlushName = interner.intern("kk_buffered_writer_flush")
        kkBufferedWriterCloseName = interner.intern("kk_buffered_writer_close")
        kkFileDeleteName = interner.intern("kk_file_delete")
        mkdirsName = interner.intern("mkdirs")
        kkFileMkdirsName = interner.intern("kk_file_mkdirs")
        listFilesName = interner.intern("listFiles")
        kkFileListFilesName = interner.intern("kk_file_listFiles")
        walkName = interner.intern("walk")
        kkFileWalkName = interner.intern("kk_file_walk")
        readBytesName = interner.intern("readBytes")
        kkFileReadBytesName = interner.intern("kk_file_readBytes")
        // STDLIB-IO-087: Additional File operations
        absolutePathName = interner.intern("absolutePath")
        kkFileAbsolutePathName = interner.intern("kk_file_absolutePath")
        canonicalPathName = interner.intern("canonicalPath")
        kkFileCanonicalPathName = interner.intern("kk_file_canonicalPath")
        parentName = interner.intern("parent")
        kkFileParentName = interner.intern("kk_file_parent")
        // lengthName already initialized in StringBuilder section above
        kkFileLengthName = interner.intern("kk_file_length")
        lastModifiedName = interner.intern("lastModified")
        kkFileLastModifiedName = interner.intern("kk_file_lastModified")
        createNewFileName = interner.intern("createNewFile")
        kkFileCreateNewFileName = interner.intern("kk_file_createNewFile")
        canReadName = interner.intern("canRead")
        kkFileCanReadName = interner.intern("kk_file_canRead")
        canWriteName = interner.intern("canWrite")
        kkFileCanWriteName = interner.intern("kk_file_canWrite")
        canExecuteName = interner.intern("canExecute")
        kkFileCanExecuteName = interner.intern("kk_file_canExecute")
        kkFileNewParentChildName = interner.intern("kk_file_new_parent_child")

        listFactoryNames = [listOfName, mutableListOfName, arrayListOfName, emptyListName, listOfNotNullName]
        setFactoryNames = [setOfName, setOfNotNullName, mutableSetOfName, hashSetOfName, linkedSetOfName, emptySetName]
        mapFactoryNames = [mapOfName, mutableMapOfName, hashMapOfName, linkedMapOfName, emptyMapName]
        mutableListConstructorNames = [arrayListName]
        mutableSetConstructorNames = [hashSetName, linkedHashSetName]
        mutableMapConstructorNames = [hashMapName, linkedHashMapName]
        arrayOfFactoryNames = [arrayOfName, emptyArrayName, intArrayOfName, longArrayOfName, shortArrayOfName, byteArrayOfName, uintArrayOfName, doubleArrayOfName, floatArrayOfName, booleanArrayOfName, charArrayOfName]
        builderDSLNames = [buildStringName, buildListName, buildSetName, buildMapName]

        stringProducingCallees = [
            interner.intern("kk_string_concat"),
            interner.intern("kk_string_trim"),
            interner.intern("kk_string_lowercase"),
            interner.intern("kk_string_uppercase"),
            interner.intern("kk_string_replace"),
            interner.intern("kk_string_replaceFirst"),
            interner.intern("kk_string_replaceAfter"),
            interner.intern("kk_string_replaceAfter_char"),
            interner.intern("kk_string_replaceAfterLast"),
            interner.intern("kk_string_replaceAfterLast_char"),
            interner.intern("kk_string_replaceBefore"),
            interner.intern("kk_string_replaceBefore_char"),
            interner.intern("kk_string_replaceBeforeLast"),
            interner.intern("kk_string_replaceBeforeLast_char"),
            interner.intern("kk_string_substring"),
            interner.intern("kk_string_padStart_default"),
            interner.intern("kk_string_padEnd_default"),
            interner.intern("kk_string_padStart"),
            interner.intern("kk_string_padEnd"),
            interner.intern("kk_string_repeat"),
            interner.intern("kk_string_reversed"),
            interner.intern("kk_string_take"),
            interner.intern("kk_string_drop"),
            interner.intern("kk_string_takeLast"),
            interner.intern("kk_string_dropLast"),
            interner.intern("kk_string_removePrefix"),
            interner.intern("kk_string_removeSuffix"),
            interner.intern("kk_string_removeSurrounding"),
            interner.intern("kk_string_removeRange"),
            interner.intern("kk_string_removeRange_range"),
            interner.intern("kk_string_substringBefore"),
            interner.intern("kk_string_substringAfter"),
            interner.intern("kk_string_substringBeforeLast"),
            interner.intern("kk_string_substringAfterLast"),
            interner.intern("kk_string_prependIndent_default"),
            interner.intern("kk_string_prependIndent"),
            interner.intern("kk_string_replaceIndent_default"),
            interner.intern("kk_string_replaceIndent"),
            interner.intern("kk_string_replaceIndentByMargin"),
            kkStringFilterName,
            interner.intern("kk_build_string"),
            interner.intern("kk_build_string_with_capacity"),
        ]
    }
}

// swiftformat:enable redundantMemberwiseInit
