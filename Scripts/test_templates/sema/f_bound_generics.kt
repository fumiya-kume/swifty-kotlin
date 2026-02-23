package golden.sema

fun <T> max(a: T, b: T): T where T : Comparable<T> =
    if (a > b) a else b

fun useMax() {
    val m1 = max(1, 2)
    val m2 = max("a", "b")
}
