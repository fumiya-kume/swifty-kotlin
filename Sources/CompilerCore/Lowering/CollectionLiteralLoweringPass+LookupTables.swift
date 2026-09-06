import RuntimeABI

// swiftformat:disable redundantMemberwiseInit
struct CollectionLiteralLookupTables {
    let listLookup: ListLookupNames
    let setLookup: SetLookupNames
    let mapLookup: MapLookupNames
    let sequenceLookup: SequenceLookupNames
    let arrayLookup: ArrayLookupNames
    let rangeLookup: RangeLookupNames
    let stringLookup: StringLookupNames
    let builderDSLLookup: BuilderDSLLookupNames
    let fileIOLookup: FileIOLookupNames
    let commonLookup: CommonLookupNames

    // Sequence factories that return a runtime RuntimeSequenceBox handle
    // (source body is only a thin bridge to a __kk_* / kk_* runtime entry).
    let sequenceRuntimeBridgeReturningNames: Set<InternedString>
    private let collectionHOFRuntimeNames: [CollectionHOFRuntimeKey: InternedString]

    init(interner: StringInterner) {
        listLookup = ListLookupNames(interner: interner)
        setLookup = SetLookupNames(interner: interner)
        mapLookup = MapLookupNames(interner: interner)
        sequenceLookup = SequenceLookupNames(interner: interner)
        arrayLookup = ArrayLookupNames(interner: interner)
        rangeLookup = RangeLookupNames(interner: interner)
        stringLookup = StringLookupNames(interner: interner)
        builderDSLLookup = BuilderDSLLookupNames(interner: interner)
        fileIOLookup = FileIOLookupNames(interner: interner)
        commonLookup = CommonLookupNames(interner: interner)

        sequenceRuntimeBridgeReturningNames = [
            interner.intern("lineSequence"),
            interner.intern("splitToSequence"),
            arrayLookup.kkListAsSequenceName,
            arrayLookup.kkArrayAsSequenceName
        ]
        collectionHOFRuntimeNames = Dictionary(uniqueKeysWithValues: StdlibSurfaceSpec.collectionHOFMembers.flatMap { spec in
            (spec.arity.minimum ... spec.arity.maximum).map { arity in
                (
                    CollectionHOFRuntimeKey(
                        ownerKind: spec.ownerKind,
                        memberName: interner.intern(spec.memberName),
                        arity: arity
                    ),
                    interner.intern(spec.runtimeLinkName)
                )
            }
        })
    }

    // MARK: - List lookup names (see CollectionLiteralLoweringPass+LookupTables+List.swift)

    var listOfName: InternedString { listLookup.listOfName }
    var mutableListOfName: InternedString { listLookup.mutableListOfName }
    var arrayListOfName: InternedString { listLookup.arrayListOfName }
    var emptyListName: InternedString { listLookup.emptyListName }
    var arrayListName: InternedString { listLookup.arrayListName }
    var kkListOfName: InternedString { listLookup.kkListOfName }
    var kkEmptyListName: InternedString { listLookup.kkEmptyListName }
    var kkListSizeName: InternedString { listLookup.kkListSizeName }
    var kkListGetName: InternedString { listLookup.kkListGetName }
    var kkListIsEmptyName: InternedString { listLookup.kkListIsEmptyName }
    var kkListIteratorName: InternedString { listLookup.kkListIteratorName }
    var kkListIteratorHasNextName: InternedString { listLookup.kkListIteratorHasNextName }
    var kkListIteratorNextName: InternedString { listLookup.kkListIteratorNextName }
    var kkListIteratorHasPreviousName: InternedString { listLookup.kkListIteratorHasPreviousName }
    var kkListIteratorPreviousName: InternedString { listLookup.kkListIteratorPreviousName }
    var kkListIteratorNextIndexName: InternedString { listLookup.kkListIteratorNextIndexName }
    var kkListIteratorPreviousIndexName: InternedString { listLookup.kkListIteratorPreviousIndexName }
    var kkListToStringName: InternedString { listLookup.kkListToStringName }
    var kkCollectionToMutableListName: InternedString { listLookup.kkCollectionToMutableListName }
    var kkListAssociateToName: InternedString { listLookup.kkListAssociateToName }
    var kkListForEachName: InternedString { listLookup.kkListForEachName }
    var kkCollectionToCollectionName: InternedString { listLookup.kkCollectionToCollectionName }
    var kkListGroupByName: InternedString { listLookup.kkListGroupByName }
    var kkListGroupByTransformName: InternedString { listLookup.kkListGroupByTransformName }
    var kkListSortedByName: InternedString { listLookup.kkListSortedByName }
    var kkListAssociateByName: InternedString { listLookup.kkListAssociateByName }
    var kkListAssociateByTransformName: InternedString { listLookup.kkListAssociateByTransformName }
    var kkListAssociateWithName: InternedString { listLookup.kkListAssociateWithName }
    var kkListAssociateName: InternedString { listLookup.kkListAssociateName }
    var kkListAssociateByToName: InternedString { listLookup.kkListAssociateByToName }
    var kkListAssociateWithToName: InternedString { listLookup.kkListAssociateWithToName }
    var kkListGroupByToName: InternedString { listLookup.kkListGroupByToName }
    var kkListZipBridgeName: InternedString { listLookup.kkListZipBridgeName }
    var kkListZipTransformBridgeName: InternedString { listLookup.kkListZipTransformBridgeName }
    var kkListZipWithNextBridgeName: InternedString { listLookup.kkListZipWithNextBridgeName }
    var kkListZipWithNextTransformBridgeName: InternedString { listLookup.kkListZipWithNextTransformBridgeName }
    var kkListUnzipName: InternedString { listLookup.kkListUnzipName }
    var kkIndexingIterableIteratorName: InternedString { listLookup.kkIndexingIterableIteratorName }
    var kkIndexingIterableHasNextName: InternedString { listLookup.kkIndexingIterableHasNextName }
    var kkIndexingIterableNextName: InternedString { listLookup.kkIndexingIterableNextName }
    var kkListOnEachName: InternedString { listLookup.kkListOnEachName }
    var kkListOnEachIndexedName: InternedString { listLookup.kkListOnEachIndexedName }
    var kkListMaxOrNullName: InternedString { listLookup.kkListMaxOrNullName }
    var kkListMinOrNullName: InternedString { listLookup.kkListMinOrNullName }
    var kkListMaxByName: InternedString { listLookup.kkListMaxByName }
    var kkListMinName: InternedString { listLookup.kkListMinName }
    var kkListMaxByOrNullName: InternedString { listLookup.kkListMaxByOrNullName }
    var kkListMinByOrNullName: InternedString { listLookup.kkListMinByOrNullName }
    var kkListMinByName: InternedString { listLookup.kkListMinByName }
    var kkListMaxOfOrNullName: InternedString { listLookup.kkListMaxOfOrNullName }
    var kkListMinOfOrNullName: InternedString { listLookup.kkListMinOfOrNullName }
    var kkListMaxOfName: InternedString { listLookup.kkListMaxOfName }
    var kkListMinOfName: InternedString { listLookup.kkListMinOfName }
    var kkListMaxWithName: InternedString { listLookup.kkListMaxWithName }
    var kkListMaxWithOrNullName: InternedString { listLookup.kkListMaxWithOrNullName }
    var kkListMinWithName: InternedString { listLookup.kkListMinWithName }
    var kkListMinWithOrNullName: InternedString { listLookup.kkListMinWithOrNullName }
    var kkListMaxOfWithName: InternedString { listLookup.kkListMaxOfWithName }
    var kkListMaxOfWithOrNullName: InternedString { listLookup.kkListMaxOfWithOrNullName }
    var kkListMinOfWithName: InternedString { listLookup.kkListMinOfWithName }
    var kkListMinOfWithOrNullName: InternedString { listLookup.kkListMinOfWithOrNullName }
    var kkListSortedName: InternedString { listLookup.kkListSortedName }
    var kkListShuffledName: InternedString { listLookup.kkListShuffledName }
    var kkListShuffledRandomName: InternedString { listLookup.kkListShuffledRandomName }
    var kkListChunkedBridgeName: InternedString { listLookup.kkListChunkedBridgeName }
    var kkListChunkedTransformBridgeName: InternedString { listLookup.kkListChunkedTransformBridgeName }
    var kkListWindowedBridgeName: InternedString { listLookup.kkListWindowedBridgeName }
    var kkListWindowedTransformBridgeName: InternedString { listLookup.kkListWindowedTransformBridgeName }
    var kkListSortedDescendingName: InternedString { listLookup.kkListSortedDescendingName }
    var kkListSortedByDescendingName: InternedString { listLookup.kkListSortedByDescendingName }
    var kkListSortedWithName: InternedString { listLookup.kkListSortedWithName }
    var kkListPartitionName: InternedString { listLookup.kkListPartitionName }
    var listIteratorMemberName: InternedString { listLookup.listIteratorMemberName }
    var hasPreviousName: InternedString { listLookup.hasPreviousName }
    var previousName: InternedString { listLookup.previousName }
    var nextIndexName: InternedString { listLookup.nextIndexName }
    var previousIndexName: InternedString { listLookup.previousIndexName }
    var listFactoryNames: Set<InternedString> { listLookup.listFactoryNames }
    var mutableListConstructorNames: Set<InternedString> { listLookup.mutableListConstructorNames }

