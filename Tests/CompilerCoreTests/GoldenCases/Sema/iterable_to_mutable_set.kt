// RF-FIXTURE-004: Iterable.toMutableSet / Iterable.toHashSet produce mutable set
// copies; toHashSet's HashSet<T> result must remain assignable to MutableSet<T>.

fun iterableToMutableSet(items: Iterable<Int>) {
    val mutable = items.toMutableSet()
    val checked: MutableSet<Int> = mutable
}

fun iterableToHashSet(items: Iterable<Int>) {
    val hashSet = items.toHashSet()
    val checked: MutableSet<Int> = hashSet
}
