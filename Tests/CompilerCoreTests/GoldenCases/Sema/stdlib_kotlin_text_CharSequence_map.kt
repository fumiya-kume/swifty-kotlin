fun charSequenceMapFamily(
    source: CharSequence,
    destination: MutableList<Any?>
) {
    val indexedNotNull: List<Int> = source.mapIndexedNotNull { index, _ ->
        if (index == 0) index else null
    }
    val indexedNotNullTo: MutableList<Any?> = source.mapIndexedNotNullTo(destination) { index, _ ->
        if (index == 0) index else null
    }
    val indexedTo: MutableList<Any?> = source.mapIndexedTo(destination) { index, value ->
        if (index == 0) value else index
    }
    val notNullTo: MutableList<Any?> = source.mapNotNullTo(destination) {
        if (it == 'a') it.code else null
    }
    val mapTo: MutableList<Any?> = source.mapTo(destination) { it.code }
}
