// RF-FIXTURE-004: Iterable.toMutableList / Collection.toMutableList return a
// mutable copy typed MutableList<T>, resolved through interface receivers.

fun iterableToMutableList(items: Iterable<Int>) {
    val mutable = items.toMutableList()
    val checked: MutableList<Int> = mutable
}

fun collectionToMutableList(items: Collection<String>) {
    val mutable = items.toMutableList()
    val checked: MutableList<String> = mutable
}
