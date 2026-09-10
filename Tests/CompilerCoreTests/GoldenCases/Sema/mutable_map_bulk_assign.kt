// RF-FIXTURE-019: MutableMap plusAssign / minusAssign / putAll overloads for
// Pair, Iterable, Sequence, Array, and Map operands.
fun plusAssignOverloads(
    map: MutableMap<String, Int?>,
    pair: Pair<String, Int?>,
    pairs: List<Pair<String, Int?>>,
    sequence: Sequence<Pair<String, Int?>>,
    array: Array<Pair<String, Int?>>,
    other: Map<String, Int?>
) {
    map += pair
    map += pairs
    map += sequence
    map += array
    map += other
}

fun minusAssignOverloads(
    map: MutableMap<String, Int?>,
    key: String,
    keys: List<String>,
    sequence: Sequence<String>,
    array: Array<String>
) {
    map -= key
    map -= keys
    map -= sequence
    map -= array
}

fun putAllOverloads(
    map: MutableMap<String, Int?>,
    pairs: List<Pair<String, Int?>>,
    sequence: Sequence<Pair<String, Int?>>,
    array: Array<Pair<String, Int?>>
) {
    map.putAll(pairs)
    map.putAll(sequence)
    map.putAll(array)
}
