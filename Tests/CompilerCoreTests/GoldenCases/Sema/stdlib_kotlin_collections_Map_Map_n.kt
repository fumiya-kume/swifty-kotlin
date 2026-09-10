package golden.sema

fun mapSize(values: Map<String, Int>): Int = values.size

fun mapKeys(values: Map<String, Int>): Set<String> = values.keys

fun mapValues(values: Map<String, Int>): Collection<Int> = values.values

fun mapEntries(values: Map<String, Int>) {
    values.entries
}

fun mapIsEmpty(values: Map<String, Int>): Boolean = values.isEmpty()

fun mapGet(values: Map<String, Int>): Int? = values["key"]