    // MARK: - Set lookup names (see CollectionLiteralLoweringPass+LookupTables+Set.swift)

    var setOfName: InternedString { setLookup.setOfName }
    var setOfNotNullName: InternedString { setLookup.setOfNotNullName }
    var mutableSetOfName: InternedString { setLookup.mutableSetOfName }
    var linkedSetOfName: InternedString { setLookup.linkedSetOfName }
    var hashSetOfName: InternedString { setLookup.hashSetOfName }
    var emptySetName: InternedString { setLookup.emptySetName }
    var hashSetName: InternedString { setLookup.hashSetName }
    var linkedHashSetName: InternedString { setLookup.linkedHashSetName }
    var kkEmptySetName: InternedString { setLookup.kkEmptySetName }
    var kkSetOfName: InternedString { setLookup.kkSetOfName }
    var kkSetOfNotNullName: InternedString { setLookup.kkSetOfNotNullName }
    var kkSetSizeName: InternedString { setLookup.kkSetSizeName }
    var kkSetContainsName: InternedString { setLookup.kkSetContainsName }
    var kkSetIsEmptyName: InternedString { setLookup.kkSetIsEmptyName }
    var kkSetToStringName: InternedString { setLookup.kkSetToStringName }
    var kkIterableToMutableSetName: InternedString { setLookup.kkIterableToMutableSetName }
    var kkHashSetOfName: InternedString { setLookup.kkHashSetOfName }
    var kkIterableToHashSetName: InternedString { setLookup.kkIterableToHashSetName }
    var setFactoryNames: Set<InternedString> { setLookup.setFactoryNames }
    var mutableSetConstructorNames: Set<InternedString> { setLookup.mutableSetConstructorNames }

    // MARK: - Map lookup names (see CollectionLiteralLoweringPass+LookupTables+Map.swift)

