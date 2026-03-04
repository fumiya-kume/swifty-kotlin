// SKIP-DIFF
// F-bound generics: `a > b` in generic body not yet fully supported in kswiftc
fun <T> max(a: T, b: T): T where T : Comparable<T> =
    if (a > b) a else b

fun main() {
    println(max(1, 2))
    println(max("a", "b"))
}
