import RuntimeABI

/// Sequence lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct SequenceLookupNames {
    // Sequence ABI names (STDLIB-003)
    let kkSequenceMapName: InternedString
    let kkSequenceFilterName: InternedString
    let kkSequenceRequireNoNullsName: InternedString
    let kkSequenceToListName: InternedString
    let kkSequenceConstrainOnceName: InternedString
    let kkSequenceBuilderBuildName: InternedString
    let kkSequenceBuilderYieldName: InternedString
    let kkSequenceBuilderYieldAllName: InternedString
    let kkIteratorBuilderBuildName: InternedString
    let kkIteratorBuilderHasNextName: InternedString
    let kkIteratorBuilderNextName: InternedString
    // Sequence ABI names (STDLIB-095)
    let kkSequenceFlatMapName: InternedString
    let kkSequenceFlatMapIndexedName: InternedString
    let kkSequenceShuffledName: InternedString
    let kkSequenceShuffledRandomName: InternedString
    // STDLIB-558, 559, 560: Sequence scan / runningFold / runningReduce
    let kkSequenceScanName: InternedString
    let kkSequenceRunningFoldName: InternedString
    let kkSequenceRunningReduceName: InternedString
    // STDLIB-470: Sequence terminal ops
    let kkSequenceToSetName: InternedString
    let kkSequenceToMapName: InternedString
    let kkSequenceToCollectionName: InternedString
    let kkSequenceGroupByName: InternedString
    let kkSequenceMaxName: InternedString
    let kkSequenceMaxOrNullName: InternedString
    let kkSequenceMinOrNullName: InternedString
    let kkSequenceFlattenName: InternedString
    let kkSequenceFoldName: InternedString
    let kkSequenceFoldIndexedName: InternedString
    let kkSequenceRunningFoldIndexedName: InternedString
    let kkSequenceScanIndexedName: InternedString
    let kkSequenceReduceIndexedName: InternedString
    let kkSequenceReduceIndexedOrNullName: InternedString
    let kkSequenceRunningReduceIndexedName: InternedString
    // STDLIB-561/562: Sequence plus/minus
    let kkSequencePlusName: InternedString
    let kkSequencePlusElementName: InternedString
    let kkSequenceMinusName: InternedString
    let kkSequenceOfSingleName: InternedString
    // STDLIB-SEQ-012: Sequence partition
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
    let toCharArrayName: InternedString
    let toBooleanArrayName: InternedString
    let toShortArrayName: InternedString
    let toDoubleArrayName: InternedString
    let toFloatArrayName: InternedString
    let toIntArrayName: InternedString
    let toLongArrayName: InternedString
    let toByteArrayName: InternedString
    let toSetName: InternedString
    let toMapName: InternedString
    let takeName: InternedString
    let sequenceName: InternedString
    let iteratorBuilderName: InternedString
    let yieldName: InternedString
    let yieldAllName: InternedString

    init(interner: StringInterner) {
        kkSequenceMapName = interner.intern("kk_sequence_map")
        kkSequenceFilterName = interner.intern("kk_sequence_filter")
        kkSequenceRequireNoNullsName = interner.intern("kk_sequence_requireNoNulls")
        kkSequenceToListName = interner.intern("kk_sequence_to_list")
        kkSequenceConstrainOnceName = interner.intern("kk_sequence_constrainOnce")
        kkSequenceBuilderBuildName = interner.intern("__kk_sequence_builder_build")
        kkSequenceBuilderYieldName = interner.intern("__kk_sequence_builder_yield")
        kkSequenceBuilderYieldAllName = interner.intern("__kk_sequence_builder_yieldAll")
        kkIteratorBuilderBuildName = interner.intern("__kk_iterator_builder_build")
        kkIteratorBuilderHasNextName = interner.intern("__kk_iterator_builder_hasNext")
        kkIteratorBuilderNextName = interner.intern("__kk_iterator_builder_next")
        kkSequenceFlatMapName = interner.intern("kk_sequence_flatMap")
        kkSequenceFlatMapIndexedName = interner.intern("kk_sequence_flatMapIndexed")
        kkSequenceShuffledName = interner.intern("kk_sequence_shuffled")
        kkSequenceShuffledRandomName = interner.intern("kk_sequence_shuffled_random")
        kkSequenceScanName = interner.intern("kk_sequence_scan")
        kkSequenceRunningFoldName = interner.intern("kk_sequence_runningFold")
        kkSequenceRunningReduceName = interner.intern("kk_sequence_runningReduce")
        kkSequenceToSetName = interner.intern("kk_sequence_toSet")
        kkSequenceToMapName = interner.intern("kk_sequence_toMap")
        kkSequenceToCollectionName = interner.intern("kk_sequence_toCollection")
        kkSequenceGroupByName = interner.intern("kk_sequence_groupBy")
        kkSequenceMaxName = interner.intern("kk_sequence_max")
        kkSequenceMaxOrNullName = interner.intern("kk_sequence_maxOrNull")
        kkSequenceMinOrNullName = interner.intern("kk_sequence_minOrNull")
        kkSequenceFlattenName = interner.intern("kk_sequence_flatten")
        kkSequenceFoldName = interner.intern("kk_sequence_fold")
        kkSequenceFoldIndexedName = interner.intern("kk_sequence_foldIndexed")
        kkSequenceRunningFoldIndexedName = interner.intern("kk_sequence_runningFoldIndexed")
        kkSequenceScanIndexedName = interner.intern("kk_sequence_scanIndexed")
        kkSequenceReduceIndexedName = interner.intern("kk_sequence_reduceIndexed")
        kkSequenceReduceIndexedOrNullName = interner.intern("kk_sequence_reduceIndexedOrNull")
        kkSequenceRunningReduceIndexedName = interner.intern("kk_sequence_runningReduceIndexed")
        kkSequencePlusName = interner.intern("kk_sequence_plus")
        kkSequencePlusElementName = interner.intern("kk_sequence_plus_element")
        kkSequenceMinusName = interner.intern("kk_sequence_minus")
        kkSequenceOfSingleName = interner.intern("kk_sequence_of_single")
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
        toCharArrayName = interner.intern("toCharArray")
        toBooleanArrayName = interner.intern("toBooleanArray")
        toShortArrayName = interner.intern("toShortArray")
        toDoubleArrayName = interner.intern("toDoubleArray")
        toFloatArrayName = interner.intern("toFloatArray")
        toIntArrayName = interner.intern("toIntArray")
        toLongArrayName = interner.intern("toLongArray")
        toByteArrayName = interner.intern("toByteArray")
        toSetName = interner.intern("toSet")
        toMapName = interner.intern("toMap")
        takeName = interner.intern("take")
        sequenceName = interner.intern("sequence")
        iteratorBuilderName = interner.intern("iterator")
        yieldName = interner.intern("yield")
        yieldAllName = interner.intern("yieldAll")
    }
}