    var mapOfName: InternedString { mapLookup.mapOfName }
    var mutableMapOfName: InternedString { mapLookup.mutableMapOfName }
    var hashMapOfName: InternedString { mapLookup.hashMapOfName }
    var linkedMapOfName: InternedString { mapLookup.linkedMapOfName }
    var emptyMapName: InternedString { mapLookup.emptyMapName }
    var hashMapName: InternedString { mapLookup.hashMapName }
    var linkedHashMapName: InternedString { mapLookup.linkedHashMapName }
    var kkEmptyMapName: InternedString { mapLookup.kkEmptyMapName }
    var kkMapOfName: InternedString { mapLookup.kkMapOfName }
    var kkHashMapOfName: InternedString { mapLookup.kkHashMapOfName }
    var kkMapSizeName: InternedString { mapLookup.kkMapSizeName }
    var kkMapGetName: InternedString { mapLookup.kkMapGetName }
    var kkMapIsEmptyName: InternedString { mapLookup.kkMapIsEmptyName }
    var kkMapForEachName: InternedString { mapLookup.kkMapForEachName }
    var kkMapMapName: InternedString { mapLookup.kkMapMapName }
    var kkMapFilterName: InternedString { mapLookup.kkMapFilterName }
    var kkMapFilterKeysName: InternedString { mapLookup.kkMapFilterKeysName }
    var kkMapFilterValuesName: InternedString { mapLookup.kkMapFilterValuesName }
    var kkMapMapValuesName: InternedString { mapLookup.kkMapMapValuesName }
    var kkMapMapKeysName: InternedString { mapLookup.kkMapMapKeysName }
    var kkMapCountName: InternedString { mapLookup.kkMapCountName }
    var kkMapAnyName: InternedString { mapLookup.kkMapAnyName }
    var kkMapAllName: InternedString { mapLookup.kkMapAllName }
    var kkMapNoneName: InternedString { mapLookup.kkMapNoneName }
    var kkMapFlatMapName: InternedString { mapLookup.kkMapFlatMapName }
    var kkMapMaxByOrNullName: InternedString { mapLookup.kkMapMaxByOrNullName }
    var kkMapMinByOrNullName: InternedString { mapLookup.kkMapMinByOrNullName }
    var kkMapToStringName: InternedString { mapLookup.kkMapToStringName }
    var kkMapIteratorName: InternedString { mapLookup.kkMapIteratorName }
    var kkMapIteratorHasNextName: InternedString { mapLookup.kkMapIteratorHasNextName }
    var kkMapIteratorNextName: InternedString { mapLookup.kkMapIteratorNextName }
    var kkMutableMapPutAllName: InternedString { mapLookup.kkMutableMapPutAllName }
    var mapFactoryNames: Set<InternedString> { mapLookup.mapFactoryNames }
    var mutableMapConstructorNames: Set<InternedString> { mapLookup.mutableMapConstructorNames }

    // MARK: - Sequence lookup names (see CollectionLiteralLoweringPass+LookupTables+Sequence.swift)

    var kkSequenceMapName: InternedString { sequenceLookup.kkSequenceMapName }
    var kkSequenceFilterName: InternedString { sequenceLookup.kkSequenceFilterName }
    var kkSequenceRequireNoNullsName: InternedString { sequenceLookup.kkSequenceRequireNoNullsName }
    var kkSequenceToListName: InternedString { sequenceLookup.kkSequenceToListName }
    var kkSequenceConstrainOnceName: InternedString { sequenceLookup.kkSequenceConstrainOnceName }
    var kkSequenceBuilderBuildName: InternedString { sequenceLookup.kkSequenceBuilderBuildName }
    var kkSequenceBuilderYieldName: InternedString { sequenceLookup.kkSequenceBuilderYieldName }
    var kkSequenceBuilderYieldAllName: InternedString { sequenceLookup.kkSequenceBuilderYieldAllName }
    var kkIteratorBuilderBuildName: InternedString { sequenceLookup.kkIteratorBuilderBuildName }
    var kkIteratorBuilderHasNextName: InternedString { sequenceLookup.kkIteratorBuilderHasNextName }
    var kkIteratorBuilderNextName: InternedString { sequenceLookup.kkIteratorBuilderNextName }
    var kkSequenceForEachName: InternedString { sequenceLookup.kkSequenceForEachName }
    var kkSequenceFlatMapName: InternedString { sequenceLookup.kkSequenceFlatMapName }
    var kkSequenceFlatMapIndexedName: InternedString { sequenceLookup.kkSequenceFlatMapIndexedName }
    var kkSequenceShuffledName: InternedString { sequenceLookup.kkSequenceShuffledName }
    var kkSequenceShuffledRandomName: InternedString { sequenceLookup.kkSequenceShuffledRandomName }
    var kkSequenceForEachIndexedName: InternedString { sequenceLookup.kkSequenceForEachIndexedName }
    var kkSequenceScanName: InternedString { sequenceLookup.kkSequenceScanName }
    var kkSequenceRunningFoldName: InternedString { sequenceLookup.kkSequenceRunningFoldName }
    var kkSequenceRunningReduceName: InternedString { sequenceLookup.kkSequenceRunningReduceName }
    var kkSequenceToSetName: InternedString { sequenceLookup.kkSequenceToSetName }
    var kkSequenceToMapName: InternedString { sequenceLookup.kkSequenceToMapName }
    var kkSequenceToCollectionName: InternedString { sequenceLookup.kkSequenceToCollectionName }
    var kkSequenceGroupByName: InternedString { sequenceLookup.kkSequenceGroupByName }
    var kkSequenceMaxName: InternedString { sequenceLookup.kkSequenceMaxName }
    var kkSequenceMaxOrNullName: InternedString { sequenceLookup.kkSequenceMaxOrNullName }
    var kkSequenceMinOrNullName: InternedString { sequenceLookup.kkSequenceMinOrNullName }
    var kkSequenceFlattenName: InternedString { sequenceLookup.kkSequenceFlattenName }
    var kkSequenceFoldName: InternedString { sequenceLookup.kkSequenceFoldName }
    var kkSequenceFoldIndexedName: InternedString { sequenceLookup.kkSequenceFoldIndexedName }
    var kkSequenceRunningFoldIndexedName: InternedString { sequenceLookup.kkSequenceRunningFoldIndexedName }
    var kkSequenceScanIndexedName: InternedString { sequenceLookup.kkSequenceScanIndexedName }
    var kkSequenceReduceIndexedName: InternedString { sequenceLookup.kkSequenceReduceIndexedName }
    var kkSequenceReduceIndexedOrNullName: InternedString { sequenceLookup.kkSequenceReduceIndexedOrNullName }
    var kkSequenceRunningReduceIndexedName: InternedString { sequenceLookup.kkSequenceRunningReduceIndexedName }
    var kkSequencePlusName: InternedString { sequenceLookup.kkSequencePlusName }
    var kkSequencePlusElementName: InternedString { sequenceLookup.kkSequencePlusElementName }
    var kkSequenceMinusName: InternedString { sequenceLookup.kkSequenceMinusName }
    var kkSequenceOfSingleName: InternedString { sequenceLookup.kkSequenceOfSingleName }
    var plusMemberName: InternedString { sequenceLookup.plusMemberName }
    var plusElementName: InternedString { sequenceLookup.plusElementName }
    var minusElementName: InternedString { sequenceLookup.minusElementName }
    var minusMemberName: InternedString { sequenceLookup.minusMemberName }
    var asSequenceName: InternedString { sequenceLookup.asSequenceName }
    var toListName: InternedString { sequenceLookup.toListName }
    var constrainOnceName: InternedString { sequenceLookup.constrainOnceName }
    var toCollectionName: InternedString { sequenceLookup.toCollectionName }
    var toUByteArrayName: InternedString { sequenceLookup.toUByteArrayName }
    var toUShortArrayName: InternedString { sequenceLookup.toUShortArrayName }
    var toUIntArrayName: InternedString { sequenceLookup.toUIntArrayName }
    var toULongArrayName: InternedString { sequenceLookup.toULongArrayName }
    var toCharArrayName: InternedString { sequenceLookup.toCharArrayName }
    var toBooleanArrayName: InternedString { sequenceLookup.toBooleanArrayName }
    var toShortArrayName: InternedString { sequenceLookup.toShortArrayName }
    var toDoubleArrayName: InternedString { sequenceLookup.toDoubleArrayName }
    var toFloatArrayName: InternedString { sequenceLookup.toFloatArrayName }
    var toIntArrayName: InternedString { sequenceLookup.toIntArrayName }
    var toLongArrayName: InternedString { sequenceLookup.toLongArrayName }
    var toByteArrayName: InternedString { sequenceLookup.toByteArrayName }
    var toSetName: InternedString { sequenceLookup.toSetName }
    var toMapName: InternedString { sequenceLookup.toMapName }
    var takeName: InternedString { sequenceLookup.takeName }
    var sequenceName: InternedString { sequenceLookup.sequenceName }
    var iteratorBuilderName: InternedString { sequenceLookup.iteratorBuilderName }
    var yieldName: InternedString { sequenceLookup.yieldName }
    var yieldAllName: InternedString { sequenceLookup.yieldAllName }

