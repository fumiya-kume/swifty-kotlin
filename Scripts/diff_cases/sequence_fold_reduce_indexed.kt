// SKIP-DIFF  sequence HOF lowering does not yet rewrite fold/reduce through asSequence() (link error)
fun main() {
    // foldIndexed: accumulate with index
    val foldResult = listOf(10, 20, 30)
        .asSequence()
        .foldIndexed(0) { index, acc, element -> acc + index * element }
    println(foldResult)  // 0*10 + 1*20 + 2*30 = 0 + 20 + 60 = 80

    // reduceIndexed: reduce with index
    val reduceResult = listOf(1, 2, 3, 4)
        .asSequence()
        .reduceIndexed { index, acc, element -> acc + index * element }
    println(reduceResult)  // 1 + 1*2 + 2*3 + 3*4 = 1 + 2 + 6 + 12 = 21

    // foldIndexed with string accumulation
    val words = listOf("a", "b", "c")
        .asSequence()
        .foldIndexed("") { index, acc, element -> acc + "$index:$element " }
    println(words)  // "0:a 1:b 2:c "
}
