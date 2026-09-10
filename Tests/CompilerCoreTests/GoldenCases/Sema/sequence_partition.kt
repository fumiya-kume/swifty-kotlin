// RF-FIXTURE-012: Sequence<T>.partition — the predicate receives T, the
// result is Pair<List<T>, List<T>>, and both sides destructure as List<T>.
// Execution (basic, empty, asSequence, all-match, none-match) is covered by
// Scripts/diff_cases/sequence_partition.kt and
// CodegenBackendIntegrationTests+SequenceEdgeCases.testCodegenSequencePartitionSplitsElements.

fun partitionSequence(values: Sequence<Int>) {
    val (matching, rest) = values.partition { it % 2 == 0 }
    val checkedMatching: List<Int> = matching
    val checkedRest: List<Int> = rest
}