    // MARK: - Array lookup names (see CollectionLiteralLoweringPass+LookupTables+Array.swift)

    var arrayOfName: InternedString { arrayLookup.arrayOfName }
    var emptyArrayName: InternedString { arrayLookup.emptyArrayName }
    var intArrayOfName: InternedString { arrayLookup.intArrayOfName }
    var longArrayOfName: InternedString { arrayLookup.longArrayOfName }
    var shortArrayOfName: InternedString { arrayLookup.shortArrayOfName }
    var byteArrayOfName: InternedString { arrayLookup.byteArrayOfName }
    var ushortArrayOfName: InternedString { arrayLookup.ushortArrayOfName }
    var uintArrayOfName: InternedString { arrayLookup.uintArrayOfName }
    var doubleArrayOfName: InternedString { arrayLookup.doubleArrayOfName }
    var floatArrayOfName: InternedString { arrayLookup.floatArrayOfName }
    var booleanArrayOfName: InternedString { arrayLookup.booleanArrayOfName }
    var charArrayOfName: InternedString { arrayLookup.charArrayOfName }
    var kkEmptyArrayName: InternedString { arrayLookup.kkEmptyArrayName }
    var kkArraySizeName: InternedString { arrayLookup.kkArraySizeName }
    var kkArrayNewName: InternedString { arrayLookup.kkArrayNewName }
    var kkArraySetName: InternedString { arrayLookup.kkArraySetName }
    var kkArrayToListName: InternedString { arrayLookup.kkArrayToListName }
    var kkArrayToMutableListName: InternedString { arrayLookup.kkArrayToMutableListName }

    var kkArrayCopyOfName: InternedString { arrayLookup.kkArrayCopyOfName }
    var kkArrayFillName: InternedString { arrayLookup.kkArrayFillName }
    var kkListAsSequenceName: InternedString { arrayLookup.kkListAsSequenceName }
    var kkArrayAsSequenceName: InternedString { arrayLookup.kkArrayAsSequenceName }
    var kkArrayOfName: InternedString { arrayLookup.kkArrayOfName }
    var toMutableListName: InternedString { arrayLookup.toMutableListName }
    var toTypedArrayName: InternedString { arrayLookup.toTypedArrayName }
    var sliceArrayName: InternedString { arrayLookup.sliceArrayName }
    var reversedArrayName: InternedString { arrayLookup.reversedArrayName }
    var asListName: InternedString { arrayLookup.asListName }
    var copyOfName: InternedString { arrayLookup.copyOfName }
    var copyOfRangeName: InternedString { arrayLookup.copyOfRangeName }
    var fillName: InternedString { arrayLookup.fillName }
    var arrayOfFactoryNames: Set<InternedString> { arrayLookup.arrayOfFactoryNames }

    // MARK: - Range lookup names (see CollectionLiteralLoweringPass+LookupTables+Range.swift)

