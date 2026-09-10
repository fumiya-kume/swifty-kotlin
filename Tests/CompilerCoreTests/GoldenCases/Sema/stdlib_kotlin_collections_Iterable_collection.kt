@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun knownCollectionSize(values: Iterable<Int>): Int? {
    return values.collectionSizeOrNull()
}

fun collectionSizeOrFallback(values: Iterable<String?>): Int {
    return values.collectionSizeOrDefault(17)
}
