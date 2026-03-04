// KSWIFTK_DIFF_IGNORE: Requires kotlinc with `data object` support.
data object None

fun main() {
    println(None)
    println(None == None)
    println(None.toString())
}