    var kkRangeIteratorName: InternedString { rangeLookup.kkRangeIteratorName }
    var kkRangeHasNextName: InternedString { rangeLookup.kkRangeHasNextName }
    var kkRangeNextName: InternedString { rangeLookup.kkRangeNextName }
    var kkOpRangeToName: InternedString { rangeLookup.kkOpRangeToName }
    var kkOpRangeUntilName: InternedString { rangeLookup.kkOpRangeUntilName }
    var kkOpULongRangeUntilName: InternedString { rangeLookup.kkOpULongRangeUntilName }
    var kkOpDownToName: InternedString { rangeLookup.kkOpDownToName }
    var kkOpStepName: InternedString { rangeLookup.kkOpStepName }
    var kkRangeFirstName: InternedString { rangeLookup.kkRangeFirstName }
    var kkRangeLastName: InternedString { rangeLookup.kkRangeLastName }
    var kkRangeEndExclusiveName: InternedString { rangeLookup.kkRangeEndExclusiveName }
    var kkRangeCountName: InternedString { rangeLookup.kkRangeCountName }
    var kkRangeToListName: InternedString { rangeLookup.kkRangeToListName }
    var kkRangeForEachName: InternedString { rangeLookup.kkRangeForEachName }
    var kkRangeMapName: InternedString { rangeLookup.kkRangeMapName }
    var kkRangeMapIndexedName: InternedString { rangeLookup.kkRangeMapIndexedName }
    var kkRangeMapNotNullName: InternedString { rangeLookup.kkRangeMapNotNullName }
    var kkRangeFilterName: InternedString { rangeLookup.kkRangeFilterName }
    var kkRangeFilterIndexedName: InternedString { rangeLookup.kkRangeFilterIndexedName }
    var kkRangeFilterNotName: InternedString { rangeLookup.kkRangeFilterNotName }
    var kkRangeReduceName: InternedString { rangeLookup.kkRangeReduceName }
    var kkRangeReduceIndexedName: InternedString { rangeLookup.kkRangeReduceIndexedName }
    var kkRangeFoldName: InternedString { rangeLookup.kkRangeFoldName }
    var kkRangeFoldIndexedName: InternedString { rangeLookup.kkRangeFoldIndexedName }
    var kkRangeFindName: InternedString { rangeLookup.kkRangeFindName }
    var kkRangeFindLastName: InternedString { rangeLookup.kkRangeFindLastName }
    var kkRangeFirstPredicateName: InternedString { rangeLookup.kkRangeFirstPredicateName }
    var kkRangeFirstOrNullPredicateName: InternedString { rangeLookup.kkRangeFirstOrNullPredicateName }
    var kkRangeLastPredicateName: InternedString { rangeLookup.kkRangeLastPredicateName }
    var kkRangeLastOrNullPredicateName: InternedString { rangeLookup.kkRangeLastOrNullPredicateName }
    var kkRangeAnyName: InternedString { rangeLookup.kkRangeAnyName }
    var kkRangeAllName: InternedString { rangeLookup.kkRangeAllName }
    var kkRangeNoneName: InternedString { rangeLookup.kkRangeNoneName }
    var kkRangeChunkedName: InternedString { rangeLookup.kkRangeChunkedName }
    var kkRangeWindowedName: InternedString { rangeLookup.kkRangeWindowedName }
    var kkRangeStepName: InternedString { rangeLookup.kkRangeStepName }
    var kkRangeReversedName: InternedString { rangeLookup.kkRangeReversedName }
    var kkRangeIsEmptyName: InternedString { rangeLookup.kkRangeIsEmptyName }
    var kkRangeSumName: InternedString { rangeLookup.kkRangeSumName }
    var kkRangeToIntArrayName: InternedString { rangeLookup.kkRangeToIntArrayName }
    var kkRangeTakeName: InternedString { rangeLookup.kkRangeTakeName }
    var kkRangeDropName: InternedString { rangeLookup.kkRangeDropName }
    var kkRangeAverageName: InternedString { rangeLookup.kkRangeAverageName }
    var kkRangeSortedName: InternedString { rangeLookup.kkRangeSortedName }
    var kkOpContainsName: InternedString { rangeLookup.kkOpContainsName }
    var kkBoxCharName: InternedString { rangeLookup.kkBoxCharName }
    var kkCharRangeToListName: InternedString { rangeLookup.kkCharRangeToListName }
    var kkCharRangeForEachName: InternedString { rangeLookup.kkCharRangeForEachName }
    var kkULongRangeToListName: InternedString { rangeLookup.kkULongRangeToListName }
    var kkULongRangeContainsName: InternedString { rangeLookup.kkULongRangeContainsName }
    var kkULongRangeFirstName: InternedString { rangeLookup.kkULongRangeFirstName }
    var kkULongRangeLastName: InternedString { rangeLookup.kkULongRangeLastName }
    var kkULongRangeStepName: InternedString { rangeLookup.kkULongRangeStepName }
    var kkULongRangeIsEmptyName: InternedString { rangeLookup.kkULongRangeIsEmptyName }
    var kkULongRangeReversedName: InternedString { rangeLookup.kkULongRangeReversedName }
    var kkULongRangeToULongArrayName: InternedString { rangeLookup.kkULongRangeToULongArrayName }
    var kkULongRangeCountName: InternedString { rangeLookup.kkULongRangeCountName }
    var kkULongRangeIteratorName: InternedString { rangeLookup.kkULongRangeIteratorName }
    var kkULongRangeHasNextName: InternedString { rangeLookup.kkULongRangeHasNextName }
    var kkULongRangeNextName: InternedString { rangeLookup.kkULongRangeNextName }
    var kkULongRangeForEachName: InternedString { rangeLookup.kkULongRangeForEachName }
    var kkULongRangeMapName: InternedString { rangeLookup.kkULongRangeMapName }
    var kkLongRangeToLongArrayName: InternedString { rangeLookup.kkLongRangeToLongArrayName }

    // MARK: - String lookup names (see CollectionLiteralLoweringPass+LookupTables+String.swift)

    var kkStringSplitName: InternedString { stringLookup.kkStringSplitName }
    var stringProducingCallees: Set<InternedString> { stringLookup.stringProducingCallees }

    // MARK: - Comparator lookup names (see CollectionLiteralLoweringPass+LookupTables+Comparator.swift)


    // MARK: - BuilderDSL lookup names (see CollectionLiteralLoweringPass+LookupTables+BuilderDSL.swift)

