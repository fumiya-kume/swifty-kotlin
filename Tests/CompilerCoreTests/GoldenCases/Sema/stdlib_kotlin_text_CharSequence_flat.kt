fun charSequenceFlatFamily(
    source: CharSequence,
    destination: MutableList<Any?>
) {
    val chars: List<Char> = source.flatMap { listOf(it) }
    val booleans: List<Boolean> = source.flatMapIndexed { index, _ -> listOf(index == 0) }
    val nullable: List<Int?> = source.flatMap { listOf<Int?>(null) }
    val flatTo: MutableList<Any?> = source.flatMapTo(destination) { listOf(it, null) }
    val indexedTo: MutableList<Any?> = source.flatMapIndexedTo(destination) { index, value ->
        listOf(index, value)
    }
    val empty: List<Any?> = "".flatMap { emptyList<Any?>() }
}