    var buildListName: InternedString { builderDSLLookup.buildListName }
    var buildSetName: InternedString { builderDSLLookup.buildSetName }
    var buildMapName: InternedString { builderDSLLookup.buildMapName }
    var kkBuildListName: InternedString { builderDSLLookup.kkBuildListName }
    var kkBuildListWithCapacityName: InternedString { builderDSLLookup.kkBuildListWithCapacityName }
    var kkBuildSetName: InternedString { builderDSLLookup.kkBuildSetName }
    var kkBuildSetWithCapacityName: InternedString { builderDSLLookup.kkBuildSetWithCapacityName }
    var kkBuildMapName: InternedString { builderDSLLookup.kkBuildMapName }
    var kkBuildMapWithCapacityName: InternedString { builderDSLLookup.kkBuildMapWithCapacityName }
    var kkMutableSetAddName: InternedString { builderDSLLookup.kkMutableSetAddName }
    var kkMutableSetRemoveName: InternedString { builderDSLLookup.kkMutableSetRemoveName }
    var builderDSLNames: Set<InternedString> { builderDSLLookup.builderDSLNames }

    // MARK: - FileIO lookup names (see CollectionLiteralLoweringPass+LookupTables+FileIO.swift)

    var deleteName: InternedString { fileIOLookup.deleteName }
    var lengthName: InternedString { fileIOLookup.lengthName }
    var fileConstructorName: InternedString { fileIOLookup.fileConstructorName }
    var kkFileNewName: InternedString { fileIOLookup.kkFileNewName }
    var readTextName: InternedString { fileIOLookup.readTextName }
    var kkFileReadTextName: InternedString { fileIOLookup.kkFileReadTextName }
    var writeTextName: InternedString { fileIOLookup.writeTextName }
    var kkFileWriteTextName: InternedString { fileIOLookup.kkFileWriteTextName }
    var appendTextName: InternedString { fileIOLookup.appendTextName }
    var kkFileAppendTextName: InternedString { fileIOLookup.kkFileAppendTextName }
    var existsName: InternedString { fileIOLookup.existsName }
    var kkFileExistsName: InternedString { fileIOLookup.kkFileExistsName }
    var isFileName: InternedString { fileIOLookup.isFileName }
    var kkFileIsFileName: InternedString { fileIOLookup.kkFileIsFileName }
    var isDirectoryName: InternedString { fileIOLookup.isDirectoryName }
    var kkFileIsDirectoryName: InternedString { fileIOLookup.kkFileIsDirectoryName }
    var kkBufferedReaderForEachLineName: InternedString { fileIOLookup.kkBufferedReaderForEachLineName }
    var forEachBlockName: InternedString { fileIOLookup.forEachBlockName }
    var kkFileForEachBlockName: InternedString { fileIOLookup.kkFileForEachBlockName }
    var kkFileForEachBlockBlockSizeName: InternedString { fileIOLookup.kkFileForEachBlockBlockSizeName }
    var kkBufferedReaderUseLinesName: InternedString { fileIOLookup.kkBufferedReaderUseLinesName }
    var kkPathUseLinesName: InternedString { fileIOLookup.kkPathUseLinesName }
    var kkPathUseLinesDefaultName: InternedString { fileIOLookup.kkPathUseLinesDefaultName }
    var kkPathWalkName: InternedString { fileIOLookup.kkPathWalkName }
    var bufferedReaderName: InternedString { fileIOLookup.bufferedReaderName }
    var kkFileBufferedReaderName: InternedString { fileIOLookup.kkFileBufferedReaderName }
    var bufferedWriterName: InternedString { fileIOLookup.bufferedWriterName }
    var kkFileBufferedWriterName: InternedString { fileIOLookup.kkFileBufferedWriterName }
    var kkFileDeleteName: InternedString { fileIOLookup.kkFileDeleteName }
    var mkdirsName: InternedString { fileIOLookup.mkdirsName }
    var kkFileMkdirsName: InternedString { fileIOLookup.kkFileMkdirsName }
    var listFilesName: InternedString { fileIOLookup.listFilesName }
    var kkFileListFilesName: InternedString { fileIOLookup.kkFileListFilesName }
    var walkName: InternedString { fileIOLookup.walkName }
    var kkFileWalkName: InternedString { fileIOLookup.kkFileWalkName }
    var readBytesName: InternedString { fileIOLookup.readBytesName }
    var kkFileReadBytesName: InternedString { fileIOLookup.kkFileReadBytesName }
    var appendBytesName: InternedString { fileIOLookup.appendBytesName }
    var kkFileAppendBytesName: InternedString { fileIOLookup.kkFileAppendBytesName }
    var writeBytesName: InternedString { fileIOLookup.writeBytesName }
    var kkFileWriteBytesName: InternedString { fileIOLookup.kkFileWriteBytesName }
    var absolutePathName: InternedString { fileIOLookup.absolutePathName }
    var kkFileAbsolutePathName: InternedString { fileIOLookup.kkFileAbsolutePathName }
    var canonicalPathName: InternedString { fileIOLookup.canonicalPathName }
    var kkFileCanonicalPathName: InternedString { fileIOLookup.kkFileCanonicalPathName }
    var kkFileLengthName: InternedString { fileIOLookup.kkFileLengthName }
    var lastModifiedName: InternedString { fileIOLookup.lastModifiedName }
    var kkFileLastModifiedName: InternedString { fileIOLookup.kkFileLastModifiedName }
    var createNewFileName: InternedString { fileIOLookup.createNewFileName }
    var kkFileCreateNewFileName: InternedString { fileIOLookup.kkFileCreateNewFileName }
    var canReadName: InternedString { fileIOLookup.canReadName }
    var kkFileCanReadName: InternedString { fileIOLookup.kkFileCanReadName }
    var canWriteName: InternedString { fileIOLookup.canWriteName }
    var kkFileCanWriteName: InternedString { fileIOLookup.kkFileCanWriteName }
    var canExecuteName: InternedString { fileIOLookup.canExecuteName }
    var kkFileCanExecuteName: InternedString { fileIOLookup.kkFileCanExecuteName }
    var kkFileNewParentChildName: InternedString { fileIOLookup.kkFileNewParentChildName }
    var printWriterName: InternedString { fileIOLookup.printWriterName }
    var kkFilePrintWriterName: InternedString { fileIOLookup.kkFilePrintWriterName }

    // MARK: - Common lookup names (see CollectionLiteralLoweringPass+LookupTables+Common.swift)

    var sumName: InternedString { commonLookup.sumName }
    var sizeName: InternedString { commonLookup.sizeName }
    var getName: InternedString { commonLookup.getName }
    var containsName: InternedString { commonLookup.containsName }
    var containsAllName: InternedString { commonLookup.containsAllName }
    var containsKeyName: InternedString { commonLookup.containsKeyName }
    var containsValueName: InternedString { commonLookup.containsValueName }
    var isEmptyName: InternedString { commonLookup.isEmptyName }
    var countName: InternedString { commonLookup.countName }
    var addName: InternedString { commonLookup.addName }
    var removeName: InternedString { commonLookup.removeName }
    var firstName: InternedString { commonLookup.firstName }
    var lastName: InternedString { commonLookup.lastName }
    var startName: InternedString { commonLookup.startName }
    var endInclusiveName: InternedString { commonLookup.endInclusiveName }
    var endExclusiveName: InternedString { commonLookup.endExclusiveName }
    var stepName: InternedString { commonLookup.stepName }
    var iteratorName: InternedString { commonLookup.iteratorName }
    var mapName: InternedString { commonLookup.mapName }
    var filterName: InternedString { commonLookup.filterName }
    var filterNotName: InternedString { commonLookup.filterNotName }
    var mapNotNullName: InternedString { commonLookup.mapNotNullName }
    var filterNotNullName: InternedString { commonLookup.filterNotNullName }
    var requireNoNullsName: InternedString { commonLookup.requireNoNullsName }
    var filterToName: InternedString { commonLookup.filterToName }
    var filterNotToName: InternedString { commonLookup.filterNotToName }
    var mapToName: InternedString { commonLookup.mapToName }
    var flatMapToName: InternedString { commonLookup.flatMapToName }
    var mapNotNullToName: InternedString { commonLookup.mapNotNullToName }
    var mapIndexedToName: InternedString { commonLookup.mapIndexedToName }
    var mapIndexedNotNullToName: InternedString { commonLookup.mapIndexedNotNullToName }
    var flatMapIndexedToName: InternedString { commonLookup.flatMapIndexedToName }
    var filterIsInstanceToName: InternedString { commonLookup.filterIsInstanceToName }
    var filterIndexedToName: InternedString { commonLookup.filterIndexedToName }
    var filterNotNullToName: InternedString { commonLookup.filterNotNullToName }
    var forEachName: InternedString { commonLookup.forEachName }
    var flatMapName: InternedString { commonLookup.flatMapName }
    var flatMapIndexedName: InternedString { commonLookup.flatMapIndexedName }
    var anyName: InternedString { commonLookup.anyName }
    var noneName: InternedString { commonLookup.noneName }
    var allName: InternedString { commonLookup.allName }
    var foldName: InternedString { commonLookup.foldName }
    var foldRightName: InternedString { commonLookup.foldRightName }
    var reduceName: InternedString { commonLookup.reduceName }
    var reduceRightName: InternedString { commonLookup.reduceRightName }
    var reduceOrNullName: InternedString { commonLookup.reduceOrNullName }
    var scanName: InternedString { commonLookup.scanName }
    var runningFoldName: InternedString { commonLookup.runningFoldName }
    var runningReduceName: InternedString { commonLookup.runningReduceName }
    var scanReduceName: InternedString { commonLookup.scanReduceName }
    var groupByName: InternedString { commonLookup.groupByName }
    var sortedByName: InternedString { commonLookup.sortedByName }
    var findName: InternedString { commonLookup.findName }
    var findLastName: InternedString { commonLookup.findLastName }
    var associateByName: InternedString { commonLookup.associateByName }
    var associateWithName: InternedString { commonLookup.associateWithName }
    var associateName: InternedString { commonLookup.associateName }
    var associateToName: InternedString { commonLookup.associateToName }
    var associateByToName: InternedString { commonLookup.associateByToName }
    var associateWithToName: InternedString { commonLookup.associateWithToName }
    var groupByToName: InternedString { commonLookup.groupByToName }
    var mapValuesName: InternedString { commonLookup.mapValuesName }
    var mapValuesToName: InternedString { commonLookup.mapValuesToName }
    var mapKeysName: InternedString { commonLookup.mapKeysName }
    var mapKeysToName: InternedString { commonLookup.mapKeysToName }
    var filterKeysName: InternedString { commonLookup.filterKeysName }
    var filterValuesName: InternedString { commonLookup.filterValuesName }
    var zipName: InternedString { commonLookup.zipName }
    var zipWithNextName: InternedString { commonLookup.zipWithNextName }
    var unzipName: InternedString { commonLookup.unzipName }
    var withIndexName: InternedString { commonLookup.withIndexName }
    var forEachIndexedName: InternedString { commonLookup.forEachIndexedName }
    var onEachName: InternedString { commonLookup.onEachName }
    var onEachIndexedName: InternedString { commonLookup.onEachIndexedName }
    var mapIndexedName: InternedString { commonLookup.mapIndexedName }
    var mapIndexedNotNullName: InternedString { commonLookup.mapIndexedNotNullName }
    var foldIndexedName: InternedString { commonLookup.foldIndexedName }
    var foldRightIndexedName: InternedString { commonLookup.foldRightIndexedName }
    var reduceRightIndexedName: InternedString { commonLookup.reduceRightIndexedName }
    var reduceRightIndexedOrNullName: InternedString { commonLookup.reduceRightIndexedOrNullName }
    var reduceRightOrNullName: InternedString { commonLookup.reduceRightOrNullName }
    var reduceIndexedName: InternedString { commonLookup.reduceIndexedName }
    var filterIndexedName: InternedString { commonLookup.filterIndexedName }
    var reduceIndexedOrNullName: InternedString { commonLookup.reduceIndexedOrNullName }
    var runningFoldIndexedName: InternedString { commonLookup.runningFoldIndexedName }
    var runningReduceIndexedName: InternedString { commonLookup.runningReduceIndexedName }
    var scanIndexedName: InternedString { commonLookup.scanIndexedName }
    var sumOfName: InternedString { commonLookup.sumOfName }
    var sumByName: InternedString { commonLookup.sumByName }
    var sumByDoubleName: InternedString { commonLookup.sumByDoubleName }
    var maxName: InternedString { commonLookup.maxName }
    var maxOrNullName: InternedString { commonLookup.maxOrNullName }
    var minOrNullName: InternedString { commonLookup.minOrNullName }
    var maxByName: InternedString { commonLookup.maxByName }
    var minName: InternedString { commonLookup.minName }
    var maxByOrNullName: InternedString { commonLookup.maxByOrNullName }
    var minByOrNullName: InternedString { commonLookup.minByOrNullName }
    var minByName: InternedString { commonLookup.minByName }
    var maxOfOrNullName: InternedString { commonLookup.maxOfOrNullName }
    var minOfOrNullName: InternedString { commonLookup.minOfOrNullName }
    var maxOfName: InternedString { commonLookup.maxOfName }
    var minOfName: InternedString { commonLookup.minOfName }
    var maxWithName: InternedString { commonLookup.maxWithName }
    var maxWithOrNullName: InternedString { commonLookup.maxWithOrNullName }
    var minWithName: InternedString { commonLookup.minWithName }
    var minWithOrNullName: InternedString { commonLookup.minWithOrNullName }
    var maxOfWithName: InternedString { commonLookup.maxOfWithName }
    var maxOfWithOrNullName: InternedString { commonLookup.maxOfWithOrNullName }
    var minOfWithName: InternedString { commonLookup.minOfWithName }
    var minOfWithOrNullName: InternedString { commonLookup.minOfWithOrNullName }
    var dropName: InternedString { commonLookup.dropName }
    var reversedName: InternedString { commonLookup.reversedName }
    var asReversedName: InternedString { commonLookup.asReversedName }
    var sortedName: InternedString { commonLookup.sortedName }
    var averageName: InternedString { commonLookup.averageName }
    var distinctName: InternedString { commonLookup.distinctName }
    var distinctByName: InternedString { commonLookup.distinctByName }
    var shuffledName: InternedString { commonLookup.shuffledName }
    var flattenName: InternedString { commonLookup.flattenName }
    var indexOfName: InternedString { commonLookup.indexOfName }
    var lastIndexOfName: InternedString { commonLookup.lastIndexOfName }
    var indexOfFirstName: InternedString { commonLookup.indexOfFirstName }
    var indexOfLastName: InternedString { commonLookup.indexOfLastName }
    var chunkedName: InternedString { commonLookup.chunkedName }
    var windowedName: InternedString { commonLookup.windowedName }
    var sortedDescendingName: InternedString { commonLookup.sortedDescendingName }
    var sortedByDescendingName: InternedString { commonLookup.sortedByDescendingName }
    var sortedWithName: InternedString { commonLookup.sortedWithName }
    var partitionName: InternedString { commonLookup.partitionName }
    var takeWhileName: InternedString { commonLookup.takeWhileName }
    var dropWhileName: InternedString { commonLookup.dropWhileName }
    var takeLastWhileName: InternedString { commonLookup.takeLastWhileName }
    var dropLastWhileName: InternedString { commonLookup.dropLastWhileName }
    var firstOrNullName: InternedString { commonLookup.firstOrNullName }
    var lastOrNullName: InternedString { commonLookup.lastOrNullName }
    var emptyListFQName: [InternedString] { commonLookup.emptyListFQName }
    var emptyArrayFQName: [InternedString] { commonLookup.emptyArrayFQName }
    var emptySetFQName: [InternedString] { commonLookup.emptySetFQName }
    var emptyMapFQName: [InternedString] { commonLookup.emptyMapFQName }
    var listOfFQName: [InternedString] { commonLookup.listOfFQName }
    var setOfFQName: [InternedString] { commonLookup.setOfFQName }
    var setOfNotNullFQName: [InternedString] { commonLookup.setOfNotNullFQName }
    var mapOfFQName: [InternedString] { commonLookup.mapOfFQName }
    var mutableListOfFQName: [InternedString] { commonLookup.mutableListOfFQName }
    var arrayListOfFQName: [InternedString] { commonLookup.arrayListOfFQName }
    var mutableSetOfFQName: [InternedString] { commonLookup.mutableSetOfFQName }
    var linkedSetOfFQName: [InternedString] { commonLookup.linkedSetOfFQName }
    var hashSetOfFQName: [InternedString] { commonLookup.hashSetOfFQName }
    var mutableMapOfFQName: [InternedString] { commonLookup.mutableMapOfFQName }
    var hashMapOfFQName: [InternedString] { commonLookup.hashMapOfFQName }
    var linkedMapOfFQName: [InternedString] { commonLookup.linkedMapOfFQName }
    var listOfNotNullFQName: [InternedString] { commonLookup.listOfNotNullFQName }
    var kotlinName: InternedString { commonLookup.kotlinName }
    var initName: InternedString { commonLookup.initName }
    var toName: InternedString { commonLookup.toName }
    var pairName: InternedString { commonLookup.pairName }
    var kkPairNewName: InternedString { commonLookup.kkPairNewName }
    var kkPairFirstName: InternedString { commonLookup.kkPairFirstName }
    var kkPairSecondName: InternedString { commonLookup.kkPairSecondName }
    var tripleName: InternedString { commonLookup.tripleName }
    var kkTripleNewName: InternedString { commonLookup.kkTripleNewName }

    func collectionHOFRuntimeName(
        ownerKind: StdlibSurfaceOwnerKind,
        callee: InternedString,
        arity: Int
    ) -> InternedString? {
        collectionHOFRuntimeNames[CollectionHOFRuntimeKey(ownerKind: ownerKind, memberName: callee, arity: arity)]
    }
}

// swiftformat:enable redundantMemberwiseInit

private struct CollectionHOFRuntimeKey: Hashable {
    let ownerKind: StdlibSurfaceOwnerKind
    let memberName: InternedString
    let arity: Int
}
